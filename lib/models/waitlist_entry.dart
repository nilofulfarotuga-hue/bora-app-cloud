/// Reservas PRO F3.C — entry da fila de espera (`reservation_waitlist`).
///
/// Status: waiting / cancelled / expired / notified / seated.
/// Cliente vê (via RLS) apenas as suas entries. Trigger DB envia push
/// ao parceiro quando entry é criada.
class WaitlistEntry {
  WaitlistEntry({
    required this.id,
    required this.restaurantId,
    this.restaurantName,
    this.restaurantPhotoUrl,
    required this.people,
    required this.targetDate,
    this.targetTimeStart,
    this.targetTimeEnd,
    required this.status,
    this.position,
    this.notifiedAt,
    this.seatedAt,
    this.expiredAt,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String? restaurantName;
  final String? restaurantPhotoUrl;
  final int people;
  final DateTime targetDate;
  final String? targetTimeStart; // 'HH:mm:ss' ou null.
  final String? targetTimeEnd;
  final String status;
  final int? position;
  final DateTime? notifiedAt;
  final DateTime? seatedAt;
  final DateTime? expiredAt;
  final String? notes;
  final DateTime createdAt;

  factory WaitlistEntry.fromMap(Map<String, dynamic> map) {
    final restaurant = map['restaurants'];
    String? restaurantName;
    String? restaurantPhotoUrl;
    if (restaurant is Map) {
      restaurantName = restaurant['name'] as String?;
      restaurantPhotoUrl =
          (restaurant['photo_url'] as String?) ?? (restaurant['image_url'] as String?);
    }

    DateTime? parseTs(Object? v) =>
        v is String ? DateTime.parse(v) : null;

    return WaitlistEntry(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      restaurantName: restaurantName,
      restaurantPhotoUrl: restaurantPhotoUrl,
      people: (map['people'] as int?) ?? 2,
      targetDate: DateTime.parse(map['target_date'] as String),
      targetTimeStart: map['target_time_start'] as String?,
      targetTimeEnd: map['target_time_end'] as String?,
      status: (map['status'] as String?) ?? 'waiting',
      position: map['position'] as int?,
      notifiedAt: parseTs(map['notified_at']),
      seatedAt: parseTs(map['seated_at']),
      expiredAt: parseTs(map['expired_at']),
      notes: map['notes'] as String?,
      createdAt: parseTs(map['created_at']) ?? DateTime.now(),
    );
  }

  bool get isActive => status == 'waiting';
  bool get wasNotified => status == 'notified';
  bool get isFinalized =>
      status == 'cancelled' || status == 'expired' || status == 'seated';
}
