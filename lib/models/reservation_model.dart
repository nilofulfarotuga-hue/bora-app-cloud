/// Table reservation (BR §14).
enum ReservationStatus {
  pending,
  accepted,
  suggestedOtherTime,
  rejected,
  customerArrived,
  cancelled,
}

extension ReservationStatusX on ReservationStatus {
  String get dbName {
    switch (this) {
      case ReservationStatus.pending:
        return 'pending';
      case ReservationStatus.accepted:
        return 'accepted';
      case ReservationStatus.suggestedOtherTime:
        return 'suggested_other_time';
      case ReservationStatus.rejected:
        return 'rejected';
      case ReservationStatus.customerArrived:
        return 'customer_arrived';
      case ReservationStatus.cancelled:
        return 'cancelled';
    }
  }

  static ReservationStatus fromDb(String raw) {
    switch (raw) {
      case 'accepted':
        return ReservationStatus.accepted;
      case 'suggested_other_time':
        return ReservationStatus.suggestedOtherTime;
      case 'rejected':
        return ReservationStatus.rejected;
      case 'customer_arrived':
        return ReservationStatus.customerArrived;
      case 'cancelled':
        return ReservationStatus.cancelled;
      case 'pending':
      default:
        return ReservationStatus.pending;
    }
  }
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
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String restaurantId;
  final String clientUserId;
  final String clientName;
  final String clientPhone;
  final int people;
  final DateTime reservedFor;
  final ReservationStatus status;
  final String? notes;
  final int prepaymentCents;
  final String? prepaymentPi;
  final DateTime? decidedAt;
  final DateTime? arrivedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;

  factory ReservationModel.fromSupabase(Map<String, dynamic> row) {
    return ReservationModel(
      id: row['id'] as String,
      restaurantId: row['restaurant_id'] as String,
      clientUserId: row['client_user_id'] as String,
      clientName: (row['client_name'] as String?) ?? '',
      clientPhone: (row['client_phone'] as String?) ?? '',
      people: (row['people'] as int?) ?? 2,
      reservedFor: DateTime.parse(row['reserved_for'] as String),
      status: ReservationStatusX.fromDb((row['status'] as String?) ?? 'pending'),
      notes: row['notes'] as String?,
      prepaymentCents: (row['prepayment_cents'] as int?) ?? 0,
      prepaymentPi: row['prepayment_pi'] as String?,
      decidedAt: row['decided_at'] != null
          ? DateTime.parse(row['decided_at'] as String)
          : null,
      arrivedAt: row['arrived_at'] != null
          ? DateTime.parse(row['arrived_at'] as String)
          : null,
      cancelledAt: row['cancelled_at'] != null
          ? DateTime.parse(row['cancelled_at'] as String)
          : null,
      cancelReason: row['cancel_reason'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toInsert() => {
        'restaurant_id': restaurantId,
        'client_user_id': clientUserId,
        'client_name': clientName,
        'client_phone': clientPhone,
        'people': people,
        'reserved_for': reservedFor.toUtc().toIso8601String(),
        if (notes != null) 'notes': notes,
        'status': status.dbName,
        'prepayment_cents': prepaymentCents,
      };
}
