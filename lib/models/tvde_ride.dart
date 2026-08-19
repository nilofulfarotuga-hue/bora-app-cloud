/// TVDE — Bora Motorista. Modelo de corrida de passageiros (read-only no app;
/// as transições são sempre via RPC no backend). Espelha `public.tvde_rides`.
class TvdeRide {
  TvdeRide({
    required this.id,
    required this.clientId,
    required this.status,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.estDistanceKm,
    required this.estFareCents,
    this.driverId,
    this.originLabel,
    this.destLabel,
    this.finalDistanceKm,
    this.finalFareCents,
    this.driverEarnCents,
    this.cancelReason,
    this.ratedByClient = false,
    this.ratedByDriver = false,
    this.currentOfferDriverId,
    this.offerExpiresAt,
    this.createdAt,
    this.isQueued = false,
    this.arrivedAt,
    this.usedSubscriptionRide = false,
    this.extraStopsCount = 0,
    this.extraStopsFeeCents = 0,
    this.extraStopsDriverCents = 0,
    this.paymentMethod = 'cash',
    this.paymentStatus,
    this.roundtripCreditId,
    this.isReturnLeg = false,
    this.scheduledAt,
    this.reservationStatus,
    this.reservationDriverId,
    this.reservationOfferDriverId,
    this.reservationOfferExpiresAt,
    this.reservationDriverReadyAt,
  });

  final String id;
  final String clientId;
  final String status;
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final double estDistanceKm;
  final int estFareCents;
  final String? driverId;
  final String? originLabel;
  final String? destLabel;
  final double? finalDistanceKm;
  final int? finalFareCents;

  /// Ganho do motorista (cêntimos), preenchido no finish.
  final int? driverEarnCents;
  final String? cancelReason;
  final bool ratedByClient;

  /// O motorista já avaliou o passageiro nesta corrida.
  final bool ratedByDriver;

  /// Motorista a quem a oferta está atribuída agora (dispatch Fase 2).
  final String? currentOfferDriverId;

  /// Quando a oferta atual expira (countdown do lado do motorista).
  final DateTime? offerExpiresAt;
  final DateTime? createdAt;

  /// Back-to-back: corrida aceite EM FILA enquanto o motorista termina a
  /// viagem atual (status 'motorista_atribuido' + is_queued=true). Ativa-se
  /// no backend ao finalizar/cancelar a viagem atual.
  final bool isQueued;

  /// Quando o motorista marcou "cheguei" — alimenta o temporizador de espera
  /// no pickup (no-show só habilita após a janela tvde_noshow_wait_minutes).
  final DateTime? arrivedAt;

  /// [Item B] A corrida está coberta pelo plano (cliente paga €0). Definido no
  /// request (preview) e reconfirmado no finish (consume).
  final bool usedSubscriptionRide;

  /// [CAMPO-02 · Feature 1] Paradas adicionais no meio da corrida. A taxa
  /// (2 EUR/parada) é cobrada SEMPRE, mesmo em corrida coberta pelo plano.
  final int extraStopsCount;
  final int extraStopsFeeCents;
  final int extraStopsDriverCents;

  /// Método de pagamento: 'cash' (default), 'card' ou 'mbway'. Card/mbway só
  /// existem com o kill switch `tvde_card_payments_enabled` ligado.
  final String paymentMethod;

  /// Estado do PaymentIntent na Stripe, espelhado em `tvde_rides.payment_status`
  /// ('succeeded' / 'processing' / 'requires_action' / 'not_charged' / …).
  /// Null nas corridas em dinheiro (nunca há PaymentIntent).
  final String? paymentStatus;

  /// [Fase B] Vale do pacote ida-e-volta (€8) a que esta corrida está ligada.
  /// **Não-nulo = perna PREPAGA**: o `tvde_finish_ride` não cobra a tarifa ao
  /// cliente (só paradas, se houver). É esta ligação — e só ela — que separa
  /// "€8 pelas duas pernas" de "€8 + €5 = €13".
  final String? roundtripCreditId;

  /// [Fase B] Esta corrida é a VOLTA do pacote (chamada com o vale), não a ida.
  final bool isReturnLeg;

