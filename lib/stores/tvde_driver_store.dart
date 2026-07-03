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

  /// Corrida EM FILA (back-to-back): aceite durante a viagem atual
  /// ('motorista_atribuido' + is_queued). Máx 1; ativa-se no backend ao
  /// finalizar/cancelar a viagem atual.
  TvdeRide? _queuedRide;
  TvdeRide? get queuedRide => _queuedRide;

  /// Janela (minutos) de espera no pickup antes de habilitar
  /// "Passageiro não apareceu" (platform_settings.tvde_noshow_wait_minutes).
  int _noshowWaitMinutes = 5;
  int get noshowWaitMinutes => _noshowWaitMinutes;

  bool _busy = false;
  bool get busy => _busy;

  /// Preferência de trabalho: 'everything' (tudo) | 'rides_only' (só corridas).
  String _workMode = 'everything';
  String get workMode => _workMode;
  bool get ridesOnly => _workMode == 'rides_only';

  /// Ganhos do dia (cêntimos) — soma dos `driver_earn_cents` das corridas
  /// finalizadas hoje. Mostrado na home (estilo Uber Driver).
  int _todayEarnCents = 0;
  int get todayEarnCents => _todayEarnCents;

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
    await loadWorkMode();
    await loadTodayEarnings();
    await loadNoshowWait();
  }

  /// Lê a janela de no-show (best-effort; default 5 min).
  Future<void> loadNoshowWait() async {
    try {
      final v = await _sb
          .rpc('get_setting', params: {'p_key': 'tvde_noshow_wait_minutes'});
      final n = v is num ? v.toInt() : int.tryParse(v.toString());
      if (n != null && n >= 0) {
        _noshowWaitMinutes = n;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('TvdeDriverStore.loadNoshowWait error => $e');
    }
  }

  /// Soma os ganhos das corridas finalizadas hoje (por dia local).
  Future<void> loadTodayEarnings() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      final startLocalUtc = DateTime(now.year, now.month, now.day).toUtc();
      final rows = await _sb
          .from('tvde_rides')
          .select('driver_earn_cents')
          .eq('driver_id', uid)
          .eq('status', 'finalizada')
          .gte('updated_at', startLocalUtc.toIso8601String());
      var sum = 0;
      for (final r in rows) {
        sum += (r['driver_earn_cents'] as num?)?.toInt() ?? 0;
      }
      _todayEarnCents = sum;
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeDriverStore.loadTodayEarnings error => $e');
    }
  }

  /// Lê a preferência de trabalho do motorista (drivers.work_mode).
  Future<void> loadWorkMode() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final row = await _sb
          .from('drivers')
          .select('work_mode')
          .eq('user_id', uid)
          .maybeSingle();
      _workMode = (row?['work_mode'] as String?) ?? 'everything';
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeDriverStore.loadWorkMode error => $e');
    }
  }

  /// Grava a preferência ('everything' | 'rides_only') via RPC.
  Future<void> setWorkMode(String mode) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_set_work_mode', params: {'p_mode': mode});
      _workMode = mode;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
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
          .eq('is_queued', false)
          .inFilter('status', _activeStatuses)
          .order('updated_at', ascending: false)
          .limit(1);
      _activeRide = active.isEmpty ? null : TvdeRide.fromMap(active.first);

      // Corrida em fila (back-to-back), se existir.
      final queued = await _sb
          .from('tvde_rides')
          .select()
          .eq('driver_id', uid)
          .eq('is_queued', true)
          .eq('status', 'motorista_atribuido')
          .limit(1);
      _queuedRide = queued.isEmpty ? null : TvdeRide.fromMap(queued.first);

      // Oferta: quando livre, OU em viagem 'em_andamento' sem fila (o backend
      // só oferece nesse estado — tier 2 do tvde_offer_to_next).
      final canReceiveOffer = _activeRide == null ||
          (_activeRide!.isInProgress && _queuedRide == null);
      if (canReceiveOffer) {
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
        callback: (payload) {
          // [Item E] DELETE não traz newRecord → tratar à parte, senão uma
          // oferta removida fica presa no ecrã (o "travou" do teste de campo).
          if (payload.eventType == PostgresChangeEvent.delete) {
            _onRideDeleted(payload.oldRecord);
          } else {
            _onRideChange(payload.newRecord);
          }
        },
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
      // Back-to-back: corrida em fila nunca substitui a ativa.
      if (ride.isQueued && ride.status == 'motorista_atribuido') {
        _queuedRide = ride;
        _offeredRide = null;
        notifyListeners();
        return;
      }
      if (_activeStatuses.contains(ride.status)) {
        // Ativação da fila (a_caminho vinda da fila) ou update da ativa.
        if (_queuedRide?.id == ride.id) _queuedRide = null;
        _activeRide = ride;
        _offeredRide = null;
      } else if (ride.isTerminal) {
        if (_queuedRide?.id == ride.id) {
          // A corrida em fila caiu (passageiro cancelou) — limpa o indicador.
          _queuedRide = null;
        } else if (_activeRide?.id == ride.id) {
          // finalizada/cancelada — a UI trata a transição; mantemos o objeto
          // até o ecrã ativo o consumir (avaliação) e chamar clearActive().
          _activeRide = ride;
        }
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

  /// [Item E] Corrida APAGADA (raro em produção — normalmente muda de estado via
  /// UPDATE — mas defensivo): se era a oferta/fila/ativa atual, limpa para nunca
  /// prender o ecrã de oferta. O DELETE só traz o oldRecord (PK).
  void _onRideDeleted(Map<String, dynamic>? oldRecord) {
    if (oldRecord == null || oldRecord.isEmpty) return;
    final deletedId = oldRecord['id'] as String?;
    if (deletedId == null) return;
    var changed = false;
    if (_offeredRide?.id == deletedId) {
      _offeredRide = null;
      changed = true;
    }
    if (_queuedRide?.id == deletedId) {
      _queuedRide = null;
      changed = true;
    }
    if (_activeRide?.id == deletedId) {
      _activeRide = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════════
  // AÇÕES DO MOTORISTA (RPCs Fase 1/2 — params exatos)
  // ════════════════════════════════════════════════════════════════════════

  /// Aceita a oferta (atómico). Devolve a corrida ('motorista_a_caminho' —
  /// ou 'motorista_atribuido' EM FILA se o motorista está em viagem).
  /// Lança em caso de corrida já reivindicada/expirada — a UI traduz.
  Future<TvdeRide> acceptOffer(String rideId) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_accept_ride', params: {'p_ride_id': rideId});
      final ride = TvdeRide.fromMap(_asMap(res));
      if (ride.isQueued) {
        // back-to-back: fica em fila; a viagem atual continua ativa.
        _queuedRide = ride;
      } else {
        _activeRide = ride;
      }
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
  /// Back-to-back: se havia corrida em fila, o backend ativou-a — recarrega o
  /// estado (a ativada passa a `activeRide`) e devolve a corrida FINALIZADA
  /// (para o resumo do ganho). Sem fila, comporta-se como antes.
  Future<TvdeRide> finishRide(String rideId, double finalDistanceKm,
      {String? distanceSource}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_finish_ride', params: {
        'p_ride_id': rideId,
        'p_final_distance_km': finalDistanceKm,
        if (distanceSource != null) 'p_distance_source': distanceSource,
      });
      final finished = TvdeRide.fromMap(_asMap(res));
      if (_queuedRide != null) {
        _activeRide = null;
        _offeredRide = null;
        await loadCurrent(); // apanha a corrida ativada ('motorista_a_caminho')
      } else {
        _activeRide = finished;
      }
      notifyListeners();
      return finished;
    } finally {
      _setBusy(false);
    }
  }

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
      if (_queuedRide != null && _activeRide?.id == rideId) {
        // back-to-back: a ativa caiu → o backend ativou a corrida em fila.
        _activeRide = null;
        _offeredRide = null;
        await loadCurrent();
      } else {
        _activeRide = ride;
        _offeredRide = null;
      }
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
