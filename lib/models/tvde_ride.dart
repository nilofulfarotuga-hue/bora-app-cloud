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
    );
  }

  // ── Helpers de estado ───────────────────────────────────────────────────
  bool get isSearching => status == 'solicitada';
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

  String get statusLabel {
    switch (status) {
      case 'solicitada':
        return 'À procura de motorista…';
      case 'sem_motorista':
        return 'Sem motoristas disponíveis';
      case 'motorista_atribuido':
        return 'Motorista atribuído';
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
