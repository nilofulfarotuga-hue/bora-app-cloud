import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/falha_de_acao.dart';
import '../models/tvde_ride.dart';
import '../models/tvde_subscription.dart';
import '../services/payment_service.dart';

/// TVDE — Bora Motorista. Store reativo do cliente (passageiro).
/// Camada read-only: todas as transições passam por RPC no backend.
/// Corpo do pedido `charge` da Edge Fn `tvde-payment`.
///
/// Funcao pura para fixar em teste a regra que mais custa se partir: o
/// `saved_pm_id` SO pode ir quando o metodo e cartao. Enviado num pagamento
/// MB Way, seria um id de cartao a viajar num fluxo que nao o usa.
Map<String, dynamic> buildTvdeChargeBody({
  required double originLat,
  required double originLng,
  String? originLabel,
  required double destLat,
  required double destLng,
  String? destLabel,
  required double distanceKm,
  required String method,
  String? mbwayPhone,
  int tokensUsed = 0,
  String? savedPmId,
}) {
  return {
    'action': 'charge',
    'origin_lat': originLat,
    'origin_lng': originLng,
    'origin_label': originLabel,
    'dest_lat': destLat,
    'dest_lng': destLng,
    'dest_label': destLabel,
    'distance_km': distanceKm,
    'method': method,
    if (mbwayPhone != null) 'phone': mbwayPhone,
    if (tokensUsed > 0) 'tokens_used': tokensUsed,
    // A EF so respeita saved_pm_id em method:'card'.
    if (method == 'card' && savedPmId != null) 'saved_pm_id': savedPmId,
  };
}

/// Corpo do pedido `charge_reservation` da Edge Fn `tvde-payment` (v10).
///
/// Mesma regra que o `charge`: o `saved_pm_id` SO viaja em cartao. O preco
/// NAO vai no corpo — quem o fecha e o servidor (`est_fare_cents` da reserva
/// criada por `tvde_schedule_ride`). Mandar preco daqui seria deixar o cliente
/// escolher quanto paga.
Map<String, dynamic> buildTvdeReservationChargeBody({
  required double originLat,
  required double originLng,
  String? originLabel,
  required double destLat,
  required double destLng,
  String? destLabel,
  required double distanceKm,
  required DateTime scheduledAt,
  required String method,
  String? mbwayPhone,
  String? note,
  String? savedPmId,
}) {
  return {
    'action': 'charge_reservation',
    'origin_lat': originLat,
    'origin_lng': originLng,
    'origin_label': originLabel,
    'dest_lat': destLat,
    'dest_lng': destLng,
    'dest_label': destLabel,
    'distance_km': distanceKm,
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'method': method,
    if (mbwayPhone != null) 'phone': mbwayPhone,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    if (method == 'card' && savedPmId != null) 'saved_pm_id': savedPmId,
  };
}

/// Traduz para PT-PT os erros das RPCs/Edge Function de reserva.
///
/// Funcao pura de proposito: e o unico sitio onde os codigos crus do servidor
/// viram frase para o cliente, e da para fixar em teste. Codigo desconhecido
/// devolve uma frase neutra — nunca o codigo cru no ecra.
String traduzErroReserva(Object erro) {
  final txt = erro.toString();
  bool tem(String code) => txt.contains(code);

  if (tem('reservations_disabled')) {
    return 'As reservas estão desligadas de momento. Podes pedir uma corrida para agora.';
  }
  if (tem('too_soon')) {
    return 'Essa hora está demasiado em cima. Marca com mais antecedência.';
  }
  if (tem('too_far')) {
    return 'Só dá para marcar dentro dos próximos dias. Escolhe uma data mais perto.';
  }
  if (tem('reservation_overlap')) {
    return 'Já tens uma reserva marcada para essa hora.';
  }
  if (tem('too_many_reservations')) {
    return 'Já tens reservas a mais marcadas. Cancela uma antes de marcar outra.';
  }
  if (tem('card_payments_not_enabled')) {
    return 'Os pagamentos online estão desligados. Marca a reserva para pagar em dinheiro.';
  }
  if (tem('below_minimum')) {
    return 'O valor da viagem é baixo demais para pagar online. Escolhe dinheiro.';
  }
  if (tem('invalid_distance')) {
    return 'Não consegui calcular o trajeto. Confirma a recolha e o destino.';
  }
  if (tem('missing_scheduled_at')) {
    return 'Falta escolher o dia e a hora da reserva.';
  }
  if (tem('not_authenticated')) {
    return 'A tua sessão expirou. Entra outra vez para marcar a reserva.';
  }
  if (tem('cancelled') || tem('cancel')) {
    return 'Pagamento não concluído. A reserva não ficou marcada.';
  }
  return 'Não consegui marcar a reserva. Tenta de novo daqui a pouco.';
}

