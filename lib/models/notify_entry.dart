/// Reservas PRO F3.C — entry da lista "avisar se vagar"
/// (`reservation_notify_list`, modelo OpenTable Notify).
///
/// Status: active / notified / converted / expired / cancelled.
/// CRON `5_expire_lists` gere expiry automático após `expires_at`.
class NotifyEntry {
  NotifyEntry({
    required this.id,
    required this.restaurantId,
    this.restaurantName,
    this.restaurantPhotoUrl,
    required this.targetDate,
    required this.targetTime,
    required this.flexibilityMinutes,
    required this.people,
    required this.status,
    this.notifiedAt,
    this.convertedToReservationId,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String? restaurantName;
  final String? restaurantPhotoUrl;
  final DateTime targetDate;
  final String targetTime; // 'HH:mm:ss'.
  final int flexibilityMinutes;
  final int people;
  final String status;
  final DateTime? notifiedAt;
  final String? convertedToReservationId;
  final DateTime expiresAt;
  final DateTime createdAt;

  factory NotifyEntry.fromMap(Map<String, dynamic> map) {
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

    return NotifyEntry(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      restaurantName: restaurantName,
      restaurantPhotoUrl: restaurantPhotoUrl,
      targetDate: DateTime.parse(map['target_date'] as String),
      targetTime: map['target_time'] as String,
      flexibilityMinutes: (map['flexibility_minutes'] as int?) ?? 30,
      people: (map['people'] as int?) ?? 2,
      status: (map['status'] as String?) ?? 'active',
      notifiedAt: parseTs(map['notified_at']),
      convertedToReservationId:
          map['converted_to_reservation_id'] as String?,
      expiresAt: parseTs(map['expires_at']) ?? DateTime.now(),
      createdAt: parseTs(map['created_at']) ?? DateTime.now(),
    );
  }

  bool get isActive => status == 'active';
  bool get wasNotified => status == 'notified';
  bool get wasConverted => status == 'converted';
  bool get isFinalized => status == 'cancelled' || status == 'expired';
}