  // ── [Reserva agendada 2026-08-19] ───────────────────────────────────────
  /// Hora marcada pelo cliente. Não-nulo => é uma RESERVA (`status='agendada'`).
  final DateTime? scheduledAt;

  /// `aguarda_pagamento` | `a_procurar` | `atribuida` | `ativada`
  /// | `sem_motorista` | `cancelada`. Espelha o servidor — o app nunca calcula.
  final String? reservationStatus;

  /// Motorista DONO da reserva (já aceitou). Alimenta a Agenda do motorista.
  final String? reservationDriverId;

  /// Motorista a quem a oferta antecipada está a ser feita AGORA.
  final String? reservationOfferDriverId;

  /// Prazo para responder à oferta antecipada — vem pronto do servidor,
  /// o app só conta para trás (nunca decide o TTL).
  final DateTime? reservationOfferExpiresAt;

  /// Momento em que o motorista carregou "A caminho" no lembrete dos 10 min.
  /// Nulo perto da hora = o servidor vai passar a reserva a outro.
  final DateTime? reservationDriverReadyAt;

  /// É uma reserva (corrida marcada para depois), não um pedido imediato.
  bool get isReservation => status == 'agendada' || scheduledAt != null;

  /// Reserva criada mas ainda por pagar (cartão/MB Way). O servidor cancela
  /// sozinha ao fim de `tvde_reservation_payment_timeout_minutes` (15 min).
  bool get reservationAwaitingPayment =>
      reservationStatus == 'aguarda_pagamento';

