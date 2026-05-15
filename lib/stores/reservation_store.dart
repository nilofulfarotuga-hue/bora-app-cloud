import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notify_entry.dart';
import '../models/reservation_model.dart';
import '../models/waitlist_entry.dart';

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

  // 2026-05-14 — H1 fix: realtime subscription para reservas do user.
  // Pre-requisito: migration 20260514120001 adicionou reservations a
  // publication supabase_realtime.
  StreamSubscription? _myReservationsSub;
  bool _subscribed = false;

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

  /// 2026-05-14 — Lookup reactivo por id (usado pelo details screen
  /// para reflectir mudancas de status sem reabrir).
  ReservationModel? findById(String id) {
    for (final r in _myReservations) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 2026-05-14 — Subscreve mudancas em tempo real das reservas do user.
  /// Idempotente. Stream filtrado server-side por client_user_id (RLS)
  /// + .eq() no cliente para reduzir trafego.
  /// Pre-requisito: tabela reservations adicionada a publication
  /// supabase_realtime (migration 20260514120001).
  ///
  /// .stream() do Supabase NAO suporta JOIN. Por isso preservamos os campos
  /// restaurantName/restaurantPhotoUrl da fetch inicial via merge por id.
  void subscribeMyReservations() {
    if (_subscribed) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    _subscribed = true;
    _myReservationsSub = _supabase
        .from('reservations')
        .stream(primaryKey: ['id'])
        .eq('client_user_id', uid)
        .order('reserved_for', ascending: false)
        .listen((rows) {
      // .stream() entrega lista completa em cada evento.
      final byId = {for (final r in _myReservations) r.id: r};
      _myReservations = rows.map((row) {
        final fresh = ReservationModel.fromSupabase(
          Map<String, dynamic>.from(row),
        );
        final prev = byId[fresh.id];
        if (prev?.restaurantName != null && fresh.restaurantName == null) {
          return fresh.copyWithRestaurantInfo(
            name: prev!.restaurantName,
            photoUrl: prev.restaurantPhotoUrl,
          );
        }
        return fresh;
      }).toList();
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('[ReservationStore] realtime stream error: $e');
    });
  }

  void unsubscribeMyReservations() {
    _myReservationsSub?.cancel();
    _myReservationsSub = null;
    _subscribed = false;
  }

  @override
  void dispose() {
    _myReservationsSub?.cancel();
    super.dispose();
  }

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
    // BUG #11 Fase 1 (2026-05-13) — debug instrumentação temporária para
    // capturar input/output reais quando o user repete o teste. Manter até
    // root cause confirmado, depois remover ou trocar para log estruturado.
    final params = <String, dynamic>{
      'p_restaurant_id': restaurantId,
      'p_target_date': _formatDate(date),
      'p_party_size': partySize,
      'p_target_time': targetTime != null ? _formatTime(targetTime) : null,
    };
    debugPrint('[ReservationStore] searchAvailability → params=$params '
        '(weekday=${date.weekday} ie ${_weekdayPtPt(date.weekday)})');
    try {
      final result =
          await _supabase.rpc('client_search_availability', params: params);
      debugPrint('[ReservationStore] searchAvailability ← $result');
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      debugPrint('[ReservationStore] searchAvailability PostgrestException: '
          'code=${e.code} message=${e.message}');
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e, st) {
      debugPrint('[ReservationStore] searchAvailability error: $e\n$st');
      throw Exception('Erro ao procurar disponibilidade. Tenta de novo.');
    }
  }

  static String _weekdayPtPt(int weekday) {
    // DateTime.weekday: 1=Mon..7=Sun
    const names = [
      '', // index 0 unused
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    return names[weekday.clamp(1, 7)];
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
      debugPrint(
          '[ReservationStore] joinWaitlist PostgrestException: code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}');
      throw Exception(_mapErrorPtPt(e.code ?? e.message));
    } catch (e, st) {
      debugPrint('[ReservationStore] joinWaitlist error: $e\n$st');
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

  /// Cria PaymentIntent Stripe para reserva via Edge Function.
  /// Edge Fn `create-reservation-payment-intent` v3 aceita: restaurant_id,
  /// people, reserved_for, client_name, client_phone, notes (combinado).
  /// Resposta: { reservation_id, paymentIntentId, clientSecret, amount_cents }.
  Future<Map<String, dynamic>> createReservationPaymentIntent({
    required String restaurantId,
    required int people,
    required DateTime reservedFor,
    String? combinedNotes,
    String? clientName,
    String? clientPhone,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-reservation-payment-intent',
        body: {
          'restaurant_id': restaurantId,
          'people': people,
          'reserved_for': reservedFor.toUtc().toIso8601String(),
          if (combinedNotes != null && combinedNotes.isNotEmpty)
            'notes': combinedNotes,
          if (clientName != null && clientName.isNotEmpty)
            'client_name': clientName,
          if (clientPhone != null && clientPhone.isNotEmpty)
            'client_phone': clientPhone,
        },
      );
      if (response.data == null) {
        throw Exception('Resposta vazia do servidor.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data.containsKey('error')) {
        throw Exception(_mapErrorPtPt(data['error'].toString()));
      }
      return data;
    } catch (e) {
      debugPrint('[ReservationStore] createPaymentIntent error: $e');
      rethrow;
    }
  }

  /// Cria reserva pending_payment + PaymentIntent MBWay server-confirm.
  /// Edge Fn `create-mbway-reservation-payment-intent` v1 espelha o padrão
  /// dos pedidos normais (create-mbway-payment-intent v21) — confirm:true com
  /// billing_details.phone, push imediato para MBWay.
  ///
  /// Resposta: { reservation_id, paymentIntentId, status, amount_cents }.
  /// O Flutter deve depois apresentar dialog de espera com poll a
  /// `reservations.status` até `pending` (webhook confirma) ou timeout.
  Future<Map<String, dynamic>> createMbwayReservationPaymentIntent({
    required String restaurantId,
    required int people,
    required DateTime reservedFor,
    required String mbwayPhone,
    String? combinedNotes,
    String? clientName,
    String? clientPhone,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-mbway-reservation-payment-intent',
        body: {
          'restaurant_id': restaurantId,
          'people': people,
          'reserved_for': reservedFor.toUtc().toIso8601String(),
          'phone': mbwayPhone,
          if (combinedNotes != null && combinedNotes.isNotEmpty)
            'notes': combinedNotes,
          if (clientName != null && clientName.isNotEmpty)
            'client_name': clientName,
          if (clientPhone != null && clientPhone.isNotEmpty)
            'client_phone': clientPhone,
        },
      );
      if (response.data == null) {
        throw Exception('Resposta vazia do servidor.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data.containsKey('error')) {
        throw Exception(_mapErrorPtPt(data['error'].toString()));
      }
      return data;
    } catch (e) {
      debugPrint('[ReservationStore] createMbwayPaymentIntent error: $e');
      rethrow;
    }
  }

  /// Confirma pagamento da reserva após Stripe sucesso (RPC F2 fallback).
  /// Webhook auto-confirma payment_status; este RPC é fallback que valida
  /// estado client-side e refresh state.
  Future<void> confirmReservationPayment(String reservationId) async {
    try {
      await _supabase.rpc(
        'client_confirm_reservation_payment',
        params: {'p_reservation_id': reservationId},
      );
    } catch (e) {
      debugPrint('[ReservationStore] confirm payment: $e');
    } finally {
      await fetchMyReservations();
    }
  }

  /// Lista próprias entries da fila de espera (RLS filtra por
  /// client_user_id = auth.uid()).
  Future<List<WaitlistEntry>> fetchMyWaitlist() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sessão expirada. Volta a entrar.');
    }
    try {
      final res = await _supabase
          .from('reservation_waitlist')
          .select('*, restaurants(id, name, photo_url, image_url)')
          .eq('client_user_id', userId)
          .order('created_at', ascending: false);
      return (res as List)
          .map((row) =>
              WaitlistEntry.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      debugPrint('[ReservationStore] fetchMyWaitlist error: $e');
      throw Exception('Não foi possível carregar a fila de espera.');
    }
  }

  /// Lista próprias entries de "avisar se vagar" (RLS).
  Future<List<NotifyEntry>> fetchMyNotify() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sessão expirada. Volta a entrar.');
    }
    try {
      final res = await _supabase
          .from('reservation_notify_list')
          .select('*, restaurants(id, name, photo_url, image_url)')
          .eq('client_user_id', userId)
          .order('created_at', ascending: false);
      return (res as List)
          .map((row) =>
              NotifyEntry.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      debugPrint('[ReservationStore] fetchMyNotify error: $e');
      throw Exception('Não foi possível carregar a lista "avisar se vagar".');
    }
  }

  /// Cancela entry da fila (UPDATE status='cancelled').
  /// NÃO DELETE — mantém audit trail e triggers analytics.
  Future<void> leaveWaitlist(String waitlistId) async {
    try {
      await _supabase
          .from('reservation_waitlist')
          .update({'status': 'cancelled'}).eq('id', waitlistId);
    } catch (e) {
      debugPrint('[ReservationStore] leaveWaitlist error: $e');
      throw Exception('Não foi possível sair da fila.');
    }
  }

  /// Cancela entry da lista notify (UPDATE status='cancelled').
  Future<void> leaveNotify(String notifyId) async {
    try {
      await _supabase
          .from('reservation_notify_list')
          .update({'status': 'cancelled'}).eq('id', notifyId);
    } catch (e) {
      debugPrint('[ReservationStore] leaveNotify error: $e');
      throw Exception('Não foi possível sair da lista.');
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
      'profile_incomplete_name':
          'Adiciona o teu nome no perfil antes de entrar na fila.',
      'profile_incomplete_phone':
          'Adiciona o teu telefone no perfil antes de entrar na fila.',
    };
    if (mapping.containsKey(code)) return mapping[code]!;
    if (code.startsWith('cannot_arrive_status')) {
      return 'Não podes carregar "estou aqui" neste estado.';
    }
    return 'Ocorreu um erro. Tenta de novo.';
  }
}
