/// Reservas PRO F4 — plano de sala (`restaurant_floor_plans`).
///
/// Cada restaurante pode ter múltiplos planos (ex: piso 0 / piso 1 /
/// esplanada de Verão). Apenas um pode ser is_default.
class FloorPlan {
  FloorPlan({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.isDefault,
    required this.widthCm,
    required this.heightCm,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final bool isDefault;
  final int widthCm;
  final int heightCm;
  final bool active;
  final DateTime createdAt;

  factory FloorPlan.fromJson(Map<String, dynamic> map) {
    return FloorPlan(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      name: (map['name'] as String?) ?? 'Sala principal',
      isDefault: (map['is_default'] as bool?) ?? false,
      widthCm: (map['width_cm'] as int?) ?? 1000,
      heightCm: (map['height_cm'] as int?) ?? 800,
      active: (map['active'] as bool?) ?? true,
      createdAt: map['created_at'] is String
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }
}
