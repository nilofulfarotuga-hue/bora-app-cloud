import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cleaning_models.dart';

/// LIMPEZA — store reativo do cliente. Camada read-only: preço e transições
/// passam SEMPRE por RPC no backend (cleaning_quote / create_cleaning_booking).
/// Espelha o padrão TvdeStore (vertical paralela, realtime por reserva).
class CleaningStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  // ── Reservas do cliente ──────────────────────────────────────────────────
  List<CleaningBooking> _bookings = const [];
  List<CleaningBooking> get bookings => _bookings;

  List<CleaningBooking> get activeBookings =>
      _bookings.where((b) => b.status.isActive).toList();
  List<CleaningBooking> get pastBookings =>
      _bookings.where((b) => !b.status.isActive).toList();

  /// Reserva aberta no ecrã de acompanhamento (atualizada por realtime).
  CleaningBooking? _tracked;
  CleaningBooking? get tracked => _tracked;

  bool _busy = false;
  bool get busy => _busy;

  /// cleaning_stripe_enabled — enquanto false, cartão/MB Way ficam
  /// "brevemente" no wizard (Lista Vermelha: cobrança real só após "vai").
  bool _stripeEnabled = false;
  bool get stripeEnabled => _stripeEnabled;

  RealtimeChannel? _channel;

  // ══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  /// Lê um setting via get_setting; devolve [fallback] em erro (padrão TvdeStore).
  Future<int> getSettingInt(String key, int fallback) async {
    try {
      final res = await _sb.rpc('get_setting', params: {'p_key': key});
      if (res == null) return fallback;
      return int.tryParse(res.toString()) ?? fallback;
    } catch (e) {
      debugPrint('CleaningStore.getSettingInt($key) error => $e');
      return fallback;
    }
  }

  Future<void> refreshStripeEnabled() async {
    try {
      final res = await _sb
          .rpc('get_setting', params: {'p_key': 'cleaning_stripe_enabled'});
      _stripeEnabled = res?.toString() == 'true';
      notifyListeners();
    } catch (e) {
      debugPrint('CleaningStore.refreshStripeEnabled error => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ORÇAMENTO + PROFISSIONAIS DISPONÍVEIS (wizard)
  // ══════════════════════════════════════════════════════════════════════════

  /// Orçamento server-side (RPC cleaning_quote). null em erro.
  Future<CleaningQuote?> quote({
    required String cleaningType,
    required String pricingMode,
    String? homeSize,
    int? hours,
    String recurrence = 'single',
    String productsBy = 'client',
  }) async {
    try {
      final res = await _sb.rpc('cleaning_quote', params: {
        'p_cleaning_type': cleaningType,
        'p_pricing_mode': pricingMode,
        'p_home_size': homeSize,
        'p_hours': hours,
        'p_recurrence': recurrence,
        'p_products_by': productsBy,
      });
      return CleaningQuote.fromJson(_asMap(res));
    } catch (e) {
      debugPrint('CleaningStore.quote error => $e');
      return null;
    }
  }

  /// Profissionais aprovadas + disponíveis no slot (Passo 3 do wizard).
  Future<List<AvailableCleaner>> listAvailableCleaners({
    required DateTime scheduledAt,
    required int durationMin,
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await _sb.rpc('cleaning_list_available_cleaners', params: {
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_duration_min': durationMin,
        'p_lat': lat,
        'p_lng': lng,
      });
      if (res is! List) return const [];
      return res
          .map((m) => AvailableCleaner.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('CleaningStore.listAvailableCleaners error => $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESERVA
  // ══════════════════════════════════════════════════════════════════════════

  /// Cria a reserva (preço 100% server-side) e começa a segui-la ao vivo.
  Future<CleaningBooking?> createBooking({
    required String cleaningType,
    required String pricingMode,
    String? homeSize,
    int? hours,
    required DateTime scheduledAt,
    required String recurrence,
    required String productsBy,
    required String paymentMethod,
    required String addressStreet,
    required String addressCity,
    required String addressPostal,
    double? lat,
    double? lng,
    String notes = '',
    String? requestedCleanerId,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('create_cleaning_booking', params: {
        'p_cleaning_type': cleaningType,
        'p_pricing_mode': pricingMode,
        'p_home_size': homeSize,
        'p_hours': hours,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_recurrence': recurrence,
        'p_products_by': productsBy,
        'p_payment_method': paymentMethod,
        'p_address_street': addressStreet,
        'p_address_city': addressCity,
        'p_address_postal': addressPostal,
        'p_lat': lat,
        'p_lng': lng,
        'p_notes': notes,
        'p_requested_cleaner_id': requestedCleanerId,
      });
      final booking = CleaningBooking.fromSupabase(_asMap(res));
      _tracked = booking;
      _subscribeBooking(booking.id);
      await loadMyBookings();
      return booking;
    } catch (e) {
      debugPrint('CleaningStore.createBooking error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Carrega as reservas do cliente (ativas + histórico, mais recentes primeiro).
  Future<void> loadMyBookings() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('cleaning_bookings')
          .select()
          .eq('client_user_id', uid)
          .order('scheduled_at', ascending: false)
          .limit(50);
      _bookings =
          rows.map<CleaningBooking>(CleaningBooking.fromSupabase).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('CleaningStore.loadMyBookings error => $e');
    }
  }

  /// Abre uma reserva no acompanhamento e liga o realtime dela.
  void trackBooking(CleaningBooking booking) {
    _tracked = booking;
    _subscribeBooking(booking.id);
    notifyListeners();
  }

  void _subscribeBooking(String bookingId) {
    _unsubscribe();
    _channel = _sb.channel('cleaning_booking_$bookingId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'cleaning_bookings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: bookingId,
        ),
        callback: (payload) {
          final updated = CleaningBooking.fromSupabase(payload.newRecord);
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

  /// Fecha o acompanhamento (após concluir/cancelar/sair do ecrã).
  void clearTracked() {
    _unsubscribe();
    _tracked = null;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AÇÕES DO CLIENTE
  // ══════════════════════════════════════════════════════════════════════════

  /// Cliente confirma a conclusão (liberta o pagamento à profissional).
  Future<CleaningBooking?> confirmCompleted(String bookingId) async {
    _setBusy(true);
    try {
      final res = await _sb
          .rpc('client_confirm_cleaning', params: {'p_booking_id': bookingId});
      final booking = CleaningBooking.fromSupabase(_asMap(res));
      _applyUpdate(booking);
      return booking;
    } catch (e) {
      debugPrint('CleaningStore.confirmCompleted error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Cancela a reserva. A taxa (grátis / 50% / 100%) é decidida no backend.
  Future<CleaningBooking?> cancelBooking(String bookingId,
      {String reason = ''}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('cancel_cleaning_booking', params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
        'p_no_show': false,
      });
      final booking = CleaningBooking.fromSupabase(_asMap(res));
      _applyUpdate(booking);
      return booking;
    } catch (e) {
      debugPrint('CleaningStore.cancelBooking error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Cancela a série de recorrência inteira (só as futuras por agendar).
  Future<void> cancelSeries(String groupId) async {
    _setBusy(true);
    try {
      await _sb.rpc('cancel_cleaning_series', params: {'p_group_id': groupId});
      await loadMyBookings();
    } catch (e) {
      debugPrint('CleaningStore.cancelSeries error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Avalia a profissional (1–5 estrelas) após done/completed.
  Future<void> rateCleaner(String bookingId, int stars,
      {String? comment}) async {
    _setBusy(true);
    try {
      await _sb.rpc('cleaning_submit_rating', params: {
        'p_booking_id': bookingId,
        'p_stars': stars,
        'p_comment': comment ?? '',
      });
    } catch (e) {
      debugPrint('CleaningStore.rateCleaner error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ── infra ────────────────────────────────────────────────────────────────

  void _applyUpdate(CleaningBooking updated) {
    _tracked = _tracked?.id == updated.id ? updated : _tracked;
    _bookings = [
      for (final b in _bookings) b.id == updated.id ? updated : b
    ];
    notifyListeners();
  }

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
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
