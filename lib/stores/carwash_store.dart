import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carwash_models.dart';
import '../models/falha_de_acao.dart';

/// LAVAGEM AUTO — store reativo do cliente.
/// Camada read-only: preço e transições passam SEMPRE por RPC no servidor
/// (`carwash_quote` / `create_carwash_booking`). Espelha o padrão do
/// `CleaningStore`, incluindo o espelho-do-servidor ao voltar ao foreground.
class CarwashStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  List<CarwashBooking> _bookings = const [];
  List<CarwashBooking> get bookings => _bookings;

  List<CarwashBooking> get activeBookings =>
      _bookings.where((b) => b.status.isActive).toList();
  List<CarwashBooking> get pastBookings =>
      _bookings.where((b) => !b.status.isActive).toList();

  CarwashBooking? _tracked;
  CarwashBooking? get tracked => _tracked;

  bool _busy = false;
  bool get busy => _busy;

  /// carwash_stripe_enabled — enquanto false, cartão/MB WAY aparecem como
  /// "brevemente" e o servidor recusa-os ANTES de tocar no Stripe.
  bool _stripeEnabled = false;
  bool get stripeEnabled => _stripeEnabled;

  /// carwash_interior_enabled — o terceiro serviço nasce desligado.
  bool _interiorEnabled = false;
  bool get interiorEnabled => _interiorEnabled;

  /// carwash_enabled — o "Em breve" da categoria. Enquanto false, o ladrilho
  /// nem aparece na grelha inicial: mais vale não mostrar do que mostrar e
  /// dar erro ao toque.
  bool _enabled = false;
  bool get enabled => _enabled;

  /// Serviços que o cliente pode escolher agora.
  List<CarwashServiceType> get availableServices => [
        CarwashServiceType.exterior,
        CarwashServiceType.full,
        if (_interiorEnabled) CarwashServiceType.interior,
      ];

  RealtimeChannel? _channel;

  // ══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> refreshSettings() async {
    try {
      final rows = await _sb
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', [
            'carwash_enabled',
            'carwash_stripe_enabled',
            'carwash_interior_enabled',
          ])
          .timeout(kAcaoTimeout);
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final on = m['value'] == true || m['value'].toString() == 'true';
        if (m['key'] == 'carwash_enabled') _enabled = on;
        if (m['key'] == 'carwash_stripe_enabled') _stripeEnabled = on;
        if (m['key'] == 'carwash_interior_enabled') _interiorEnabled = on;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('CarwashStore.refreshSettings => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PREÇO — fonte única no servidor
  // ══════════════════════════════════════════════════════════════════════════

  Future<CarwashQuote?> quote(CarwashServiceType type) async {
    try {
      final res = await _sb
          .rpc('carwash_quote', params: {'p_service_type': type.wire})
          .timeout(kAcaoTimeout);
      return CarwashQuote.fromJson(_asMap(res));
    } catch (e) {
      debugPrint('CarwashStore.quote => $e');
      return null;
    }
  }

  /// Preços dos serviços disponíveis, para os cartões do primeiro ecrã.
  Future<Map<CarwashServiceType, CarwashQuote>> quoteAll() async {
    final out = <CarwashServiceType, CarwashQuote>{};
    for (final t in availableServices) {
      final q = await quote(t);
      if (q != null) out[t] = q;
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CRIAR PEDIDO
  // ══════════════════════════════════════════════════════════════════════════

  Future<CarwashBooking?> createBooking({
    required CarwashServiceType serviceType,
    required String plate,
    required String clientPhone,
    required String whenMode, // 'now' | 'later'
    DateTime? scheduledAt,
    required String addressStreet,
    String addressCity = 'Guarda',
    String addressPostal = '',
    double? lat,
    double? lng,
    required String paymentMethod,
    String carMakeModel = '',
    String carColor = '',
    String pickupNotes = '',
    String notes = '',
    List<CarwashPhoto> photosClient = const [],
  }) async {
    _setBusy(true);
    try {
      final res = await criarComTectoSeguro(
        () => _sb.rpc('create_carwash_booking', params: {
          'p_service_type': serviceType.wire,
          'p_plate': plate,
          'p_client_phone': clientPhone,
          'p_when_mode': whenMode,
          'p_scheduled_at': (scheduledAt ?? DateTime.now()).toUtc().toIso8601String(),
          'p_address_street': addressStreet,
          'p_address_city': addressCity,
          'p_address_postal': addressPostal,
          'p_lat': lat,
          'p_lng': lng,
          'p_payment_method': paymentMethod,
          'p_car_make_model': carMakeModel,
          'p_car_color': carColor,
          'p_pickup_notes': pickupNotes,
          'p_notes': notes,
          'p_photos_client': photosClient.map((p) => p.toJson()).toList(),
        }),
        // Se o servidor for lento mas o pedido PASSAR, repetir e apanhar a
        // guarda do servidor prova que já ficou criado — evita o cliente
        // pedir duas lavagens sem saber.
        trabalho: TrabalhoEmCurso.lavagem,
      );
      final booking = CarwashBooking.fromSupabase(_asMap(res));
      _bookings = [booking, ..._bookings];
      _tracked = booking;
      _subscribeBooking(booking.id);
      notifyListeners();
      return booking;
    } catch (e) {
      debugPrint('CarwashStore.createBooking => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LEITURA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadMyBookings() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('carwash_bookings')
          .select()
          .eq('client_user_id', uid)
          .order('created_at', ascending: false)
          .timeout(kAcaoTimeout);
      _bookings = (rows as List)
          .map((r) => CarwashBooking.fromSupabase(Map<String, dynamic>.from(r as Map)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('CarwashStore.loadMyBookings => $e');
    }
  }

  void trackBooking(CarwashBooking booking) {
    _tracked = booking;
    _subscribeBooking(booking.id);
    notifyListeners();
  }

  void _subscribeBooking(String bookingId) {
    _unsubscribe();
    _channel = _sb.channel('carwash_booking_$bookingId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'carwash_bookings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: bookingId,
        ),
        callback: (payload) {
          final updated = CarwashBooking.fromSupabase(payload.newRecord);
          _tracked = updated;
          // Realtime substitui objetos — comparar por ID, nunca por referência.
          _bookings = [
            for (final b in _bookings) b.id == updated.id ? updated : b
          ];
          notifyListeners();
        },
      )
      ..subscribe();
  }

  /// Espelho do servidor ao voltar ao foreground: o realtime pode ter perdido
  /// eventos com a app em background — o ecrã nunca assume o estado local
  /// como verdade.
  Future<void> refreshTracked() async {
    final t = _tracked;
    if (t == null) return;
    try {
      final row = await _sb
          .from('carwash_bookings')
          .select()
          .eq('id', t.id)
          .maybeSingle()
          .timeout(kAcaoTimeout);
      if (row != null) {
        final updated = CarwashBooking.fromSupabase(Map<String, dynamic>.from(row));
        _tracked = updated;
        _bookings = [
          for (final b in _bookings) b.id == updated.id ? updated : b
        ];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CarwashStore.refreshTracked => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AÇÕES DO CLIENTE
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> cancelBooking(String bookingId, {String reason = ''}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('cancel_carwash_booking', params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
      }).timeout(kAcaoTimeout);
      final updated = CarwashBooking.fromSupabase(_asMap(res));
      _tracked = updated;
      _bookings = [for (final b in _bookings) b.id == updated.id ? updated : b];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CarwashStore.cancelBooking => $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> confirmCompletion(String bookingId, {int? rating, String? comment}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('carwash_confirm_completion', params: {
        'p_booking_id': bookingId,
        'p_rating': rating,
        'p_comment': comment,
      }).timeout(kAcaoTimeout);
      final updated = CarwashBooking.fromSupabase(_asMap(res));
      _tracked = updated;
      _bookings = [for (final b in _bookings) b.id == updated.id ? updated : b];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CarwashStore.confirmCompletion => $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGAMENTO — Edge Fn ISOLADA carwash-checkout
  // O preço vem SEMPRE do servidor. O Dart nunca manda valores.
  // O portão (carwash_payment_precheck) corre lá antes de tocar no Stripe.
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> createCardPayment(String bookingId,
      {String? savedPmId}) async {
    try {
      final res = await _sb.functions.invoke('carwash-checkout', body: {
        'action': 'create',
        'bookingId': bookingId,
        if (savedPmId != null) 'saved_pm_id': savedPmId,
      });
      final data = res.data;
      if (data is Map && data['clientSecret'] != null) {
        return Map<String, dynamic>.from(data);
      }
      debugPrint('CarwashStore.createCardPayment resposta má => $data');
      return null;
    } catch (e) {
      debugPrint('CarwashStore.createCardPayment => $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> createMbwayPayment(
      String bookingId, String phone) async {
    try {
      final res = await _sb.functions.invoke('carwash-checkout', body: {
        'action': 'create_mbway',
        'bookingId': bookingId,
        'phone': phone,
      });
      final data = res.data;
      if (data is Map && data['paymentIntentId'] != null) {
        return Map<String, dynamic>.from(data);
      }
      debugPrint('CarwashStore.createMbwayPayment resposta má => $data');
      return null;
    } catch (e) {
      debugPrint('CarwashStore.createMbwayPayment => $e');
      return null;
    }
  }

  /// Marca o pedido como pago. O servidor revalida o PaymentIntent (dono,
  /// pedido e valor) antes de aceitar.
  Future<bool> markPaymentHeld(String bookingId, String paymentIntentId) async {
    try {
      final res = await _sb.functions.invoke('carwash-checkout', body: {
        'action': 'mark_held',
        'bookingId': bookingId,
        'paymentIntentId': paymentIntentId,
      });
      final ok = res.data is Map && (res.data as Map)['ok'] == true;
      if (ok) await refreshTracked();
      return ok;
    } catch (e) {
      debugPrint('CarwashStore.markPaymentHeld => $e');
      return false;
    }
  }

  /// Pedido cancelado: liberta a retenção ou estorna o que exceder a taxa.
  Future<void> reversePayment(String bookingId) async {
    try {
      await _sb.functions.invoke('carwash-checkout',
          body: {'action': 'reverse', 'bookingId': bookingId});
    } catch (e) {
      debugPrint('CarwashStore.reversePayment => $e');
    }
  }

  /// Anexa a foto opcional do cliente depois do pedido criado.
  /// Falhar aqui NUNCA estraga o pedido — a foto é opcional por desenho.
  Future<void> attachClientPhoto(String bookingId, String path) async {
    try {
      await _sb.from('carwash_bookings').update({
        'photos_client': [
          {'angle': '', 'url': path}
        ]
      }).eq('id', bookingId).timeout(kAcaoTimeout);
    } catch (e) {
      debugPrint('CarwashStore.attachClientPhoto => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INTERNOS
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    throw StateError('Resposta inesperada da RPC: $res');
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) _sb.removeChannel(ch);
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
