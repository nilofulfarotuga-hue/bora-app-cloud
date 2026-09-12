import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_restaurant_profile.dart';
import '../models/floor_plan.dart';
import '../models/reservation_model.dart';
import '../models/restaurant_table.dart';

/// Reservas PRO F4 — store partner-side.
///
/// Consome 9 RPCs partner + CRUD direct via RLS partner_owner para
/// `restaurant_floor_plans`, `restaurant_tables`,
/// `restaurant_pacing_rules`, `restaurant_turn_times`,
/// `client_restaurant_profiles`.
class PartnerReservasStore extends ChangeNotifier {
  PartnerReservasStore({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  // ───────────── RESERVAS ─────────────

  /// `filter`: 'pending' / 'approved' / 'today' / 'future' / 'all' / 'history'.
  Future<List<ReservationModel>> fetchRestaurantReservations({
    required String restaurantId,
    String filter = 'today',
  }) async {
    try {
      var query = _supabase
          .from('reservations')
          .select('*')
          .eq('restaurant_id', restaurantId);

      switch (filter) {
        case 'pending':
          query = query.eq('status', 'pending');
          break;
        case 'approved':
          query = query.eq('status', 'approved');
          break;
        case 'today':
          final today = DateTime.now();
          final start = DateTime(today.year, today.month, today.day);
          final end = start.add(const Duration(days: 1));
          query = query
              .gte('reserved_for', start.toIso8601String())
              .lt('reserved_for', end.toIso8601String());
          break;
        case 'future':
          // BUG 3 — reservas futuras (após NOW), ainda activas.
          final now = DateTime.now();
          query = query
              .gt('reserved_for', now.toIso8601String())
              .inFilter('status', ['pending', 'approved', 'arrived']);
          break;
        case 'history':
          final today = DateTime.now();
          final start = DateTime(today.year, today.month, today.day);
          query = query.lt('reserved_for', start.toIso8601String());
          break;
        case 'all':
          break;
      }

      final res = await query.order('reserved_for', ascending: true);
      return (res as List)
          .map((row) => ReservationModel.fromSupabase(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchReservations: $e');
      throw Exception('Não foi possível carregar as reservas.');
    }
  }

  Future<Map<String, dynamic>> decideReservation({
    required String reservationId,
    required bool accept,
    String? reason,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_decide_reservation',
        params: {
          'p_reservation_id': reservationId,
          'p_accept': accept,
          if (reason != null) 'p_reason': reason,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] decide: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  Future<Map<String, dynamic>> markSeated({
    required String reservationId,
    String? tableId,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_mark_seated',
        params: {
          'p_reservation_id': reservationId,
          if (tableId != null) 'p_table_id': tableId,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] markSeated: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  Future<Map<String, dynamic>> markFinished(String reservationId) async {
    try {
      final res = await _supabase.rpc(
        'partner_mark_finished',
        params: {'p_reservation_id': reservationId},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] markFinished: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// ⚠️ Cria CRÉDITO €2 cliente + PAYOUT obrigation Bora.
  /// UI deve mostrar ambos no dialog sucesso (transparência).
  Future<Map<String, dynamic>> markArrival(String reservationId) async {
    try {
      final res = await _supabase.rpc(
        'partner_mark_arrival',
        params: {'p_reservation_id': reservationId},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] markArrival: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  Future<Map<String, dynamic>> seatWalkIn({
    required String restaurantId,
    required int party,
    required String tableId,
    String clientName = 'Walk-in',
    String? clientPhone,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_seat_walk_in',
        params: {
          'p_restaurant_id': restaurantId,
          'p_party': party,
          'p_table_id': tableId,
          'p_client_name': clientName,
          if (clientPhone != null) 'p_client_phone': clientPhone,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] walkIn: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  // ───────────── FLOOR PLANS / TABLES ─────────────

  Future<List<FloorPlan>> fetchFloorPlans(String restaurantId) async {
    try {
      final res = await _supabase
          .from('restaurant_floor_plans')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('active', true)
          .order('is_default', ascending: false);
      return (res as List)
          .map((r) => FloorPlan.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchFloorPlans: $e');
      throw Exception('Não foi possível carregar os planos.');
    }
  }

  Future<Map<String, dynamic>> createFloorPlan({
    required String restaurantId,
    required String name,
    bool isDefault = false,
    int widthCm = 1000,
    int heightCm = 800,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_create_floor_plan',
        params: {
          'p_restaurant_id': restaurantId,
          'p_name': name,
          'p_is_default': isDefault,
          'p_width_cm': widthCm,
          'p_height_cm': heightCm,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] createFloorPlan: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  Future<List<RestaurantTable>> fetchTables({
    required String restaurantId,
    String? floorPlanId,
  }) async {
    try {
      var query = _supabase
          .from('restaurant_tables')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('active', true);
      if (floorPlanId != null) {
        query = query.eq('floor_plan_id', floorPlanId);
      }
      final res = await query.order('numero');
      return (res as List)
          .map((r) =>
              RestaurantTable.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchTables: $e');
      throw Exception('Não foi possível carregar as mesas.');
    }
  }

  Future<Map<String, dynamic>> addTable({
    required String restaurantId,
    required String numero,
    required int capacity,
    String zona = 'interior',
    String? floorPlanId,
    double posX = 100,
    double posY = 100,
    String shape = 'rectangle',
    String? notes,
  }) async {
    try {
      final res = await _supabase.rpc(
        'partner_add_table',
        params: {
          'p_restaurant_id': restaurantId,
          'p_numero': numero,
          'p_capacity': capacity,
          'p_zona': zona,
          if (floorPlanId != null) 'p_floor_plan_id': floorPlanId,
          'p_pos_x': posX,
          'p_pos_y': posY,
          'p_shape': shape,
          if (notes != null) 'p_notes': notes,
        },
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('[PartnerReservasStore] addTable: $e');
      throw Exception(_mapErrorPtPt(e.toString()));
    }
  }

  /// UPDATE direct via RLS partner_owner. Usado pelo drag&drop
  /// (persistido no onPanEnd para evitar saturar BD).
  Future<void> updateTablePosition({
    required String tableId,
    required double posX,
    required double posY,
    int? rotationDeg,
  }) async {
    try {
      final update = <String, dynamic>{
        'pos_x': posX,
        'pos_y': posY,
      };
      if (rotationDeg != null) update['rotation_deg'] = rotationDeg;
      await _supabase.from('restaurant_tables').update(update).eq('id', tableId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] updatePosition: $e');
      throw Exception('Não foi possível mover a mesa.');
    }
  }

  Future<void> updateTable({
    required String tableId,
    String? numero,
    int? capacity,
    String? zona,
    String? shape,
    String? notes,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (numero != null) update['numero'] = numero;
      if (capacity != null) update['capacity'] = capacity;
      if (zona != null) update['zona'] = zona;
      if (shape != null) update['shape'] = shape;
      if (notes != null) update['notes'] = notes;
      await _supabase.from('restaurant_tables').update(update).eq('id', tableId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] updateTable: $e');
      throw Exception('Não foi possível actualizar a mesa.');
    }
  }

  /// Soft delete via active=false (mantém audit trail).
  Future<void> deleteTable(String tableId) async {
    try {
      await _supabase
          .from('restaurant_tables')
          .update({'active': false}).eq('id', tableId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] deleteTable: $e');
      throw Exception('Não foi possível remover a mesa.');
    }
  }

  // ───────────── CLIENT PROFILES ─────────────

  Future<List<ClientRestaurantProfile>> fetchClientProfiles(
    String restaurantId,
  ) async {
    try {
      final res = await _supabase
          .from('client_restaurant_profiles')
          .select('*, users:client_user_id(name, phone)')
          .eq('restaurant_id', restaurantId)
          .order('total_visits', ascending: false);
      return (res as List)
          .map((r) => ClientRestaurantProfile.fromJson(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchProfiles: $e');
      throw Exception('Não foi possível carregar perfis.');
    }
  }

  Future<void> toggleVip(String profileId, bool isVip) async {
    try {
      await _supabase
          .from('client_restaurant_profiles')
          .update({'is_vip': isVip}).eq('id', profileId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] toggleVip: $e');
      throw Exception('Não foi possível actualizar VIP.');
    }
  }

  Future<void> toggleBlock({
    required String profileId,
    required bool isBlocked,
    String? reason,
  }) async {
    try {
      await _supabase.from('client_restaurant_profiles').update({
        'is_blocked': isBlocked,
        'blocked_reason': isBlocked ? reason : null,
        'blocked_at':
            isBlocked ? DateTime.now().toIso8601String() : null,
      }).eq('id', profileId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] toggleBlock: $e');
      throw Exception('Não foi possível actualizar bloqueio.');
    }
  }

  Future<void> updatePartnerNotes(String profileId, String? notes) async {
    try {
      await _supabase
          .from('client_restaurant_profiles')
          .update({'partner_notes': notes}).eq('id', profileId);
    } catch (e) {
      debugPrint('[PartnerReservasStore] updatePartnerNotes: $e');
      throw Exception('Não foi possível guardar notas.');
    }
  }

  // ───────────── ANALYTICS ─────────────

  /// KPIs agregados client-side (sem RPC dedicada — query simples
  /// com seleção de colunas).
  Future<Map<String, dynamic>> fetchStats({
    required String restaurantId,
    int days = 30,
  }) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final res = await _supabase
          .from('reservations')
          .select(
              'status, people, prepayment_cents, reserved_for, arrived_at, finished_at, seated_at, is_walk_in')
          .eq('restaurant_id', restaurantId)
          .gte('reserved_for', since.toIso8601String());

      final list = (res as List).cast<Map<String, dynamic>>();

      final total = list.length;
      final approved = list.where((r) => r['status'] == 'approved').length;
      final rejected =
          list.where((r) => r['status'] == 'rejected_refunded').length;
      final noShows = list.where((r) => r['status'] == 'no_show').length;
      final seated = list.where((r) => r['seated_at'] != null).length;
      final walkIns = list.where((r) => r['is_walk_in'] == true).length;
      final totalCovers = list
          .where((r) => r['seated_at'] != null)
          .fold<int>(0, (sum, r) => sum + ((r['people'] as int?) ?? 0));

      return {
        'total': total,
        'approved': approved,
        'rejected': rejected,
        'no_shows': noShows,
        'seated': seated,
        'walk_ins': walkIns,
        'total_covers': totalCovers,
        'period_days': days,
      };
    } catch (e) {
      debugPrint('[PartnerReservasStore] stats: $e');
      throw Exception('Não foi possível carregar estatísticas.');
    }
  }

  // ───────────── PACING & TURN TIMES (CRUD direct) ─────────────

  Future<List<Map<String, dynamic>>> fetchTurnTimes(
      String restaurantId) async {
    try {
      final res = await _supabase
          .from('restaurant_turn_times')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('active', true)
          .order('party_size_min');
      return (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchTurnTimes: $e');
      throw Exception('Não foi possível carregar tempos.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchPacingRules(
      String restaurantId) async {
    try {
      final res = await _supabase
          .from('restaurant_pacing_rules')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('active', true)
          .order('day_of_week');
      return (res as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (e) {
      debugPrint('[PartnerReservasStore] fetchPacingRules: $e');
      throw Exception('Não foi possível carregar regras.');
    }
  }

  Future<void> insertTurnTime(Map<String, dynamic> row) async {
    try {
      await _supabase.from('restaurant_turn_times').insert(row);
    } catch (e) {
      debugPrint('[PartnerReservasStore] insertTurnTime: $e');
      throw Exception('Não foi possível guardar.');
    }
  }

  Future<void> deleteTurnTime(String id) async {
    try {
      await _supabase
          .from('restaurant_turn_times')
          .update({'active': false}).eq('id', id);
    } catch (e) {
      debugPrint('[PartnerReservasStore] deleteTurnTime: $e');
      throw Exception('Não foi possível remover.');
    }
  }

  Future<void> insertPacingRule(Map<String, dynamic> row) async {
    try {
      await _supabase.from('restaurant_pacing_rules').insert(row);
    } catch (e) {
      debugPrint('[PartnerReservasStore] insertPacingRule: $e');
      throw Exception('Não foi possível guardar.');
    }
  }

  Future<void> deletePacingRule(String id) async {
    try {
      await _supabase
          .from('restaurant_pacing_rules')
          .update({'active': false}).eq('id', id);
    } catch (e) {
      debugPrint('[PartnerReservasStore] deletePacingRule: $e');
      throw Exception('Não foi possível remover.');
    }
  }

  // ───────────── ERROR MAPPING ─────────────

  String _mapErrorPtPt(String error) {
    final e = error.toLowerCase();
    if (e.contains('reservation_not_found')) return 'Reserva não encontrada.';
    if (e.contains('reservation_not_pending')) {
      return 'Reserva já foi decidida.';
    }
    if (e.contains('reservation_not_approved')) {
      return 'Reserva ainda não aprovada.';
    }
    if (e.contains('not_your_restaurant') || e.contains('not_partner_owner')) {
      return 'Não tens acesso a esta reserva.';
    }
    if (e.contains('cannot_seat_status')) {
      return 'Não é possível sentar nesse estado.';
    }
    if (e.contains('already_seated')) return 'Já está sentado.';
    if (e.contains('not_seated_yet')) return 'Tens de sentar primeiro.';
    if (e.contains('already_finished')) return 'Já foi terminado.';
    if (e.contains('already_arrived')) return 'Chegada já marcada.';
    if (e.contains('invalid_table')) return 'Mesa inválida.';
    if (e.contains('table_not_found')) return 'Mesa não encontrada.';
    if (e.contains('table_not_owned')) {
      return 'Mesa não pertence a este restaurante.';
    }
    if (e.contains('table_inactive')) return 'Mesa desactivada.';
    if (e.contains('table_too_small')) return 'Mesa pequena para o grupo.';
    if (e.contains('invalid_party_size')) {
      return 'Número de pessoas inválido (1-50).';
    }
    if (e.contains('auth_required')) return 'Sessão expirada.';
    return 'Erro: ${error.replaceFirst('Exception: ', '')}';
  }
}
