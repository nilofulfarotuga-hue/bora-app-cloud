import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tvde_ride.dart';
import '../models/tvde_subscription.dart';

/// TVDE — Bora Motorista. Store reativo do cliente (passageiro).
/// Camada read-only: todas as transições passam por RPC no backend.
class TvdeStore extends ChangeNotifier {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  // ── Acesso à categoria escondida ────────────────────────────────────────
  bool _tvdeAccess = false;
  bool get tvdeAccess => _tvdeAccess;

  /// null | 'pendente' | 'aprovado' | 'recusado'
  String? _accessRequestStatus;
  String? get accessRequestStatus => _accessRequestStatus;

  // ── Corrida ativa + histórico + assinatura ──────────────────────────────
  TvdeRide? _activeRide;
  TvdeRide? get activeRide => _activeRide;

  List<TvdeRide> _history = const [];
  List<TvdeRide> get history => _history;

  TvdeSubscription? _subscription;
  TvdeSubscription? get subscription => _subscription;

  int _dailyUsed = 0;
  int get dailyUsed => _dailyUsed;

  bool _busy = false;
  bool get busy => _busy;

  RealtimeChannel? _channel;

  // ════════════════════════════════════════════════════════════════════════
  // ACESSO
  // ════════════════════════════════════════════════════════════════════════

  // [D/adenda] guarda contra recursão no retry pós-falha de sessão.
  bool _retriedAfterAuth = false;

  /// Re-lê tvde_access + estado do último pedido. Chamar no load/resume da home.
  ///
  /// [D/adenda 2026-06-30] Resiliência de sessão: nos logs há
  /// `AuthApiException: Invalid Refresh Token`. Se a query falhasse (sessão
  /// inválida) ou devolvesse null (RLS transitória), o tile "Bora Motorista"
  /// desaparecia mesmo com tvde_access=TRUE. Agora:
  ///   • só esconde se tvde_access vier EXPLICITAMENTE false;
  ///   • em null (linha ausente) mantém o estado actual;
  ///   • em erro de sessão refresca a sessão e re-busca UMA vez antes de
  ///     desistir — e nunca esconde por erro transitório.
  Future<void> refreshAccess() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final user = await _sb
          .from('users')
          .select('tvde_access')
          .eq('id', uid)
          .maybeSingle();
      if (user != null) {
        _tvdeAccess = (user['tvde_access'] as bool?) ?? false;
      } else {
        debugPrint(
            'TvdeStore.refreshAccess: users sem linha — mantém tvdeAccess=$_tvdeAccess');
      }

