import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reservation_model.dart';

/// Store cliente para reservas (Reservas PRO §51).
///
/// Consome:
/// - Tabela `reservations` (com JOIN restaurants para nome/foto)
/// - 4 RPCs F2 cliente: client_search_availability, client_join_waitlist,
///   client_join_notify, client_arrived
class ReservationStore extends ChangeNotifier {
  ReservationStore({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  List<ReservationModel> _myReservations = const [];
  bool _loading = false;
  String? _error;

  List<ReservationModel> get myReservations => _myReservations;
  bool get loading => _loading;
  String? get error => _error;

  // Filtered getters para tabs.
  List<ReservationModel> get upcomingReservations =>
      _myReservations.where((r) => r.isUpcoming).toList();

  List<ReservationModel> get pastReservations =>
      _myReservations.where((r) => r.isPast && !r.isCancelled).toList();

  List<ReservationModel> get cancelledReservations =>
      _myReservations.where((r) => r.isCancelled).toList();

  /// Lê reservas do cliente actual (RLS filtra automaticamente por
  /// client_user_id = auth.uid()) com JOIN restaurants para nome/foto.
  Future<void> fetchMyReservations() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from('reservations')
          .select('*, restaurants(id, name, photo_url, image_url)')
          .order('reserved_for', ascending: false)
          .limit(100);

      _myReservations = (response as List)
          .map((r) => ReservationModel.fromSupabase(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      _error = _mapErrorPtPt(e.code ?? e.message);
      debugPrint(
          '[ReservationStore] PostgrestException: ${e.code} ${e.message}');
    } catch (e) {
      _error = 'Não foi possível carregar as reservas. Tenta de novo.';
      debugPrint('[ReservationStore] fetchMyReservations error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Procura slots disponíveis no restaurante (RPC F2).
  Future<Map<String, dynamic>> searchAvailability({
    required String restaurantId,
    required DateTime date,
    required int partySize,
    TimeOfDay? targetTime,
  }) async {
    try {
      final result = await _supabase.rpc('client_search_availability', params: {
        'p_restaurant_id': restaurantId,
        'p_target_date': _formatDate(date),
        'p_party_size': partySize,
        'p_target_time': targetTime != null ? _formatTime(targetTime) : null,
      });
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      throw Exception('Erro ao procurar disponibilidade. Tenta de novo.');
    }
  }

  /// Entra na fila de espera (RPC F2). Trigger envia push parceiro.
  Future<Map<String, dynamic>> joinWaitlist({
    required String restaurantId,
    required int people,
    required DateTime targetDate,
    TimeOfDay? timeStart,
    TimeOfDay? timeEnd,
    String? notes,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_restaurant_id': restaurantId,
        'p_party': people,
        'p_target_date': _formatDate(targetDate),
        if (timeStart != null) 'p_target_time_start': _formatTime(timeStart),
        if (timeEnd != null) 'p_target_time_end': _formatTime(timeEnd),
        if (notes != null) 'p_notes': notes,
      };
      final result = await _supabase.rpc('client_join_waitlist', params: params);
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      throw Exception('Erro ao entrar na fila. Tenta de novo.');
    }
  }

  /// Entra na lista "avisa-me se vagar" (RPC F2, modelo OpenTable Notify).
  Future<Map<String, dynamic>> joinNotify({
    required String restaurantId,
    required DateTime targetDate,
    required TimeOfDay targetTime,
    required int people,
    int flexibilityMinutes = 30,
  }) async {
    try {
      final result = await _supabase.rpc('client_join_notify', params: {
        'p_restaurant_id': restaurantId,
        'p_target_date': _formatDate(targetDate),
        'p_target_time': _formatTime(targetTime),
        'p_people': people,
        'p_flexibility_minutes': flexibilityMinutes,
      });
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      throw Exception('Erro ao entrar na lista de aviso. Tenta de novo.');
    }
  }

  /// Cliente carrega "estou aqui" (RPC F2). Push parceiro automático.
  Future<Map<String, dynamic>> markArrived(String reservationId) async {
    try {
      final result = await _supabase.rpc('client_arrived', params: {
        'p_reservation_id': reservationId,
      });
      // Refresh estado local após sucesso.
      await fetchMyReservations();
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e) {
      throw Exception('Erro ao confirmar chegada. Tenta de novo.');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  String _mapErrorPtPt(String code) {
    // Mapeamento códigos PL/pgSQL F2 (RAISE EXCEPTION) → mensagens PT-PT.
    const mapping = <String, String>{
      'auth_required': 'Sessão expirada. Volta a entrar.',
      'client_blocked_at_restaurant':
          'Não podes reservar neste restaurante.',
      'date_too_close': 'Data muito próxima. Reserva com mais antecedência.',
      'date_too_far': 'Data muito distante. Tenta uma data mais próxima.',
      'date_in_past': 'Data inválida (no passado).',
      'invalid_party_size': 'Número de pessoas inválido.',
      'invalid_flexibility': 'Flexibilidade inválida (0–180 min).',
      'waitlist_already_active': 'Já estás na fila de espera.',
      'notify_already_active': 'Já estás na lista de aviso.',
      'reservation_not_found': 'Reserva não encontrada.',
      'not_your_reservation': 'Esta reserva não é tua.',
      'already_arrived': 'Já carregaste "estou aqui".',
      'user_not_found': 'Conta não encontrada.',
    };
    if (mapping.containsKey(code)) return mapping[code]!;
    if (code.startsWith('cannot_arrive_status')) {
      return 'Não podes carregar "estou aqui" neste estado.';
    }
    return 'Ocorreu um erro. Tenta de novo.';
  }
}
