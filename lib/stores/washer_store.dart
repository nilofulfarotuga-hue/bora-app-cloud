import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carwash_models.dart';
import '../models/falha_de_acao.dart';

/// LAVAGEM AUTO — store do lavador.
///
/// LIÇÃO CARA (Valdemir, 16/08): a identidade do profissional é o `user_id`.
/// O perfil resolve-se SEMPRE por `washers.user_id = auth.uid()`, e todas as
/// consultas de pedidos filtram pelo `washers.id` que daí sai — exatamente a
/// mesma chave que as policies de SELECT e de UPDATE usam
/// (`_carwash_my_washer_id()`). Se divergirem, o lavador vê o pedido e não
/// consegue avançá-lo, e o bug fica escondido.
class WasherStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  WasherProfile? _profile;
  WasherProfile? get profile => _profile;
  bool get isWasher => _profile != null;
  bool get isApproved => _profile?.isApproved == true;

  /// Ofertas por responder (o servidor roda-as com timeout).
  List<CarwashBooking> _offers = const [];
  List<CarwashBooking> get offers => _offers;

  /// Trabalhos já aceites e ainda por fechar.
  List<CarwashBooking> _jobs = const [];
  List<CarwashBooking> get jobs => _jobs;

  CarwashBooking? get activeJob =>
      _jobs.where((j) => j.status.isActive).isEmpty ? null : _jobs.firstWhere((j) => j.status.isActive);

  bool _busy = false;
  bool get busy => _busy;

  RealtimeChannel? _channel;

  // ══════════════════════════════════════════════════════════════════════════
  // PERFIL — a chave é o user_id
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadProfile() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final row = await _sb
          .from('washers')
          .select()
          .eq('user_id', uid) // <- user_id, nunca o id da tabela
          .maybeSingle()
          .timeout(kAcaoTimeout);
      _profile = row == null
          ? null
          : WasherProfile.fromSupabase(Map<String, dynamic>.from(row));
      notifyListeners();
      if (_profile != null) _subscribe();
    } catch (e) {
      debugPrint('WasherStore.loadProfile => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OFERTAS E TRABALHOS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> refreshAll() async {
    await Future.wait([loadOffers(), loadJobs()]);
  }

  Future<void> loadOffers() async {
    final w = _profile;
    if (w == null) return;
    try {
      final rows = await _sb
          .from('carwash_bookings')
          .select()
          .eq('offer_washer_id', w.id) // mesma chave da policy
          .eq('status', 'scheduled')
          .order('scheduled_at')
          .timeout(kAcaoTimeout);
      _offers = (rows as List)
          .map((r) => CarwashBooking.fromSupabase(Map<String, dynamic>.from(r as Map)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('WasherStore.loadOffers => $e');
    }
  }

  Future<void> loadJobs() async {
    final w = _profile;
    if (w == null) return;
    try {
      final rows = await _sb
          .from('carwash_bookings')
          .select()
          .eq('washer_id', w.id) // mesma chave da policy
          .order('scheduled_at', ascending: false)
          .limit(50)
          .timeout(kAcaoTimeout);
      _jobs = (rows as List)
          .map((r) => CarwashBooking.fromSupabase(Map<String, dynamic>.from(r as Map)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('WasherStore.loadJobs => $e');
    }
  }

  void _subscribe() {
    final w = _profile;
    if (w == null) return;
    _unsubscribe();
    // Sem filtro por coluna: interessam tanto as ofertas (offer_washer_id)
    // como os trabalhos (washer_id). A RLS já limita o que chega.
    _channel = _sb.channel('washer_feed_${w.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'carwash_bookings',
        callback: (_) => refreshAll(),
      )
      ..subscribe();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AÇÕES — todas por RPC (o servidor é que valida)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> accept(String bookingId) =>
      _call('washer_accept_booking', {'p_booking_id': bookingId});

  Future<bool> reject(String bookingId) =>
      _call('washer_reject_booking', {'p_booking_id': bookingId});

  Future<bool> markOnTheWay(String bookingId) =>
      _call('carwash_mark_on_the_way', {'p_booking_id': bookingId});

  /// As 4 fotos são obrigatórias — e o servidor valida-as outra vez.
  /// O botão cinzento é conforto; a garantia está na RPC.
  Future<bool> markPickedUp(String bookingId, List<CarwashPhoto> photos) =>
      _call('carwash_mark_picked_up', {
        'p_booking_id': bookingId,
        'p_photos': photos.map((p) => p.toJson()).toList(),
      });

  Future<bool> markStarted(String bookingId) =>
      _call('carwash_mark_started', {'p_booking_id': bookingId});

  Future<bool> markDelivering(String bookingId,
          {List<CarwashPhoto> photos = const []}) =>
      _call('carwash_mark_delivering', {
        'p_booking_id': bookingId,
        'p_photos': photos.map((p) => p.toJson()).toList(),
      });

  Future<bool> markDelivered(String bookingId,
          {List<CarwashPhoto> photos = const []}) =>
      _call('carwash_mark_delivered', {
        'p_booking_id': bookingId,
        'p_photos': photos.map((p) => p.toJson()).toList(),
      });

  Future<bool> giveUp(String bookingId, {String reason = ''}) =>
      _call('cancel_carwash_booking',
          {'p_booking_id': bookingId, 'p_reason': reason});

  String? _lastError;
  String? get lastError => _lastError;

  Future<bool> _call(String fn, Map<String, dynamic> params) async {
    _setBusy(true);
    _lastError = null;
    try {
      await _sb.rpc(fn, params: params).timeout(kAcaoTimeout);
      await refreshAll();
      return true;
    } catch (e) {
      _lastError = _humanize(e.toString());
      debugPrint('WasherStore.$fn => $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Erros do servidor em português, para o lavador perceber.
  String _humanize(String raw) {
    if (raw.contains('missing_photos')) {
      return 'Faltam fotos do carro. Tira as quatro antes de continuar.';
    }
    if (raw.contains('offer_expired')) return 'Esta oferta expirou.';
    if (raw.contains('offer_not_yours')) return 'Esta oferta já não é tua.';
    if (raw.contains('booking_not_yours')) return 'Este pedido não é teu.';
    if (raw.contains('invalid_transition')) {
      return 'Este pedido já mudou de estado. Actualiza a lista.';
    }
    if (raw.contains('not_a_washer')) return 'A tua conta de lavador não está activa.';
    return 'Não foi possível concluir. Tenta outra vez.';
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
