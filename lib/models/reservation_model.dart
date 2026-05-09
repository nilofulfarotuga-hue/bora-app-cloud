/// Table reservation (BR §14 + Reservas PRO §50/§51).
///
/// Status canónicos do `reservations` (DB free TEXT, sem CHECK constraint).
/// Aceita os valores actuais usados pelo F2 backend + valores legacy
/// originais (BR §14) para backward-compat com partner/admin screens.
class ReservationStatus {
  // F2 canonical (Reservas PRO §51).
  static const String pending = 'pending';
  static const String pendingPayment = 'pending_payment';
  static const String approved = 'approved';
  static const String confirmed = 'confirmed';
  static const String arrived = 'arrived';
  static const String rejectedRefunded = 'rejected_refunded';
  static const String cancelledRefunded = 'cancelled_refunded';
  static const String cancelledNoRefund = 'cancelled_no_refund';
  static const String noShow = 'no_show';

  // Legacy (BR §14 original) — DB aceita ambos os conjuntos. Mantido
  // para que partner/admin screens existentes continuem a funcionar.
  static const String accepted = 'accepted';
  static const String suggestedOtherTime = 'suggested_other_time';
  static const String customerArrived = 'customer_arrived';
  static const String rejected = 'rejected';
  static const String cancelled = 'cancelled';
}

class ReservationModel {
  ReservationModel({
    required this.id,
    required this.restaurantId,
    required this.clientUserId,
    required this.clientName,
    required this.clientPhone,
    required this.people,
    required this.reservedFor,
    required this.status,
    this.notes,
    this.prepaymentCents = 0,
    this.prepaymentPi,
    this.decidedAt,
    this.arrivedAt,
    this.cancelledAt,
    this.cancelReason,
    DateTime? createdAt,
    // F1 Reservas PRO — 10 colunas novas.
    this.floorPlanId,
    this.eventType = 'normal',
    this.specialRequests,
    this.occasion,
    this.isWalkIn = false,
    this.seatedAt,
    this.finishedAt,
    this.reminder24hSentAt,
    this.reminder2hSentAt,
    this.confirmationSentAt,
    // JOIN restaurants (extras opcionais — populados quando fetch faz JOIN).
    this.restaurantName,
    this.restaurantPhotoUrl,
  }) : createdAt = createdAt ?? DateTime.now();

  // 16 campos base.
  final String id;
  final String restaurantId;
  final String? clientUserId;
  final String clientName;
  final String clientPhone;
  final int people;
  final DateTime reservedFor;
  final String status;
  final String? notes;
  final int prepaymentCents;
  final String? prepaymentPi;
  final DateTime? decidedAt;
  final DateTime? arrivedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;

  // 10 colunas novas (Reservas PRO F1).
  final String? floorPlanId;
  final String eventType;
  final String? specialRequests;
  final String? occasion;
  final bool isWalkIn;
  final DateTime? seatedAt;
  final DateTime? finishedAt;
  final DateTime? reminder24hSentAt;
  final DateTime? reminder2hSentAt;
  final DateTime? confirmationSentAt;

  // JOIN restaurants extras (não no schema reservations).
  final String? restaurantName;
  final String? restaurantPhotoUrl;

  factory ReservationModel.fromSupabase(Map<String, dynamic> row) {
    // Extrai JOIN restaurants se presente (Supabase select('*, restaurants(...)')).
    String? restaurantName;
    String? restaurantPhotoUrl;
    final r = row['restaurants'];
    if (r is Map) {
      restaurantName = r['name'] as String?;
      restaurantPhotoUrl =
          (r['photo_url'] as String?) ?? (r['image_url'] as String?);
    }

    DateTime? parseTs(Object? v) =>
        v is String ? DateTime.parse(v) : null;

    return ReservationModel(
      id: row['id'] as String,
      restaurantId: row['restaurant_id'] as String,
      clientUserId: row['client_user_id'] as String?,
      clientName: (row['client_name'] as String?) ?? '',
      clientPhone: (row['client_phone'] as String?) ?? '',
      people: (row['people'] as int?) ?? 2,
      reservedFor: DateTime.parse(row['reserved_for'] as String),
      status: (row['status'] as String?) ?? ReservationStatus.pending,
      notes: row['notes'] as String?,
      prepaymentCents: (row['prepayment_cents'] as int?) ?? 0,
      prepaymentPi: row['prepayment_pi'] as String?,
      decidedAt: parseTs(row['decided_at']),
      arrivedAt: parseTs(row['arrived_at']),
      cancelledAt: parseTs(row['cancelled_at']),
      cancelReason: row['cancel_reason'] as String?,
      createdAt: parseTs(row['created_at']) ?? DateTime.now(),
      floorPlanId: row['floor_plan_id'] as String?,
      eventType: (row['event_type'] as String?) ?? 'normal',
      specialRequests: row['special_requests'] as String?,
      occasion: row['occasion'] as String?,
      isWalkIn: (row['is_walk_in'] as bool?) ?? false,
      seatedAt: parseTs(row['seated_at']),
      finishedAt: parseTs(row['finished_at']),
      reminder24hSentAt: parseTs(row['reminder_24h_sent_at']),
      reminder2hSentAt: parseTs(row['reminder_2h_sent_at']),
      confirmationSentAt: parseTs(row['confirmation_sent_at']),
      restaurantName: restaurantName,
      restaurantPhotoUrl: restaurantPhotoUrl,
    );
  }

  Map<String, dynamic> toInsert() => {
        'restaurant_id': restaurantId,
        if (clientUserId != null) 'client_user_id': clientUserId,
        'client_name': clientName,
        'client_phone': clientPhone,
        'people': people,
        'reserved_for': reservedFor.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
        'status': status,
        'prepayment_cents': prepaymentCents,
      };

  // ─── Helpers de estado (consumidos por screens cliente) ───────────────────

  bool get isPending =>
      status == ReservationStatus.pending ||
      status == ReservationStatus.pendingPayment;

  bool get isApproved =>
      status == ReservationStatus.approved ||
      status == ReservationStatus.confirmed ||
      status == ReservationStatus.accepted; // legacy

  bool get isArrived =>
      status == ReservationStatus.arrived ||
      status == ReservationStatus.customerArrived || // legacy
      arrivedAt != null;

  bool get isCancelled =>
      status == ReservationStatus.rejectedRefunded ||
      status == ReservationStatus.cancelledRefunded ||
      status == ReservationStatus.cancelledNoRefund ||
      status == ReservationStatus.cancelled || // legacy
      status == ReservationStatus.rejected; // legacy

  bool get isNoShow => status == ReservationStatus.noShow;

  bool get isFinished => finishedAt != null;

  bool get isUpcoming =>
      !isCancelled &&
      !isNoShow &&
      !isFinished &&
      (isPending || isApproved || isArrived) &&
      reservedFor.isAfter(DateTime.now());

  bool get isPast =>
      !isCancelled &&
      (isFinished || isNoShow || reservedFor.isBefore(DateTime.now()));
}