      final req = await _sb
          .from('tvde_access_requests')
          .select('status')
          .eq('client_id', uid)
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _accessRequestStatus = req?['status'] as String?;
      _retriedAfterAuth = false; // sucesso — limpa o guard
      notifyListeners();
    } catch (e) {
      // Falha de sessão (Invalid Refresh Token) NÃO pode esconder o tile.
      // Refresca a sessão e re-busca uma vez; o estado fica inalterado se falhar.
      debugPrint('TvdeStore.refreshAccess error => $e');
      if (!_retriedAfterAuth) {
        _retriedAfterAuth = true;
        try {
          await _sb.auth.refreshSession();
          await refreshAccess();
        } catch (e2) {
          debugPrint('TvdeStore.refreshAccess: refreshSession falhou => $e2');
        }
      }
    }
  }

  /// Cliente pede desbloqueio → cria tvde_access_requests (pendente) + notifica admin.
  Future<void> requestAccess() async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_request_access');
      _accessRequestStatus = 'pendente';
    } catch (e) {
      debugPrint('TvdeStore.requestAccess error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // PREÇO ESTIMADO
  // ════════════════════════════════════════════════════════════════════════

  /// Preço estimado (cêntimos) via RPC tvde_calculate_fare. -1 em erro.
  Future<int> estimateFareCents(double distanceKm) async {
    try {
      final res = await _sb.rpc('tvde_calculate_fare',
          params: {'p_distance_km': distanceKm});
      return (res as num?)?.toInt() ?? -1;
    } catch (e) {
      debugPrint('TvdeStore.estimateFareCents error => $e');
      return -1;
    }
  }

  /// Preço do plano (cêntimos) via RPC tvde_plan_price_cents (server-side,
  /// única fonte da verdade — nunca hardcodar no ecrã). null em erro.
  Future<int?> planPriceCents(String plan) async {
    try {
      final res =
          await _sb.rpc('tvde_plan_price_cents', params: {'p_plan': plan});
      return (res as num?)?.toInt();
    } catch (e) {
      debugPrint('TvdeStore.planPriceCents error => $e');
      return null;
    }
  }

  /// [Item B] Cobertura pelo plano SEM consumir (RPC read-only). Devolve
  /// {covered, daily_used, daily_included, rides_left, reason}. {} em erro.
  Future<Map<String, dynamic>> previewCoverage() async {
    final uid = _uid;
    if (uid == null) return const {};
    try {
      final res =
          await _sb.rpc('tvde_preview_coverage', params: {'p_client_id': uid});
      return res is Map ? Map<String, dynamic>.from(res) : const {};
    } catch (e) {
      debugPrint('TvdeStore.previewCoverage error => $e');
      return const {};
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // CORRIDA
  // ════════════════════════════════════════════════════════════════════════

  /// Solicita corrida. Devolve a corrida criada e começa a ouvi-la ao vivo.
  Future<TvdeRide?> requestRide({
    required double originLat,
    required double originLng,
    String? originLabel,
    required double destLat,
    required double destLng,
    String? destLabel,
    required double distanceKm,
    // Método de pagamento (backend aplicado via MCP). DEFAULT 'cash' → app
    // antigo e fluxo dinheiro continuam iguais. Com o kill switch
    // (tvde_card_payments_enabled) desligado, a RPC rejeita card/mbway.
    String paymentMethod = 'cash',
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_request_ride', params: {
        'p_origin_lat': originLat,
        'p_origin_lng': originLng,
        'p_origin_label': originLabel,
        'p_dest_lat': destLat,
        'p_dest_lng': destLng,
        'p_dest_label': destLabel,
        'p_est_distance_km': distanceKm,
        'p_payment_method': paymentMethod,
      });
      final ride = TvdeRide.fromMap(_asMap(res));
      _activeRide = ride;
      _subscribeRide(ride.id);
      notifyListeners();
      return ride;
    } catch (e) {
      debugPrint('TvdeStore.requestRide error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Corrida paga ONLINE (card/mbway). Invoca a Edge Function `tvde-payment`,
  /// que valida o kill switch, autoriza/cobra no Stripe e SÓ ENTÃO cria a
  /// corrida (nunca cria ride sem pagamento). Só é chamada com o switch ligado
  /// — a UI esconde card/mbway quando `tvde_card_payments_enabled` está OFF.
  /// [confirmCard] confirma o clientSecret (autoriza o hold de captura manual).
  Future<TvdeRide?> requestRidePaid({
    required double originLat,
    required double originLng,
    String? originLabel,
    required double destLat,
    required double destLng,
    String? destLabel,
    required double distanceKm,
    required String method, // 'card' | 'mbway'
    String? mbwayPhone,
    Future<void> Function(String clientSecret)? confirmCard,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.functions.invoke('tvde-payment', body: {
        'action': method == 'card' ? 'authorize' : 'charge',
        'origin_lat': originLat,
        'origin_lng': originLng,
        'origin_label': originLabel,
        'dest_lat': destLat,
        'dest_lng': destLng,
        'dest_label': destLabel,
        'distance_km': distanceKm,
        'method': method,
        if (mbwayPhone != null) 'phone': mbwayPhone,
      });
      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error'].toString());
      // Cartão → confirma o hold (autoriza a captura manual do valor final).
      final clientSecret = data['clientSecret'] as String?;
      if (method == 'card' && clientSecret != null && confirmCard != null) {
        await confirmCard(clientSecret);
      }
      final rideMap = data['ride'];
      if (rideMap is Map) {
        final ride = TvdeRide.fromMap(Map<String, dynamic>.from(rideMap));
        _activeRide = ride;
        _subscribeRide(ride.id);
        notifyListeners();
        return ride;
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.requestRidePaid error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Carrega a corrida ativa (se existir) ao abrir a app.
  Future<void> loadActiveRide() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('tvde_rides')
          .select()
          .eq('client_id', uid)
          // P0-3 2026-07-02: 'sem_motorista' é TERMINAL para o resume — não
          // reabrir o tracking antigo (€/endereço velhos) ao voltar à app.
          // Espelha o guard "em curso" do backend tvde_request_ride.
          .inFilter('status', const [
            'solicitada',
            'motorista_atribuido',
            'motorista_a_caminho',
            'motorista_chegou',
            'em_andamento',
          ])
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        _activeRide = TvdeRide.fromMap(rows.first);
        _subscribeRide(_activeRide!.id);
      } else {
        _activeRide = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeStore.loadActiveRide error => $e');
    }
  }

  void _subscribeRide(String rideId) {
    _unsubscribe();
    _channel = _sb.channel('tvde_ride_$rideId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'tvde_rides',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: rideId,
        ),
        callback: (payload) {
          final m = payload.newRecord;
          _activeRide = TvdeRide.fromMap(m);
          notifyListeners();
        },
      )
      ..subscribe();
  }

  /// Tentar de novo após sem_motorista (cria nova corrida com os mesmos pontos).
  Future<TvdeRide?> retryRide() async {
    final r = _activeRide;
    if (r == null) return null;
    return requestRide(
      originLat: r.originLat,
      originLng: r.originLng,
      originLabel: r.originLabel,
      destLat: r.destLat,
      destLng: r.destLng,
      destLabel: r.destLabel,
      distanceKm: r.estDistanceKm,
    );
  }

  Future<void> cancelRide(String rideId, {String? reason}) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_cancel_ride', params: {
        'p_ride_id': rideId,
        'p_actor': 'cliente',
        'p_reason': reason,
      });
    } catch (e) {
      debugPrint('TvdeStore.cancelRide error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // [CAMPO-02 · Feature 1] PARADAS ADICIONAIS
  // ════════════════════════════════════════════════════════════════════════

  /// Lê um int de platform_settings via get_setting; devolve [fallback] em erro.
  /// (Não há cache central no app — cada call site lê direto, como o resto.)
  Future<int> getSettingInt(String key, int fallback) async {
    try {
      final res = await _sb.rpc('get_setting', params: {'p_key': key});
      if (res == null) return fallback;
      return int.tryParse(res.toString()) ?? fallback;
    } catch (e) {
      debugPrint('TvdeStore.getSettingInt($key) error => $e');
      return fallback;
    }
  }

  /// Lê um bool de platform_settings (ex.: o kill switch
  /// `tvde_card_payments_enabled`). Falha fechada → devolve [fallback].
  Future<bool> getSettingBool(String key, bool fallback) async {
    try {
      final res = await _sb.rpc('get_setting', params: {'p_key': key});
      if (res == null) return fallback;
      final s = res.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 't';
    } catch (e) {
      debugPrint('TvdeStore.getSettingBool($key) error => $e');
      return fallback;
    }
  }

  /// Cliente adiciona uma parada no meio da corrida (2 EUR, até tvde_max_stops).
  /// Devolve os totais atualizados ({extra_stops_count, extra_stops_fee_cents,…})
  /// ou lança em erro (ex.: max_stops_reached). O realtime atualiza a corrida.
  Future<Map<String, dynamic>> addStop(
    String rideId, {
    required double lat,
    required double lng,
    String? label,
    double segmentKm = 0,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_add_stop', params: {
        'p_ride_id': rideId,
        'p_lat': lat,
        'p_lng': lng,
        'p_label': label,
        'p_segment_km': segmentKm,
      });
      return res is Map ? Map<String, dynamic>.from(res) : const {};
    } catch (e) {
      debugPrint('TvdeStore.addStop error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Cliente remove uma parada (só antes de o motorista lá chegar).
  Future<void> removeStop(String rideId, String stopId) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_remove_stop',
          params: {'p_ride_id': rideId, 'p_stop_id': stopId});
    } catch (e) {
      debugPrint('TvdeStore.removeStop error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Motorista marca chegada à parada (arranca o timer informativo de espera).
  Future<void> reachStop(String rideId, String stopId) async {
    try {
      await _sb.rpc('tvde_reach_stop',
          params: {'p_ride_id': rideId, 'p_stop_id': stopId});
    } catch (e) {
      debugPrint('TvdeStore.reachStop error => $e');
      rethrow;
    }
  }

  /// Lista as paradas ativas (não removidas) de uma corrida, por ordem.
  Future<List<TvdeRideStop>> fetchRideStops(String rideId) async {
    try {
      final rows = await _sb
          .from('tvde_ride_stops')
          .select()
          .eq('ride_id', rideId)
          .isFilter('removed_at', null)
          .order('seq', ascending: true);
      return rows
          .map<TvdeRideStop>((m) => TvdeRideStop.fromMap(m))
          .toList();
    } catch (e) {
      debugPrint('TvdeStore.fetchRideStops error => $e');
      return const [];
    }
  }

  Future<void> rateDriver(String rideId, int stars, {String? comment}) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_rate', params: {
        'p_ride_id': rideId,
        'p_stars': stars,
        'p_comment': comment,
      });
    } catch (e) {
      debugPrint('TvdeStore.rateDriver error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Limpa a corrida ativa do estado (após concluir/avaliar/cancelar).
  void clearActiveRide() {
    _unsubscribe();
    _activeRide = null;
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════════
  // HISTÓRICO + ASSINATURA
  // ════════════════════════════════════════════════════════════════════════

  Future<void> loadHistory() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('tvde_rides')
          .select()
          .eq('client_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      _history = rows.map<TvdeRide>((m) => TvdeRide.fromMap(m)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeStore.loadHistory error => $e');
    }
  }

  // ── Pedido de adesão a plano (C4) ──────────────────────────────────────
  /// null | 'pendente' | 'aprovado' | 'recusado'
  String? _planRequestStatus;
  String? get planRequestStatus => _planRequestStatus;

  /// Lê o estado do último pedido de plano do cliente (para a UI mostrar
  /// "pedido enviado"). Best-effort.
  Future<void> loadPlanRequest() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final req = await _sb
          .from('tvde_plan_requests')
          .select('status')
          .eq('client_id', uid)
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _planRequestStatus = req?['status'] as String?;
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeStore.loadPlanRequest error => $e');
    }
  }

  /// Cliente pede adesão a um plano → tvde_plan_requests (pendente) + notifica
  /// admin. O admin aprova/ativa num clique no painel.
  Future<void> requestPlan(String plan, String planLabel) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_request_plan',
          params: {'p_plan': plan, 'p_plan_label': planLabel});
      _planRequestStatus = 'pendente';
    } catch (e) {
      debugPrint('TvdeStore.requestPlan error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> loadSubscription() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final sub = await _sb
          .from('tvde_subscriptions')
          .select()
          .eq('client_id', uid)
          .eq('active', true)
          .order('ends_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _subscription = sub == null ? null : TvdeSubscription.fromMap(sub);

      final today = DateTime.now().toUtc();
      final dayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final counter = await _sb
          .from('tvde_ride_counters')
          .select('rides_count')
          .eq('client_id', uid)
          .eq('day', dayStr)
          .maybeSingle();
      _dailyUsed = (counter?['rides_count'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeStore.loadSubscription error => $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // [Item A] PAGAMENTO DO PLANO (Stripe, Edge Function isolada tvde-plan-payment)
  // ════════════════════════════════════════════════════════════════════════

  /// Cria o PaymentIntent do plano. Devolve {clientSecret, paymentIntentId,
  /// amountCents} ou null em erro. O preço é calculado SERVER-SIDE.
  Future<Map<String, dynamic>?> createPlanPayment(String plan) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment',
          body: {'action': 'create', 'plan': plan});
      final data = res.data;
      if (data is Map && data['clientSecret'] != null) {
        return Map<String, dynamic>.from(data);
      }
      debugPrint('TvdeStore.createPlanPayment bad response => $data');
      return null;
    } catch (e) {
      debugPrint('TvdeStore.createPlanPayment error => $e');
      return null;
    }
  }

  /// Ativa a subscrição após o pagamento — a Edge Function verifica o PI na
  /// Stripe (succeeded + dono + valor). Recarrega a subscrição. Lança em erro.
  Future<void> activatePlan(String plan, String paymentIntentId) async {
    final res = await _sb.functions.invoke('tvde-plan-payment', body: {
      'action': 'activate',
      'plan': plan,
      'payment_intent_id': paymentIntentId,
    });
    final data = res.data;
    if (data is Map && data['subscription'] != null) {
      await loadSubscription();
      return;
    }
    throw Exception('activate_failed: $data');
  }

  /// [Item A · MB Way] Cria + confirma o PaymentIntent MB Way do plano (a Stripe
  /// envia o push para a app MB WAY na hora). Devolve {paymentIntentId, status,
  /// amountCents} ou null. A ativação faz-se depois por poll a [activatePlan]
  /// (retrieve do PI na Edge Fn isolada — sem webhook). Reaproveita o MESMO
  /// método MB Way das Reservas/Serviços (server-confirm com billing phone E.164).
  Future<Map<String, dynamic>?> createPlanPaymentMbway(
      String plan, String phone) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment',
          body: {'action': 'create_mbway', 'plan': plan, 'phone': phone});
      final data = res.data;
      if (data is Map && data['paymentIntentId'] != null) {
        return Map<String, dynamic>.from(data);
      }
      debugPrint('TvdeStore.createPlanPaymentMbway bad response => $data');
      return null;
    } catch (e) {
      debugPrint('TvdeStore.createPlanPaymentMbway error => $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // [CAMPO-02 · Feature 3] IDA-E-VOLTA "Garantir a volta"
  // ════════════════════════════════════════════════════════════════════════

  /// Cria o PaymentIntent do pacote ida-e-volta (cartão). Preço SERVER-SIDE
  /// (tvde_roundtrip_price_cents). Reusa a Edge Fn tvde-plan-payment (item A).
  Future<Map<String, dynamic>?> createRoundtripPayment() async {
    try {
      final res = await _sb.functions
          .invoke('tvde-plan-payment', body: {'action': 'create_roundtrip'});
      final data = res.data;
      if (data is Map && data['clientSecret'] != null) {
        return Map<String, dynamic>.from(data);
      }
      debugPrint('TvdeStore.createRoundtripPayment bad response => $data');
      return null;
    } catch (e) {
      debugPrint('TvdeStore.createRoundtripPayment error => $e');
      return null;
    }
  }

  /// MB Way do pacote ida-e-volta (server-confirm com phone E.164).
  Future<Map<String, dynamic>?> createRoundtripPaymentMbway(String phone) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment',
          body: {'action': 'create_roundtrip_mbway', 'phone': phone});
      final data = res.data;
      if (data is Map && data['paymentIntentId'] != null) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.createRoundtripPaymentMbway error => $e');
      return null;
    }
  }

  /// Ativa o vale-volta após o pagamento: liga a corrida de ida ao vale.
  Future<bool> activateRoundtrip(
      String outboundRideId, String paymentIntentId) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment', body: {
        'action': 'activate_roundtrip',
        'outbound_ride_id': outboundRideId,
        'payment_intent_id': paymentIntentId,
      });
      return res.data is Map && (res.data as Map)['credit'] != null;
    } catch (e) {
      debugPrint('TvdeStore.activateRoundtrip error => $e');
      return false;
    }
  }

  /// Lê o vale-volta ativo do cliente ({} se não houver). Para "Chamar a volta".
  Future<Map<String, dynamic>?> activeRoundtripCredit() async {
    try {
      final res = await _sb.rpc('tvde_active_roundtrip_credit');
      if (res is List && res.isNotEmpty) {
        return Map<String, dynamic>.from(res.first as Map);
      }
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (e) {
      debugPrint('TvdeStore.activeRoundtripCredit error => $e');
      return null;
    }
  }

  /// Dispara a corrida de VOLTA usando o vale (desacoplada — corrida separada).
  Future<TvdeRide?> requestReturnRide({
    required String creditId,
    required double originLat,
    required double originLng,
    String? originLabel,
    required double destLat,
    required double destLng,
    String? destLabel,
    required double distanceKm,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_request_return_ride', params: {
        'p_credit_id': creditId,
        'p_origin_lat': originLat,
        'p_origin_lng': originLng,
        'p_origin_label': originLabel,
        'p_dest_lat': destLat,
        'p_dest_lng': destLng,
        'p_dest_label': destLabel,
        'p_est_distance_km': distanceKm,
      });
      final ride = TvdeRide.fromMap(_asMap(res));
      _activeRide = ride;
      _subscribeRide(ride.id);
      notifyListeners();
      return ride;
    } catch (e) {
      debugPrint('TvdeStore.requestReturnRide error => $e');
      rethrow;
    } finally {
      _setBusy(false);
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