  factory TvdeRide.fromMap(Map<String, dynamic> m) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return TvdeRide(
      id: m['id'] as String,
      clientId: m['client_id'] as String,
      status: m['status'] as String? ?? 'solicitada',
      originLat: d(m['origin_lat']),
      originLng: d(m['origin_lng']),
      destLat: d(m['dest_lat']),
      destLng: d(m['dest_lng']),
      estDistanceKm: d(m['est_distance_km']),
      estFareCents: (m['est_fare_cents'] as num?)?.toInt() ?? 0,
      driverId: m['driver_id'] as String?,
      originLabel: m['origin_label'] as String?,
      destLabel: m['dest_label'] as String?,
      finalDistanceKm: (m['final_distance_km'] as num?)?.toDouble(),
      finalFareCents: (m['final_fare_cents'] as num?)?.toInt(),
      driverEarnCents: (m['driver_earn_cents'] as num?)?.toInt(),
      cancelReason: m['cancel_reason'] as String?,
      ratedByClient: m['rated_by_client'] as bool? ?? false,
      ratedByDriver: m['rated_by_driver'] as bool? ?? false,
      currentOfferDriverId: m['current_offer_driver_id'] as String?,
      offerExpiresAt: m['offer_expires_at'] == null
          ? null
          : DateTime.tryParse(m['offer_expires_at'].toString()),
      createdAt: m['created_at'] == null
          ? null
          : DateTime.tryParse(m['created_at'].toString()),
      isQueued: m['is_queued'] as bool? ?? false,
      arrivedAt: m['arrived_at'] == null
          ? null
          : DateTime.tryParse(m['arrived_at'].toString()),
      usedSubscriptionRide: m['used_subscription_ride'] as bool? ?? false,
      extraStopsCount: (m['extra_stops_count'] as num?)?.toInt() ?? 0,
      extraStopsFeeCents: (m['extra_stops_fee_cents'] as num?)?.toInt() ?? 0,
      extraStopsDriverCents:
          (m['extra_stops_driver_cents'] as num?)?.toInt() ?? 0,
      paymentMethod: m['payment_method'] as String? ?? 'cash',
      paymentStatus: m['payment_status'] as String?,
      roundtripCreditId: m['roundtrip_credit_id'] as String?,
      isReturnLeg: m['is_return_leg'] as bool? ?? false,
      scheduledAt: m['scheduled_at'] == null
          ? null
          : DateTime.tryParse(m['scheduled_at'].toString()),
      reservationStatus: m['reservation_status'] as String?,
      reservationDriverId: m['reservation_driver_id'] as String?,
      reservationOfferDriverId: m['reservation_offer_driver_id'] as String?,
      reservationOfferExpiresAt: m['reservation_offer_expires_at'] == null
          ? null
          : DateTime.tryParse(m['reservation_offer_expires_at'].toString()),
      reservationDriverReadyAt: m['reservation_driver_ready_at'] == null
          ? null
          : DateTime.tryParse(m['reservation_driver_ready_at'].toString()),
    );
  }

  // ── Helpers de estado ───────────────────────────────────────────────────
  /// Estados do PaymentIntent em que o dinheiro **ainda não entrou**.
  /// `requires_payment_method` = PaymentIntent criado mas o cliente ainda não
  ///   pagou (ou abriu a PaymentSheet e voltou sem pagar — corrida d947b446,
  ///   2026-08-16: sem este valor aqui o ecrã dizia "à procura de motorista"
  ///   numa corrida que nunca foi cobrada).
  /// `requires_confirmation` = cartão anexado, falta o confirm.
  /// `requires_action` = MB Way empurrado / 3DS, à espera do toque no banco.
  /// `processing`      = confirmado no banco, a liquidar.
  static const _pendingPaymentStatuses = {
    'requires_payment_method',
    'requires_confirmation',
    'requires_action',
    'processing',
  };

  /// Pagamento online por fechar. Enquanto isto for `true` NÃO há dispatch:
  /// o motorista só é chamado quando `payment_status` chega a 'succeeded'
  /// (trigger `tr_tvde_dispatch_on_paid`).
  ///
  /// `payment_status` NULL numa corrida online ainda `solicitada` também é
  /// pendente: sem 'succeeded' o trigger nunca despachou (ex.: ida do pacote
  /// ida-e-volta antes de o `activate_roundtrip` ligar o vale). Fora de
  /// `solicitada` um NULL legado não conta — a corrida já foi despachada.
  bool get isPaymentPending =>
      isPaidOnline &&
      (paymentStatus == null
          ? status == 'solicitada'
          : _pendingPaymentStatuses.contains(paymentStatus));

  /// MB Way empurrado, à espera do toque do cliente na app do banco — o
  /// dinheiro **ainda não saiu**. Desistir aqui é grátis e não há refund a
  /// fazer.
  bool get isPaymentAwaitingClient =>
      isPaidOnline && paymentStatus == 'requires_action';

  /// Confirmado no banco, a liquidar — o dinheiro **já vai a caminho**.
  /// Cancelar aqui TEM de passar pelo refund; tratar como "não cobrado"
  /// deixaria o pagamento órfão na Stripe.
  bool get isPaymentSettling => isPaidOnline && paymentStatus == 'processing';

  /// Corrida criada mas **estacionada**: nasceu paga-online e ainda NÃO está a
  /// chamar motorista nenhum. Nunca mostrar "à procura de motorista" aqui.
  ///
  /// 2026-08-13 — o `status == 'aguarda_pagamento'` era letra morta: a RPC
  /// `tvde_request_ride` insere SEMPRE `status = 'solicitada'`, mesmo em
  /// cartão/MB Way (é o que o `tr_tvde_dispatch_on_paid` exige para despachar).
  /// Resultado: o ecrã dizia "à procura de motorista" antes sequer de o cliente
  /// tocar no MB Way. A verdade de "já pagou?" está no `payment_status`, não no
  /// `status` — é de lá que este getter passa a ler.
  bool get isAwaitingPayment =>
      status == 'aguarda_pagamento' || isPaymentPending;

  /// À procura de motorista a sério — pedido em pé E dinheiro já dentro.
  bool get isSearching => status == 'solicitada' && !isPaymentPending;
  /// Pago online (cartão/MB Way) — o motorista NÃO cobra nada ao passageiro.
  bool get isPaidOnline => paymentMethod == 'card' || paymentMethod == 'mbway';

  /// [Fase B] Perna (ida OU volta) do pacote €8 — está ligada a um vale, logo é
  /// PREPAGA. O motorista ganha a sua parte, mas o valor do pacote não é dele.
  bool get isRoundtripLeg => roundtripCreditId != null;
  bool get isNoDriver => status == 'sem_motorista';
  bool get isAssigned => status == 'motorista_atribuido' ||
      status == 'motorista_a_caminho' ||
      status == 'motorista_chegou';
  bool get isOnTheWay => status == 'motorista_a_caminho';
  bool get hasArrived => status == 'motorista_chegou';
  bool get isInProgress => status == 'em_andamento';
  bool get isFinished => status == 'finalizada';
  bool get isCancelled => status == 'cancelada_cliente' ||
      status == 'cancelada_motorista' ||
      status == 'no_show';
  /// Terminal para efeitos de RESUME: uma corrida sem motorista NÃO deve
  /// reabrir o tracking antigo (P0-3 2026-07-02). Alinha com o guard do backend
  /// `tvde_request_ride` (sem_motorista não conta como "em curso").
  bool get isTerminal => isFinished || isCancelled || isNoDriver;

  /// Estado "ativo/retomável": corrida que ainda decorre e deve reabrir o
  /// tracking ao voltar à app. Espelha EXATAMENTE o conjunto "em curso" do
  /// backend — `sem_motorista` fica de fora (é terminal para o resume).
  /// Inclui `aguarda_pagamento` de propósito: se o cliente sair da app a meio do
  /// MB Way, tem de reencontrar o ecrã da corrida — senão fica sem saber o que
  /// aconteceu ao dinheiro. Quem a limpa é o cron (cancel_reason
  /// 'payment_timeout'), não o resume.
  bool get isLive =>
      isAwaitingPayment || isSearching || isAssigned || isInProgress;

  /// Valor a apresentar ao cliente (cêntimos): final se já houver, senão est.
  int get displayFareCents => finalFareCents ?? estFareCents;

  /// Total ao vivo (cêntimos) = final se existir, senão base estimada + paradas.
  /// As paradas somam-se sempre (2 EUR cada, mesmo em corrida coberta pelo plano).
  int get liveTotalCents => finalFareCents ?? (estFareCents + extraStopsFeeCents);

  bool get hasExtraStops => extraStopsCount > 0;

  String get statusLabel {
    switch (status) {
      case 'aguarda_pagamento':
        return 'A aguardar pagamento…';
      case 'solicitada':
        return 'À procura de motorista…';
      case 'sem_motorista':
        return 'Sem motoristas disponíveis';
      case 'motorista_atribuido':
        return isQueued
            ? 'O teu motorista está a terminar uma viagem próxima'
            : 'Motorista atribuído';
      case 'motorista_a_caminho':
        return 'Motorista a caminho';
      case 'motorista_chegou':
        return 'O motorista chegou';
      case 'em_andamento':
        return 'Viagem em curso';
      case 'finalizada':
        return 'Viagem concluída';
      case 'cancelada_cliente':
        return 'Cancelada por si';
      case 'cancelada_motorista':
        return 'Cancelada pelo motorista';
      case 'no_show':
        return 'Não compareceu';
      default:
        return status;
    }
  }
}

/// [CAMPO-02 · Feature 1] Uma parada adicional de uma corrida TVDE.
/// Espelha `public.tvde_ride_stops`. Read-only no app.
class TvdeRideStop {
  TvdeRideStop({
    required this.id,
    required this.seq,
    this.label,
    required this.lat,
    required this.lng,
    required this.feeCents,
    required this.driverCents,
    this.reachedAt,
  });

  final String id;
  final int seq;
  final String? label;
  final double lat;
  final double lng;
  final int feeCents;
  final int driverCents;

  /// Quando o motorista marcou chegada à parada (arranca o timer informativo).
  final DateTime? reachedAt;

  bool get reached => reachedAt != null;

  factory TvdeRideStop.fromMap(Map<String, dynamic> m) => TvdeRideStop(
        id: m['id'] as String,
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        label: m['label'] as String?,
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        feeCents: (m['fee_cents'] as num?)?.toInt() ?? 0,
        driverCents: (m['driver_cents'] as num?)?.toInt() ?? 0,
        reachedAt: m['reached_at'] == null
            ? null
            : DateTime.tryParse(m['reached_at'].toString()),
      );
}
