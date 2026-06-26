import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tvde_ride.dart';

/// TVDE — Bora Motorista. Store reativo do MOTORISTA (modo passageiros).
/// 100% isolado do delivery (OrderStore/DispatchEngine intocados). Todas as
/// transições passam por RPC no backend (Fase 1+2); aqui só lemos e chamamos.
///
/// - Oferta: o backend grava `current_offer_driver_id = <este motorista>` e o
///   push (`notify-tvde-driver`) acorda o app. A RLS de `tvde_rides` deixa o
///   motorista ver as corridas ofertadas/atribuídas a si.
/// - Aceite atómico: `tvde_accept_ride` (Fase 2). Se já foi reivindicada/expirou
///   a RPC falha e a UI mostra "oferta já não disponível" — sem crashar.
class TvdeDriverStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// Oferta pendente para este motorista (status 'solicitada').
  TvdeRide? _offeredRide;
  TvdeRide? get offeredRide => _offeredRide;

  /// Corrida ativa atribuída a este motorista (a caminho → em andamento).
  TvdeRide? _activeRide;
  TvdeRide? get activeRide => _activeRide;

  bool _busy = false;
  bool get busy => _busy;

  RealtimeChannel? _channel;

  static const _activeStatuses = <String>[
    'motorista_atribuido',
    'motorista_a_caminho',
    'motorista_chegou',
    'em_andamento',
  ];

  // ════════════════════════════════════════════════════════════════════════
  // ARRANQUE / REALTIME
  // ════════════════════════════════════════════════════════════════════════

  /// Liga o realtime e carrega oferta/corrida ativa. Idempotente.
  Future<void> start() async {
    _subscribe();
    await loadCurrent();
  }

  /// Re-lê do servidor a oferta pendente e a corrida ativa deste motorista.
  /// Chamar no toggle Online, no resume e ao tocar na notificação (deep-link).
  Future<void> loadCurrent() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final active = await _sb
          .from('tvde_rides')
          .select()
          .eq('driver_id', uid)
          .inFilter('status', _activeStatuses)
          .order('updated_at', ascending: false)
          .limit(1);
      _activeRide = active.isEmpty ? null : TvdeRide.fromMap(active.first);

      // Só procuramos oferta se não há corrida ativa em curso.
      if (_activeRide == null) {
        final offer = await _sb
            .from('tvde_rides')
            .select()
            .eq('current_offer_driver_id', uid)
            .eq('status', 'solicitada')
            .order('offer_expires_at', ascending: false)
            .limit(1);
        _offeredRide = offer.isEmpty ? null : TvdeRide.fromMap(offer.first);
      } else {
        _offeredRide = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeDriverStore.loadCurrent error => $e');
    }
  }

  void _subscribe() {
    final uid = _uid;
    if (uid == null || _channel != null) return;
    _channel = _sb.channel('tvde_driver_$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tvde_rides',
        callback: (payload) => _onRideChange(payload.newRecord),
      )
      ..subscribe();
  }

  void _onRideChange(Map<String, dynamic>? record) {
    if (record == null || record.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    final ride = TvdeRide.fromMap(record);

    // Corrida ativa minha → atualiza/limpa.
    if (ride.driverId == uid) {
      if (_activeStatuses.contains(ride.status)) {
        _activeRide = ride;
        _offeredRide = null;
      } else if (ride.isTerminal && _activeRide?.id == ride.id) {
        // finalizada/cancelada — a UI trata a transição; mantemos o objeto
        // até o ecrã ativo o consumir (avaliação) e chamar clearActive().
        _activeRide = ride;
      }
      notifyListeners();
      return;
    }

    // Oferta para mim (ainda por aceitar).
    if (ride.currentOfferDriverId == uid && ride.status == 'solicitada') {
      _offeredRide = ride;
      notifyListeners();
    } else if (_offeredRide?.id == ride.id) {
      // A oferta saiu de mim (expirou/recusada → passou ao próximo) ou mudou
      // de estado. Limpa para fechar o ecrã de oferta.
      _offeredRide = null;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // AÇÕES DO MOTORISTA (RPCs Fase 1/2 — params exatos)
  // ════════════════════════════════════════════════════════════════════════

  /// Aceita a oferta (atómico). Devolve a corrida ('motorista_a_caminho').
  /// Lança em caso de corrida já reivindicada/expirada — a UI traduz.
  Future<TvdeRide> acceptOffer(String rideId) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_accept_ride', params: {'p_ride_id': rideId});
      final ride = TvdeRide.fromMap(_asMap(res));
      _activeRide = ride;
      _offeredRide = null;
      notifyListeners();
      return ride;
    } finally {
      _setBusy(false);
    }
  }

  /// Recusa a oferta → backend liberta para o próximo motorista (dispatch).
  Future<void> rejectOffer(String rideId) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_reject_ride', params: {'p_ride_id': rideId});
      _offeredRide = null;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<TvdeRide> markArrived(String rideId) =>
      _transition('tvde_driver_arrived', {'p_ride_id': rideId});

  Future<TvdeRide> startRide(String rideId) =>
      _transition('tvde_start_ride', {'p_ride_id': rideId});

  /// Finaliza com a distância real → tarifa final + ganho motorista/Bora.
  Future<TvdeRide> finishRide(String rideId, double finalDistanceKm) =>
      _transition('tvde_finish_ride',
          {'p_ride_id': rideId, 'p_final_distance_km': finalDistanceKm});

  /// Cancela a corrida. [noShow]=true quando o passageiro não compareceu.
  Future<TvdeRide> cancelRide(String rideId,
      {bool noShow = false, String? reason}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_cancel_ride', params: {
        'p_ride_id': rideId,
        'p_actor': noShow ? 'no_show' : 'motorista',
        'p_reason': reason,
      });
      final ride = TvdeRide.fromMap(_asMap(res));
      _activeRide = ride;
      _offeredRide = null;
      notifyListeners();
      return ride;
    } finally {
      _setBusy(false);
    }
  }

  /// Avalia o passageiro (tvde_rate deteta o sujeito por quem chama:
  /// motorista → subject_type='tvde_passenger'). Best-effort.
  Future<void> ratePassenger(String rideId, int stars, {String? comment}) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_rate', params: {
        'p_ride_id': rideId,
        'p_stars': stars,
        'p_comment': comment,
      });
    } finally {
      _setBusy(false);
    }
  }

  Future<TvdeRide> _transition(String rpc, Map<String, dynamic> params) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc(rpc, params: params);
      final ride = TvdeRide.fromMap(_asMap(res));
      _activeRide = ride;
      notifyListeners();
      return ride;
    } finally {
      _setBusy(false);
    }
  }

  // ── limpeza de estado ─────────────────────────────────────────────────────
  void clearOffer() {
    _offeredRide = null;
    notifyListeners();
  }

  void clearActive() {
    _activeRide = null;
    notifyListeners();
  }

  // ── infra ──────────────────────────────────────────────────────────────────
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

  @override
  void dispose() {
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
    super.dispose();
  }
}
