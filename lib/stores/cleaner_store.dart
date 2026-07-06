import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cleaning_models.dart';

/// LIMPEZA — store da PROFISSIONAL. Perfil, ofertas pendentes, agenda,
/// disponibilidade semanal e ganhos. Transições sempre por RPC.
class CleanerStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  CleanerProfile? _profile;
  CleanerProfile? get profile => _profile;
  bool get isCleaner => _profile != null;

  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  /// Reservas com oferta ativa para mim (aceitar/recusar).
  List<CleaningBooking> _offers = const [];
  List<CleaningBooking> get offers => _offers;

  /// Limpezas atribuídas a mim ainda ativas (agenda de trabalho).
  List<CleaningBooking> _agenda = const [];
  List<CleaningBooking> get agenda => _agenda;

  List<CleanerSlot> _slots = const [];
  List<CleanerSlot> get slots => _slots;

  Map<String, dynamic> _earnings = const {};
  Map<String, dynamic> get earnings => _earnings;

  bool _busy = false;
  bool get busy => _busy;

  RealtimeChannel? _channel;

  // ══════════════════════════════════════════════════════════════════════════
  // PERFIL / CANDIDATURA
  // ══════════════════════════════════════════════════════════════════════════

  /// Lê o meu registo de cleaners (RLS: só a própria linha). Liga o realtime
  /// de ofertas/agenda quando aprovada.
  Future<void> loadProfile() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final row = await _sb
          .from('cleaners')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      _profile = row == null ? null : CleanerProfile.fromSupabase(row);
      _profileLoaded = true;
      notifyListeners();
      if (_profile?.isApproved == true) {
        _subscribe(_profile!.id);
        await Future.wait([loadWork(), loadSlots()]);
      }
    } catch (e) {
      debugPrint('CleanerStore.loadProfile error => $e');
      _profileLoaded = true;
      notifyListeners();
    }
  }

  /// Candidatura (ou recandidatura após rejeição) via cleaner_apply.
  Future<void> apply({
    required String name,
    required String phone,
    String email = '',
    String nif = '',
    String bio = '',
    String baseAddress = '',
    double? baseLat,
    double? baseLng,
    double serviceRadiusKm = 10,
    String photoUrl = '',
    Map<String, dynamic> docs = const {},
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('cleaner_apply', params: {
        'p_name': name,
        'p_phone': phone,
        'p_email': email,
        'p_nif': nif,
        'p_bio': bio,
        'p_photo_url': photoUrl,
        'p_base_address': baseAddress,
        'p_base_lat': baseLat,
        'p_base_lng': baseLng,
        'p_service_radius_km': serviceRadiusKm,
        'p_docs': docs,
      });
      _profile = CleanerProfile.fromSupabase(_asMap(res));
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.apply error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Atualiza perfil (bio/raio/ativa) via cleaner_set_profile.
  Future<void> setProfile({
    String? bio,
    double? serviceRadiusKm,
    bool? isActive,
    String? baseAddress,
    double? baseLat,
    double? baseLng,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('cleaner_set_profile', params: {
        'p_bio': bio,
        'p_photo_url': null,
        'p_service_radius_km': serviceRadiusKm,
        'p_is_active': isActive,
        'p_base_address': baseAddress,
        'p_base_lat': baseLat,
        'p_base_lng': baseLng,
      });
      _profile = CleanerProfile.fromSupabase(_asMap(res));
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.setProfile error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OFERTAS + AGENDA
  // ══════════════════════════════════════════════════════════════════════════

  /// Recarrega ofertas pendentes + limpezas atribuídas (agenda ativa).
  Future<void> loadWork() async {
    final me = _profile;
    if (me == null) return;
    try {
      final offerRows = await _sb
          .from('cleaning_bookings')
          .select()
          .eq('offer_cleaner_id', me.id)
          .eq('status', 'scheduled')
          .order('scheduled_at', ascending: true);
      _offers =
          offerRows.map<CleaningBooking>(CleaningBooking.fromSupabase).toList();

      final agendaRows = await _sb
          .from('cleaning_bookings')
          .select()
          .eq('cleaner_id', me.id)
          .inFilter('status',
              const ['accepted', 'on_the_way', 'in_progress', 'done'])
          .order('scheduled_at', ascending: true);
      _agenda = agendaRows
          .map<CleaningBooking>(CleaningBooking.fromSupabase)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.loadWork error => $e');
    }
  }

  void _subscribe(String cleanerId) {
    _unsubscribe();
    // Ofertas novas chegam por UPDATE (rotation seta offer_cleaner_id) e a
    // agenda muda por UPDATE também — um refresh barato cobre os dois lados.
    _channel = _sb.channel('cleaner_work_$cleanerId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'cleaning_bookings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'offer_cleaner_id',
          value: cleanerId,
        ),
        callback: (_) => loadWork(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'cleaning_bookings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'cleaner_id',
          value: cleanerId,
        ),
        callback: (_) => loadWork(),
      )
      ..subscribe();
  }

  Future<void> acceptBooking(String bookingId) async {
    _setBusy(true);
    try {
      await _sb
          .rpc('cleaner_accept_booking', params: {'p_booking_id': bookingId});
      await loadWork();
    } catch (e) {
      debugPrint('CleanerStore.acceptBooking error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> rejectBooking(String bookingId) async {
    _setBusy(true);
    try {
      await _sb
          .rpc('cleaner_reject_booking', params: {'p_booking_id': bookingId});
      await loadWork();
    } catch (e) {
      debugPrint('CleanerStore.rejectBooking error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> markOnTheWay(String bookingId) =>
      _transition('cleaning_mark_on_the_way', bookingId);

  Future<void> markStarted(String bookingId) =>
      _transition('cleaning_mark_started', bookingId);

  Future<void> markDone(String bookingId) =>
      _transition('cleaning_mark_done', bookingId);

  Future<void> _transition(String rpc, String bookingId) async {
    _setBusy(true);
    try {
      await _sb.rpc(rpc, params: {'p_booking_id': bookingId});
      await loadWork();
    } catch (e) {
      debugPrint('CleanerStore.$rpc error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Profissional cancela (re-oferece às restantes; tardio conta p/ suspensão)
  /// ou marca no-show do cliente (após a hora marcada → taxa 100%).
  Future<void> cancelBooking(String bookingId,
      {String reason = '', bool noShow = false}) async {
    _setBusy(true);
    try {
      await _sb.rpc('cancel_cleaning_booking', params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
        'p_no_show': noShow,
      });
      await loadWork();
    } catch (e) {
      debugPrint('CleanerStore.cancelBooking error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Card público do cliente (nome/foto/telefone) — só para a profissional
  /// ATRIBUÍDA e com o serviço em curso (padrão tvde_ride_passenger_card).
  Future<Map<String, dynamic>?> clientCard(String bookingId) async {
    try {
      final res = await _sb.rpc('cleaning_booking_client_public',
          params: {'p_booking_id': bookingId});
      return res == null ? null : Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('CleanerStore.clientCard error => $e');
      return null;
    }
  }

  /// Avalia o cliente (obrigatório dos dois lados).
  Future<void> rateClient(String bookingId, int stars,
      {String? comment}) async {
    try {
      await _sb.rpc('cleaning_submit_rating', params: {
        'p_booking_id': bookingId,
        'p_stars': stars,
        'p_comment': comment ?? '',
      });
    } catch (e) {
      debugPrint('CleanerStore.rateClient error => $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPONIBILIDADE + GANHOS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadSlots() async {
    final me = _profile;
    if (me == null) return;
    try {
      final rows = await _sb
          .from('cleaner_availability')
          .select()
          .eq('cleaner_id', me.id)
          .order('weekday', ascending: true)
          .order('start_time', ascending: true);
      _slots = rows.map<CleanerSlot>(CleanerSlot.fromSupabase).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.loadSlots error => $e');
    }
  }

  /// Substitui a grelha semanal inteira (RPC apaga + recria).
  Future<void> saveSlots(List<CleanerSlot> slots) async {
    _setBusy(true);
    try {
      await _sb.rpc('cleaner_set_availability', params: {
        'p_slots': slots.map((s) => s.toJson()).toList(),
      });
      _slots = List.of(slots);
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.saveSlots error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Histórico de limpezas concluídas/canceladas da profissional (detalhe).
  /// Query direta (RLS: cleaner_id = a própria via cleaners) — padrão do
  /// histórico de corridas do motorista TVDE.
  Future<List<CleaningBooking>> loadHistory() async {
    final me = _profile;
    if (me == null) return const [];
    try {
      final rows = await _sb
          .from('cleaning_bookings')
          .select()
          .eq('cleaner_id', me.id)
          .inFilter('status',
              const ['completed', 'cancelled_client', 'cancelled_cleaner'])
          .order('scheduled_at', ascending: false)
          .limit(100);
      return rows.map<CleaningBooking>(CleaningBooking.fromSupabase).toList();
    } catch (e) {
      debugPrint('CleanerStore.loadHistory error => $e');
      return const [];
    }
  }

  Future<void> loadEarnings() async {
    try {
      final res = await _sb.rpc('cleaner_earnings_summary');
      _earnings = res is Map ? Map<String, dynamic>.from(res) : const {};
      notifyListeners();
    } catch (e) {
      debugPrint('CleanerStore.loadEarnings error => $e');
    }
  }

  // ── infra ────────────────────────────────────────────────────────────────

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