/// Estado da reserva em português simples, para o cliente ler.
String estadoReservaPt(TvdeRide r) {
  switch (r.reservationStatus) {
    case 'aguarda_pagamento':
      return 'à espera do pagamento';
    case 'a_procurar':
      return 'à procura de motorista';
    case 'atribuida':
      return 'motorista confirmado';
    case 'ativada':
      return 'a caminho';
    case 'sem_motorista':
      return 'sem motorista disponível';
    case 'cancelada':
      return 'cancelada';
    default:
      return 'marcada';
  }
}

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

  // clientSecret do PaymentIntent da corrida ativa (só memória, só cartão).
  // Serve o "Pagar de novo" quando o cliente abre a PaymentSheet e volta sem
  // pagar (2026-08-16, corrida d947b446): o mesmo PI pode ser re-apresentado.
  // Perde-se ao reiniciar a app — nesse caso o botão não aparece e o caminho
  // é cancelar (grátis) e pedir de novo.
  String? _pendingCardSecret;
  String? _pendingCardSecretRideId;
  String? cardClientSecretFor(String rideId) =>
      _pendingCardSecretRideId == rideId ? _pendingCardSecret : null;

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
      await _sb.rpc('tvde_request_access').timeout(kAcaoTimeout);
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
          params: {'p_distance_km': distanceKm}).timeout(kAcaoTimeout);
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
          await _sb.rpc('tvde_plan_price_cents', params: {'p_plan': plan}).timeout(kAcaoTimeout);
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
          await _sb.rpc('tvde_preview_coverage', params: {'p_client_id': uid}).timeout(kAcaoTimeout);
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
    // Bora Tokens a aplicar no desconto (max 50% da tarifa, igual ao delivery).
    int tokensUsed = 0,
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
        'p_tokens_to_apply': tokensUsed,
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
  /// [tokensUsed] quantidade de Bora Tokens a aplicar no desconto.
  ///
  /// Carteira Unica (2026-07-21): com [savedPmId] (so faz sentido em
  /// `method:'card'`) a Edge Fn cria o PI ja confirmado off_session — 1 toque.
  /// Nesse caso a confirmacao e feita aqui via confirmSavedCardPayment e o
  /// [confirmCard] nao chega a ser chamado. A biometria e do ecra, ANTES.
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
    int tokensUsed = 0,
    String? savedPmId,
    Future<void> Function(String clientSecret)? confirmCard,
    void Function(TvdeRide ride)? onRideCreated,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.functions.invoke(
        'tvde-payment',
        body: buildTvdeChargeBody(
          originLat: originLat,
          originLng: originLng,
          originLabel: originLabel,
          destLat: destLat,
          destLng: destLng,
          destLabel: destLabel,
          distanceKm: distanceKm,
          method: method,
          mbwayPhone: mbwayPhone,
          tokensUsed: tokensUsed,
          savedPmId: savedPmId,
        ),
      );
      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error'].toString());

      // A corrida JÁ existe neste ponto — a Edge Function cria-a antes de cobrar.
      // Entregá-la ao chamador ANTES de confirmar o cartão é o que permite ao
      // ecrã cancelá-la se o cliente recusar o pagamento: de outro modo a
      // exceção do `confirmCard` levaria a referência e ficava uma corrida órfã.
      TvdeRide? ride;
      final rideMap = data['ride'];
      if (rideMap is Map) {
        ride = TvdeRide.fromMap(Map<String, dynamic>.from(rideMap));
        _activeRide = ride;
        _subscribeRide(ride.id);
        notifyListeners();
        onRideCreated?.call(ride);
      }

      // Cartão → confirma o hold (autoriza a captura manual do valor final).
      // clientSecret vem null quando a EF responde 'not_charged' (valor <= 0,
      // ex.: perna de ida-e-volta já paga) — nesse caso não há nada a confirmar.
      final clientSecret = data['clientSecret'] as String?;
      if (method == 'card' && clientSecret != null && ride != null) {
        // Guardar ANTES do confirm: se o cliente desistir da sheet, o ecrã
        // ainda consegue oferecer "Pagar de novo" com o mesmo PaymentIntent.
        _pendingCardSecret = clientSecret;
        _pendingCardSecretRideId = ride.id;
      }
      if (method == 'card' && clientSecret != null) {
        if (savedPmId != null) {
          // Cartão guardado: PI já confirmado off_session no servidor; só
          // abrimos o sheet se o banco exigir 3DS.
          final ok = await PaymentService().confirmSavedCardPayment(
            clientSecret: clientSecret,
            requiresAction: (data['requiresAction'] as bool?) ?? false,
          );
          // 'cancel' no texto: o ecrã já mapeia isto para "Pagamento não
          // concluído. A corrida não foi pedida." e cancela a corrida órfã.
          if (!ok) throw Exception('saved_card_payment_cancelled');
        } else if (confirmCard != null) {
          await confirmCard(clientSecret);
        }
      }
      return ride;
    } catch (e) {
      debugPrint('TvdeStore.requestRidePaid error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // ══ RESERVA AGENDADA (2026-08-19) ═══════════════════════════════════════
  // O app é read-only sobre o relógio: quem trata rotação, lembretes, prender
  // o motorista e re-despacho é o cron `tvde-reservations-sweep`. Aqui só se
  // marca, se lê e se cancela.

  List<TvdeRide> _reservations = const [];

  /// Reservas do cliente com hora no futuro, da mais próxima para a mais longe.
  List<TvdeRide> get reservations => _reservations;

  /// Limites da marcação, lidos das definições (nunca cravados no app).
  /// Chaves: minAdvanceMinutes, maxAdvanceDays, freeCancelHours,
  /// paymentTimeoutMinutes.
  Future<Map<String, int>> loadReservationLimits() async {
    final results = await Future.wait([
      getSettingInt('tvde_reservation_min_advance_minutes', 30),
      getSettingInt('tvde_reservation_max_advance_days', 30),
      getSettingInt('tvde_reservation_free_cancel_hours', 2),
      getSettingInt('tvde_reservation_payment_timeout_minutes', 15),
    ]);
    return {
      'minAdvanceMinutes': results[0],
      'maxAdvanceDays': results[1],
      'freeCancelHours': results[2],
      'paymentTimeoutMinutes': results[3],
    };
  }

  /// As reservas estão ligadas? (kill switch `tvde_reservation_enabled`).
  Future<bool> reservationsEnabled() =>
      getSettingBool('tvde_reservation_enabled', false);

  /// Marca uma reserva a pagar EM DINHEIRO ao motorista.
  /// Chama a RPC direto — a reserva nasce logo `a_procurar`.
  Future<TvdeRide?> scheduleRideCash({
    required double originLat,
    required double originLng,
    String? originLabel,
    required double destLat,
    required double destLng,
    String? destLabel,
    required double distanceKm,
    required DateTime scheduledAt,
    String? note,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_schedule_ride', params: {
        'p_origin_lat': originLat,
        'p_origin_lng': originLng,
        'p_origin_label': originLabel,
        'p_dest_lat': destLat,
        'p_dest_lng': destLng,
        'p_dest_label': destLabel,
        'p_est_distance_km': distanceKm,
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        'p_payment_method': 'cash',
        'p_note': note,
      });
      final row = (res is List && res.isNotEmpty) ? res.first : res;
      if (row is! Map) return null;
      final ride = TvdeRide.fromMap(Map<String, dynamic>.from(row));
      await loadMyReservations();
      return ride;
    } catch (e) {
      debugPrint('TvdeStore.scheduleRideCash error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Marca uma reserva paga ONLINE (cartão ou MB Way).
  ///
  /// Mesmo caminho da corrida normal: a Edge Function `tvde-payment` cria a
  /// reserva E cobra o preço fechado por ela. A reserva nasce em
  /// `aguarda_pagamento` e SÓ procura motorista depois de
  /// [confirmReservationPayment] devolver `succeeded`.
  ///
  /// Devolve o par (reserva, paymentIntentId) — o id serve para o polling.
  Future<({TvdeRide? ride, String? paymentIntentId})> scheduleRidePaid({
    required double originLat,
    required double originLng,
    String? originLabel,
    required double destLat,
    required double destLng,
    String? destLabel,
    required double distanceKm,
    required DateTime scheduledAt,
    required String method, // 'card' | 'mbway'
    String? mbwayPhone,
    String? note,
    String? savedPmId,
    Future<void> Function(String clientSecret)? confirmCard,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.functions.invoke(
        'tvde-payment',
        body: buildTvdeReservationChargeBody(
          originLat: originLat,
          originLng: originLng,
          originLabel: originLabel,
          destLat: destLat,
          destLng: destLng,
          destLabel: destLabel,
          distanceKm: distanceKm,
          scheduledAt: scheduledAt,
          method: method,
          mbwayPhone: mbwayPhone,
          note: note,
          savedPmId: savedPmId,
        ),
      );
      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error'].toString());

      TvdeRide? ride;
      final rideMap = data['ride'];
      if (rideMap is Map) {
        ride = TvdeRide.fromMap(Map<String, dynamic>.from(rideMap));
      }
      final piId = data['paymentIntentId'] as String?;

      // Cartão → confirma exactamente como a corrida normal.
      final clientSecret = data['clientSecret'] as String?;
      if (method == 'card' && clientSecret != null) {
        if (savedPmId != null) {
          final ok = await PaymentService().confirmSavedCardPayment(
            clientSecret: clientSecret,
            requiresAction: (data['requiresAction'] as bool?) ?? false,
          );
          if (!ok) throw Exception('saved_card_payment_cancelled');
        } else if (confirmCard != null) {
          await confirmCard(clientSecret);
        }
      }
      await loadMyReservations();
      return (ride: ride, paymentIntentId: piId);
    } catch (e) {
      debugPrint('TvdeStore.scheduleRidePaid error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Pergunta ao servidor se o pagamento da reserva já entrou.
  /// Só quando devolve `true` é que a reserva passa a procurar motorista.
  /// Idempotente — pode ser chamada em polling sem risco.
  Future<bool> confirmReservationPayment(String paymentIntentId) async {
    try {
      final res = await _sb.functions.invoke(
        'tvde-payment',
        body: {
          'action': 'confirm_reservation_payment',
          'payment_intent_id': paymentIntentId,
        },
      );
      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      return data['succeeded'] == true;
    } catch (e) {
      debugPrint('TvdeStore.confirmReservationPayment error => $e');
      return false;
    }
  }

  /// Carrega as reservas do cliente com hora no futuro.
  Future<void> loadMyReservations() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('tvde_rides')
          .select()
          .eq('client_id', uid)
          .eq('status', 'agendada')
          .gte('scheduled_at', DateTime.now().toUtc().toIso8601String())
          .order('scheduled_at', ascending: true);
      _reservations = (rows as List)
          .map((r) => TvdeRide.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('TvdeStore.loadMyReservations error => $e');
    }
  }

  /// Cliente cancela a reserva.
  ///
  /// O reembolso (cartão/MB Way) é AUTOMÁTICO do lado do servidor — o app
  /// nunca chama a action `refund` para reservas. Aqui só se cancela e se
  /// recarrega a lista.
  Future<void> cancelReservation(String rideId, {String? reason}) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_cancel_reservation', params: {
        'p_ride_id': rideId,
        'p_reason': reason ?? 'cliente',
      }).timeout(kAcaoTimeout);
      await loadMyReservations();
    } catch (e) {
      debugPrint('TvdeStore.cancelReservation error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Grava a nota opcional do cliente para o MOTORISTA (paridade com a "Nota
  /// para o estafeta" do delivery). NÃO-FINANCEIRO: RPC dedicada que só escreve
  /// texto livre (`tvde_set_ride_note`, limite 200 chars server-side). Falha
  /// silenciosa — a nota nunca deve bloquear a criação da corrida.
  Future<void> setRideNote(String rideId, String note) async {
    try {
      await _sb.rpc('tvde_set_ride_note', params: {
        'p_ride_id': rideId,
        'p_note': note,
      }).timeout(kAcaoTimeout);
    } catch (e) {
      debugPrint('TvdeStore.setRideNote error => $e');
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

  /// Rebusca a corrida ativa por id, SEM filtro de status — ao contrário do
  /// [loadActiveRide], um estado terminal chega ao ecrã (que sai sozinho) em
  /// vez de ser filtrado. Serve o refetch ao voltar ao foreground: o realtime
  /// pode ter perdido eventos com a app em background (2026-08-16).
  Future<void> refreshActiveRide() async {
    final r = _activeRide;
    if (r == null) return;
    try {
      final row =
          await _sb.from('tvde_rides').select().eq('id', r.id).maybeSingle();
      if (row != null) {
        _activeRide = TvdeRide.fromMap(Map<String, dynamic>.from(row));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('TvdeStore.refreshActiveRide error => $e');
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
  ///
  /// BUG 6 (2026-08-13) — só serve corridas em DINHEIRO. Antes caía no default
  /// `paymentMethod: 'cash'`, por isso quem tinha pago por cartão/MB Way e não
  /// arranjou motorista recebia, ao tocar em "Tentar de novo", uma corrida em
  /// **dinheiro** sem o saber — o motorista apareceria a pedir o valor em mão.
  /// Repetir uma corrida paga online exige um pagamento novo, e isso é o ecrã
  /// de pedido que faz (folha de pagamento + `requestRidePaid`). Aqui devolve
  /// `null` e quem chama reencaminha — nunca inventa um método de pagamento.
  Future<TvdeRide?> retryRide() async {
    final r = _activeRide;
    if (r == null) return null;
    if (r.isPaidOnline) {
      debugPrint('TvdeStore.retryRide: corrida ${r.paymentMethod} — '
          'exige pagamento novo, reencaminhar para o ecrã de pedido');
      return null;
    }
    return requestRide(
      originLat: r.originLat,
      originLng: r.originLng,
      originLabel: r.originLabel,
      destLat: r.destLat,
      destLng: r.destLng,
      destLabel: r.destLabel,
      distanceKm: r.estDistanceKm,
      paymentMethod: r.paymentMethod,
    );
  }

  /// [skipRefund] para o cancelamento por pagamento falhado: aí **não há nada
  /// cobrado** para devolver, e pedir um refund de um PaymentIntent que nunca
  /// passou só gera erro e ruído na Stripe.
  Future<void> cancelRide(String rideId,
      {String? reason, bool skipRefund = false}) async {
    _setBusy(true);
    try {
      final res = await _sb.rpc('tvde_cancel_ride', params: {
        'p_ride_id': rideId,
        'p_actor': 'cliente',
        'p_reason': reason,
      }).timeout(kAcaoTimeout);
      // Corrida paga no app (card/mbway) → refund estilo client-cancel-order
      // (capado ao pago, menos a taxa) via Edge Function. Best-effort: se
      // falhar, o cancelamento já foi feito. Só corre com o switch ligado.
      final ride = _activeRide;
      if (!skipRefund && ride != null && ride.id == rideId && ride.isPaidOnline) {
        int feeCents = 0;
        try {
          feeCents = (_asMap(res)['cancel_fee_cents'] as num?)?.toInt() ?? 0;
        } catch (_) {/* sem taxa legível → refund total */}
        try {
          await _sb.functions.invoke('tvde-payment', body: {
            'action': 'refund',
            'ride_id': rideId,
            'cancel_fee_cents': feeCents,
          });
        } catch (e) {
          debugPrint('TvdeStore.cancelRide refund error => $e');
        }
      }
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
      final res = await _sb.rpc('get_setting', params: {'p_key': key}).timeout(kAcaoTimeout);
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
      final res = await _sb.rpc('get_setting', params: {'p_key': key}).timeout(kAcaoTimeout);
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
      }).timeout(kAcaoTimeout);
      return res is Map ? Map<String, dynamic>.from(res) : const {};
    } catch (e) {
      debugPrint('TvdeStore.addStop error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Parada numa corrida paga ONLINE: cobra os €2 **antes** de a adicionar.
  ///
  /// A parada NÃO entra aqui — só no [confirmStopPayment], quando o
  /// PaymentIntent passar. Sem pagamento não há parada (regra do Danilo).
  ///
  /// Devolve `{paymentIntentId, clientSecret (só cartão), status, amountCents}`.
  /// Erros conhecidos da EF (lançados como Exception com o código lá dentro):
  /// `stop_cash_flow`, `max_stops_reached`, `invalid_ride_state_for_stop`,
  /// `card_payments_not_enabled`.
  Future<Map<String, dynamic>> chargeStop(
    String rideId, {
    required String method, // 'card' | 'mbway'
    required double lat,
    required double lng,
    String? label,
    double segmentKm = 0,
    String? mbwayPhone,
  }) async {
    _setBusy(true);
    try {
      final res = await _sb.functions.invoke('tvde-payment', body: {
        'action': 'charge_stop',
        'ride_id': rideId,
        'method': method,
        'lat': lat,
        'lng': lng,
        if (label != null) 'label': label,
        'segment_km': segmentKm,
        if (mbwayPhone != null) 'phone': mbwayPhone,
      });
      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error'].toString());
      return data;
    } catch (e) {
      debugPrint('TvdeStore.chargeStop error => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Pergunta ao servidor se o pagamento da parada passou. Quando
  /// `succeeded:true` a parada **já foi adicionada** pelo backend (é ele que
  /// chama a `tvde_add_stop` com o PaymentIntent ligado).
  ///
  /// Se vier `refunded:true`, o pagamento passou mas a parada não entrou
  /// (máximo atingido, corrida terminou) e o dinheiro **já foi devolvido**.
  ///
  /// Devolve **null** quando nem se conseguiu falar com o servidor — o poll do
  /// MB Way continua, em vez de concluir "não pagou" por causa de rede.
  Future<Map<String, dynamic>?> confirmStopPayment(
      String paymentIntentId) async {
    try {
      final res = await _sb.functions.invoke('tvde-payment', body: {
        'action': 'confirm_stop_payment',
        'payment_intent_id': paymentIntentId,
      });
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.confirmStopPayment error => $e');
      return null;
    }
  }

  /// Cliente remove uma parada (só antes de o motorista lá chegar).
  Future<void> removeStop(String rideId, String stopId) async {
    _setBusy(true);
    try {
      await _sb.rpc('tvde_remove_stop',
          params: {'p_ride_id': rideId, 'p_stop_id': stopId}).timeout(kAcaoTimeout);
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
          params: {'p_ride_id': rideId, 'p_stop_id': stopId}).timeout(kAcaoTimeout);
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
      }).timeout(kAcaoTimeout);
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
    _pendingCardSecret = null;
    _pendingCardSecretRideId = null;
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
  /// (dinâmico, via `tvde_quote_roundtrip`). Reusa a Edge Fn tvde-plan-payment.
  /// [distanceKm] é obrigatório: a Edge Fn recomputa o preço a partir dela
  /// (nunca aceita um valor vindo do cliente) — ver PROPOSTA no index.ts.
  /// [tokensUsed] (PROPOSTA, não deployado) — nº de Bora Tokens escolhidos no
  /// toggle da folha de pagamento. A Edge Fn recomputa o desconto em cêntimos
  /// (nunca aceita um valor de desconto vindo do cliente); aqui só viaja a
  /// CONTAGEM.
  Future<Map<String, dynamic>?> createRoundtripPayment(double distanceKm,
      {int tokensUsed = 0}) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment', body: {
        'action': 'create_roundtrip',
        'distance_km': distanceKm,
        'tokens_used': tokensUsed,
      });
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
  /// [distanceKm] é obrigatório — ver nota em [createRoundtripPayment].
  /// [tokensUsed] (PROPOSTA, não deployado) — ver nota em [createRoundtripPayment].
  Future<Map<String, dynamic>?> createRoundtripPaymentMbway(
      String phone, double distanceKm,
      {int tokensUsed = 0}) async {
    try {
      final res = await _sb.functions.invoke('tvde-plan-payment', body: {
        'action': 'create_roundtrip_mbway',
        'phone': phone,
        'distance_km': distanceKm,
        'tokens_used': tokensUsed,
      });
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

  /// [Fase B] Vale-volta do pacote pago em **DINHEIRO** — sem Stripe nenhum.
  /// Cria o vale, liga-lhe a corrida de ida (mete `roundtrip_credit_id`) e usa o
  /// preço dinâmico (RPC `tvde_quote_roundtrip`). Idempotente por ida.
  ///
  /// O motorista da ida recolhe o valor em mão por conta da Bora; o acerto
  /// é do backend, no fecho semanal.
  ///
  /// Devolve a linha do vale, ou **null** se não deu. Null é grave: significa
  /// que a ida ficou por ligar e cobraria a tarifa ao cliente — quem chama TEM
  /// de a cancelar (ver `_solicitarRoundtripCash`).
  ///
  /// [tokensUsed] (PROPOSTA, não deployado) — nº de Bora Tokens escolhidos no
  /// toggle. A RPC recomputa o desconto em cêntimos e o teto de 50% do preço
  /// FINAL do pacote server-side (nunca aceita um valor de desconto vindo do
  /// cliente); aqui só viaja a CONTAGEM. Depende da migration PROPOSTA que
  /// acrescenta `p_tokens_to_apply` a `tvde_create_roundtrip_credit_cash`
  /// estar aplicada — sem ela, este parâmetro extra faz a RPC falhar com
  /// "function not found" (a assinatura antiga só tem 1 arg).
  Future<Map<String, dynamic>?> createRoundtripCreditCash(
      String outboundRideId,
      {int tokensUsed = 0}) async {
    try {
      final res = await _sb.rpc('tvde_create_roundtrip_credit_cash', params: {
        'p_outbound_ride_id': outboundRideId,
        'p_tokens_to_apply': tokensUsed,
      });
      // Mesma defesa do `activeRoundtripCredit`: um composto vazio
      // ({id:null,…}) não é vale (ver licao-rpc-composite-null-row).
      if (res is List && res.isNotEmpty) {
        final first = Map<String, dynamic>.from(res.first as Map);
        return first['id'] != null ? first : null;
      }
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        return m['id'] != null ? m : null;
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.createRoundtripCreditCash error => $e');
      return null;
    }
  }

  /// Cotação dinâmica do pacote ida-e-volta para a distância dada.
  Future<Map<String, dynamic>?> quoteRoundtrip(double distanceKm) async {
    try {
      final res = await _sb.rpc('tvde_quote_roundtrip',
          params: {'p_distance_km': distanceKm}).timeout(kAcaoTimeout);
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty) {
        return Map<String, dynamic>.from(res.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.quoteRoundtrip error => $e');
      return null;
    }
  }

  /// Lê o `paid_cents` de um vale de ida-e-volta pelo ID do crédito.
  Future<int> getRoundtripPaidCents(String creditId) async {
    try {
      final res = await _sb
          .from('tvde_roundtrip_credits')
          .select('paid_cents')
          .eq('id', creditId)
          .maybeSingle();
      if (res != null && res['paid_cents'] != null) {
        return (res['paid_cents'] as num).toInt();
      }
      return 800;
    } catch (e) {
      debugPrint('TvdeStore.getRoundtripPaidCents error => $e');
      return 800;
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

  /// Manda o servidor **reverificar o PaymentIntent na Stripe** e, se estiver
  /// `succeeded`, destravar a corrida (`aguarda_pagamento` → `solicitada`, que é
  /// o que faz o dispatch começar). É a única fonte de verdade sobre "está pago":
  /// o cliente nunca decide isso sozinho.
  ///
  /// Devolve o corpo da resposta (`{succeeded, payment_status, status}`) ou
  /// **null** quando nem sequer se conseguiu falar com o servidor (rede, ou a
  /// ação ainda não existir no backend). Distinguir os dois casos importa:
  /// "não pagou" cancela a corrida, "não consegui perguntar" **não** cancela.
  Future<Map<String, dynamic>?> confirmRidePayment(String rideId) async {
    try {
      final res = await _sb.functions.invoke('tvde-payment', body: {
        'action': 'confirm_ride_payment',
        'ride_id': rideId,
      });
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return null;
    } catch (e) {
      debugPrint('TvdeStore.confirmRidePayment error => $e');
      return null;
    }
  }

  /// Lê o `payment_status` de uma corrida (SELECT read-only). Serve o poll do
  /// MB Way: a Edge Function grava aqui o estado do PaymentIntent, e o cliente
  /// espera até `succeeded`. Devolve null se não conseguir ler (o poll continua).
  Future<String?> fetchRidePaymentStatus(String rideId) async {
    try {
      final res = await _sb
          .from('tvde_rides')
          .select('payment_status')
          .eq('id', rideId)
          .maybeSingle();
      return res?['payment_status'] as String?;
    } catch (e) {
      debugPrint('TvdeStore.fetchRidePaymentStatus error => $e');
      return null;
    }
  }

  /// Lê o vale-volta ativo do cliente ({} se não houver). Para "Chamar a volta".
  Future<Map<String, dynamic>?> activeRoundtripCredit() async {
    try {
      final res = await _sb.rpc('tvde_active_roundtrip_credit').timeout(kAcaoTimeout);
      // Defesa dupla contra "linha de NULLs" (ver licao-rpc-composite-null-row):
      // um vale só é real se tiver id. Sem isto, um composto vazio ({id:null,…})
      // fazia o banner "Tens uma volta garantida" aparecer sem vale nenhum.
      if (res is List && res.isNotEmpty) {
        final first = Map<String, dynamic>.from(res.first as Map);
        return first['id'] != null ? first : null;
      }
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        return m['id'] != null ? m : null;
      }
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
