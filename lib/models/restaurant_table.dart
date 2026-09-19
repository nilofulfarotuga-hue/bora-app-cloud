/// Reservas PRO F4 — mesa do restaurante (`restaurant_tables`).
///
/// Posições em cm (não pixels — independente da resolução).
/// shape: 'rectangle' / 'circle' / 'square'.
/// zona: 'interior' / 'esplanada' / 'balcao' / 'privado'.
class RestaurantTable {
  RestaurantTable({
    required this.id,
    required this.restaurantId,
    this.floorPlanId,
    required this.numero,
    required this.capacity,
    required this.zona,
    required this.posX,
    required this.posY,
    required this.rotationDeg,
    required this.shape,
    required this.combinableWith,
    required this.active,
    this.notes,
  });

  final String id;
  final String restaurantId;
  final String? floorPlanId;
  final String numero;
  final int capacity;
  final String zona;
  final double posX;
  final double posY;
  final int rotationDeg;
  final String shape;
  final List<String> combinableWith;
  final bool active;
  final String? notes;

  factory RestaurantTable.fromJson(Map<String, dynamic> map) {
    final combinable = (map['combinable_with'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return RestaurantTable(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      floorPlanId: map['floor_plan_id'] as String?,
      numero: (map['numero'] as String?) ?? '',
      capacity: (map['capacity'] as int?) ?? 2,
      zona: (map['zona'] as String?) ?? 'interior',
      posX: ((map['pos_x'] as num?) ?? 0).toDouble(),
      posY: ((map['pos_y'] as num?) ?? 0).toDouble(),
      rotationDeg: (map['rotation_deg'] as int?) ?? 0,
      shape: (map['shape'] as String?) ?? 'rectangle',
      combinableWith: combinable,
      active: (map['active'] as bool?) ?? true,
      notes: map['notes'] as String?,
    );
  }

  RestaurantTable copyWith({
    double? posX,
    double? posY,
    int? rotationDeg,
  }) =>
      RestaurantTable(
        id: id,
        restaurantId: restaurantId,
        floorPlanId: floorPlanId,
        numero: numero,
        capacity: capacity,
        zona: zona,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
        rotationDeg: rotationDeg ?? this.rotationDeg,
        shape: shape,
        combinableWith: combinableWith,
        active: active,
        notes: notes,
      );
}
