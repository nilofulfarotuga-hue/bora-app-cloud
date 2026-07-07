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
    );
  }

  // ── Helpers de estado ───────────────────────────────────────────────────
  bool get isSearching => status == 'solicitada';
  /// Pago online (cartão/MB Way) — o motorista NÃO cobra nada ao passageiro.
  bool get isPaidOnline => paymentMethod == 'card' || paymentMethod == 'mbway';
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
  bool get isLive => isSearching || isAssigned || isInProgress;

  /// Valor a apresentar ao cliente (cêntimos): final se já houver, senão est.
  int get displayFareCents => finalFareCents ?? estFareCents;

  /// Total ao vivo (cêntimos) = final se existir, senão base estimada + paradas.
  /// As paradas somam-se sempre (2 EUR cada, mesmo em corrida coberta pelo plano).
  int get liveTotalCents => finalFareCents ?? (estFareCents + extraStopsFeeCents);

  bool get hasExtraStops => extraStopsCount > 0;

  String get statusLabel {
    switch (status) {
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
