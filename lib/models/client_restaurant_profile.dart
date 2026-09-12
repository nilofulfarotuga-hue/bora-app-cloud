/// Reservas PRO F4 — perfil cliente↔restaurante
/// (`client_restaurant_profiles`).
///
/// Trigger DB actualiza `total_visits`/`total_no_shows`/`last_visit_at`
/// quando reserva é finalizada/no-show. Partner gere VIP, bloqueio
/// e notas privadas.
class ClientRestaurantProfile {
  ClientRestaurantProfile({
    required this.id,
    required this.clientUserId,
    this.clientName,
    this.clientPhone,
    required this.restaurantId,
    required this.totalVisits,
    required this.totalNoShows,
    required this.totalLateCancels,
    this.lastVisitAt,
    required this.isVip,
    required this.isBlocked,
    this.blockedReason,
    this.blockedAt,
    required this.preferences,
    this.partnerNotes,
  });

  final String id;
  final String clientUserId;
  final String? clientName;
  final String? clientPhone;
  final String restaurantId;
  final int totalVisits;
  final int totalNoShows;
  final int totalLateCancels;
  final DateTime? lastVisitAt;
  final bool isVip;
  final bool isBlocked;
  final String? blockedReason;
  final DateTime? blockedAt;
  final Map<String, dynamic> preferences;
  final String? partnerNotes;

  factory ClientRestaurantProfile.fromJson(Map<String, dynamic> map) {
    final user = map['users'];
    String? clientName;
    String? clientPhone;
    if (user is Map) {
      clientName = user['name'] as String?;
      clientPhone = user['phone'] as String?;
    }
    DateTime? parseTs(Object? v) =>
        v is String ? DateTime.parse(v) : null;
    return ClientRestaurantProfile(
      id: map['id'] as String,
      clientUserId: map['client_user_id'] as String,
      clientName: clientName,
      clientPhone: clientPhone,
      restaurantId: map['restaurant_id'] as String,
      totalVisits: (map['total_visits'] as int?) ?? 0,
      totalNoShows: (map['total_no_shows'] as int?) ?? 0,
      totalLateCancels: (map['total_late_cancels'] as int?) ?? 0,
      lastVisitAt: parseTs(map['last_visit_at']),
      isVip: (map['is_vip'] as bool?) ?? false,
      isBlocked: (map['is_blocked'] as bool?) ?? false,
      blockedReason: map['blocked_reason'] as String?,
      blockedAt: parseTs(map['blocked_at']),
      preferences:
          Map<String, dynamic>.from((map['preferences'] as Map?) ?? const {}),
      partnerNotes: map['partner_notes'] as String?,
    );
  }
}
