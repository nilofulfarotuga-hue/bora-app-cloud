/// ClientAddress — endereço guardado do cliente (Casa, Trabalho, Outro).
/// Tabela: `client_addresses` (criada via MCP).
/// Cliente pode ter N endereços; um marcado is_default=true.
class ClientAddress {
  final String id;
  final String userId;
  final String label;          // "Casa", "Trabalho", "Outro" (livre)
  final String address;        // string formatada completa (linha única)
  final String? street;
  final String? city;
  final String? postalCode;
  final double? lat;
  final double? lng;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClientAddress({
    required this.id,
    required this.userId,
    required this.label,
    required this.address,
    this.street,
    this.city,
    this.postalCode,
    this.lat,
    this.lng,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientAddress.fromJson(Map<String, dynamic> j) => ClientAddress(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        label: j['label'] as String,
        address: j['address'] as String,
        street: j['street'] as String?,
        city: j['city'] as String?,
        postalCode: j['postal_code'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        isDefault: (j['is_default'] as bool?) ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'label': label,
        'address': address,
        if (street != null) 'street': street,
        if (city != null) 'city': city,
        if (postalCode != null) 'postal_code': postalCode,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'is_default': isDefault,
      };

  ClientAddress copyWith({
    String? label,
    String? address,
    String? street,
    String? city,
    String? postalCode,
    double? lat,
    double? lng,
    bool? isDefault,
  }) =>
      ClientAddress(
        id: id,
        userId: userId,
        label: label ?? this.label,
        address: address ?? this.address,
        street: street ?? this.street,
        city: city ?? this.city,
        postalCode: postalCode ?? this.postalCode,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
