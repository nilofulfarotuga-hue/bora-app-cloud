import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';
import '../models/client_restaurant_profile.dart';
import '../models/floor_plan.dart';
import '../models/reservation_model.dart';
import '../models/restaurant_table.dart';
import '../utils/euros.dart';
import '../utils/hora_lisboa.dart';

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
          // M4 (04/10/2026): "hoje" é o dia de Lisboa, em instantes UTC
          // (antes ia a meia-noite do telemóvel sem fuso → 1 h ao lado no verão).
          final start = inicioDiaLisboaUtc(DateTime.now());
          final end = inicioDiaLisboaUtc(
              start.add(const Duration(hours: 26)));
          query = query
              .gte('reserved_for', start.toIso8601String())
              .lt('reserved_for', end.toIso8601String());
          break;
        case 'future':
          // BUG 3 — reservas futuras (após NOW), ainda activas.
          final now = DateTime.now().toUtc();
          query = query
              .gt('reserved_for', now.toIso8601String())
              .inFilter('status', ['pending', 'approved', 'arrived']);
          break;
        case 'history':
          final start = inicioDiaLisboaUtc(DateTime.now());
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

  // ───────────── REJEITAR COM DEVOLUÇÃO (fechar-tudo-15-11) ─────────────

  /// Edge que rejeita a reserva E devolve o pré-pagamento na Stripe
  /// (`supabase/functions/partner-reject-reservation`). A RPC sozinha só
  /// mudava o estado e dizia ao cliente "Reembolso em curso" sem devolver
  /// nada.
  static const String edgeRejeitarComDevolucao = 'partner-reject-reservation';

  /// Há dinheiro a devolver? Então a rejeição passa pela Edge. Sem
  /// pré-pagamento, a RPC de sempre faz exatamente o mesmo.
  static bool precisaDeDevolucao(ReservationModel r) =>
      r.prepaymentCents > 0 || (r.prepaymentPi ?? '').trim().isNotEmpty;

  /// Rejeita a reserva (o cliente é avisado pelo servidor).
  ///
  /// Com pré-pagamento vai pela Edge, que devolve o dinheiro. Se a Edge
  /// falhar — também se ainda não estiver instalada — NÃO há volta pela RPC:
  /// rejeitar sem devolver era precisamente o erro. Lança
  /// [RecusaReservaFalhou] e a reserva fica como estava.
  Future<RecusaReserva> rejectReservation({
    required ReservationModel reservation,
    String? reason,
  }) async {
    if (!precisaDeDevolucao(reservation)) {
      await decideReservation(
        reservationId: reservation.id,
        accept: false,
        reason: reason,
      );
      return const RecusaReserva(devolucao: DevolucaoDaReserva.semPrePagamento);
    }
    try {
      final res = await _supabase.functions.invoke(
        edgeRejeitarComDevolucao,
        body: {
          'reservation_id': reservation.id,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      return RecusaReserva.daResposta(
        res.data,
        prePagamentoCents: reservation.prepaymentCents,
      );
    } on FunctionException catch (e) {
      debugPrint('[PartnerReservasStore] rejeitar: $e');
      throw RecusaReservaFalhou(
          RecusaReservaFalhou.motivoDe(e.status, e.details));
    } catch (e) {
      debugPrint('[PartnerReservasStore] rejeitar: $e');
      throw const RecusaReservaFalhou(MotivoFalhaRecusa.outro);
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
            isBlocked ? DateTime.now().toUtc().toIso8601String() : null,
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
      final since = DateTime.now().toUtc().subtract(Duration(days: days));
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

// ───────────── REJEITAR COM DEVOLUÇÃO: resultado e falhas ─────────────
// fechar-tudo-15-11 (15/11/2026): o parceiro só lê o que é verdade sobre o
// pré-pagamento do cliente.

/// O que aconteceu ao pré-pagamento quando o parceiro rejeitou a reserva.
enum DevolucaoDaReserva {
  /// Não havia pré-pagamento, ou nunca chegou a ser cobrado.
  semPrePagamento,

  /// A devolução foi pedida agora à Stripe.
  pedida,

  /// Já tinha sido devolvido (nova tentativa).
  jaFeita,

  /// Não saiu sozinha: a equipa Bora foi avisada no painel e trata dela.
  aCargoDaEquipa,
}

/// Reserva rejeitada (pela Edge ou, sem pré-pagamento, pela RPC).
class RecusaReserva {
  const RecusaReserva({required this.devolucao, this.valorCents = 0});

  final DevolucaoDaReserva devolucao;
  final int valorCents;

  /// Lê a resposta da Edge `partner-reject-reservation`
  /// (`refund.result`: succeeded · already_refunded · not_applicable ·
  /// not_paid · failed). Resposta que não se reconhece → a equipa trata:
  /// nunca se diz que o dinheiro foi devolvido sem a Edge o confirmar.
  factory RecusaReserva.daResposta(Object? data, {int prePagamentoCents = 0}) {
    final refund = data is Map ? data['refund'] : null;
    final resultado = refund is Map ? refund['result']?.toString() : null;
    final bruto = refund is Map ? refund['amount_cents'] : null;
    final cents = bruto is num && bruto > 0 ? bruto.toInt() : prePagamentoCents;
    switch (resultado) {
      case 'succeeded':
        return RecusaReserva(
            devolucao: DevolucaoDaReserva.pedida, valorCents: cents);
      case 'already_refunded':
        return RecusaReserva(
            devolucao: DevolucaoDaReserva.jaFeita, valorCents: cents);
      case 'not_applicable':
      case 'not_paid':
        return const RecusaReserva(
            devolucao: DevolucaoDaReserva.semPrePagamento);
      default:
        return RecusaReserva(
            devolucao: DevolucaoDaReserva.aCargoDaEquipa, valorCents: cents);
    }
  }

  /// A frase para o parceiro: só o que aconteceu de facto.
  String get texto => switch (devolucao) {
        DevolucaoDaReserva.pedida =>
          'Reserva rejeitada. O cliente foi avisado e a devolução de {0} já foi pedida.'
              .trArgs([eurCents(valorCents)]),
        DevolucaoDaReserva.jaFeita =>
          'Reserva rejeitada. A devolução de {0} ao cliente já tinha sido feita.'
              .trArgs([eurCents(valorCents)]),
        DevolucaoDaReserva.semPrePagamento =>
          'Reserva rejeitada. O cliente foi avisado.'.tr,
        DevolucaoDaReserva.aCargoDaEquipa =>
          'Reserva rejeitada. O cliente foi avisado e a equipa Bora trata da devolução.'
              .tr,
      };
}

/// Porque é que a rejeição não aconteceu.
enum MotivoFalhaRecusa {
  /// A Edge ainda não foi publicada no servidor (404 da Supabase).
  naoInstalada,
  semRede,
  sessao,
  semAcesso,
  naoEncontrada,
  jaDecidida,
  outro,
}

/// A rejeição falhou: a reserva continua como estava.
class RecusaReservaFalhou implements Exception {
  const RecusaReservaFalhou(this.motivo);

  final MotivoFalhaRecusa motivo;

  /// Código HTTP + corpo da resposta → motivo. A Supabase responde 404 sem o
  /// nosso campo `error` quando a função não existe; o 404 da própria Edge
  /// traz `error: reservation_not_found`. Código 0 = o pedido nem chegou
  /// ao servidor.
  static MotivoFalhaRecusa motivoDe(int status, Object? detalhes) {
    final erro = detalhes is Map ? detalhes['error']?.toString() : null;
    if (status == 0) return MotivoFalhaRecusa.semRede;
    if (status == 401) return MotivoFalhaRecusa.sessao;
    if (status == 403) return MotivoFalhaRecusa.semAcesso;
    if (status == 404) {
      return erro == 'reservation_not_found'
          ? MotivoFalhaRecusa.naoEncontrada
          : MotivoFalhaRecusa.naoInstalada;
    }
    if (status == 409) return MotivoFalhaRecusa.jaDecidida;
    return MotivoFalhaRecusa.outro;
  }

  String get texto => switch (motivo) {
        MotivoFalhaRecusa.naoInstalada =>
          'Esta parte ainda não está instalada; tenta mais tarde ou fala com a equipa Bora.'
              .tr,
        MotivoFalhaRecusa.semRede =>
          'Sem ligação. Verifica a internet e tenta outra vez.'.tr,
        MotivoFalhaRecusa.sessao => 'A tua sessão terminou. Entra outra vez.'.tr,
        MotivoFalhaRecusa.semAcesso => 'Não tens acesso a esta reserva.'.tr,
        MotivoFalhaRecusa.naoEncontrada => 'Reserva não encontrada.'.tr,
        MotivoFalhaRecusa.jaDecidida =>
          'Esta reserva já foi decidida. Atualiza a lista.'.tr,
        MotivoFalhaRecusa.outro =>
          'Não foi possível concluir. Atualiza a lista e tenta de novo.'.tr,
      };

  @override
  String toString() => texto;
}
