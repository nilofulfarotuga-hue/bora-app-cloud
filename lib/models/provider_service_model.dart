/// Serviço oferecido por um prestador (vertical Serviços).
///
/// Espelha a tabela `provider_services`. Preço em cêntimos
/// (`price_cents`), duração em minutos (`duration_minutes`).
class ProviderServiceModel {
  ProviderServiceModel({
    required this.id,
    required this.providerId,
    required this.name,
    this.description,
    this.durationMinutes = 30,
    this.priceCents = 0,
    this.photoUrl,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String providerId;
  final String name;
  final String? description;
  final int durationMinutes;
  final int priceCents;
  final String? photoUrl;
  final bool isActive;
  final int sortOrder;

  /// Preço formatado em euros: '€12,00' → usa '.' por consistência com o
  /// resto da app ('€${(cents/100).toStringAsFixed(2)}').
  String get priceLabel => '€${(priceCents / 100).toStringAsFixed(2)}';

  /// Duração legível: '45 min' ou '1h15'.
  String get durationLabel {
    if (durationMinutes < 60) return '$durationMinutes min';
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  factory ProviderServiceModel.fromSupabase(Map<String, dynamic> row) {
    return ProviderServiceModel(
      id: row['id'] as String,
      providerId: row['provider_id'] as String,
      name: (row['name'] as String?) ?? '',
      description: row['description'] as String?,
      durationMinutes: (row['duration_minutes'] as int?) ?? 30,
      priceCents: (row['price_cents'] as int?) ?? 0,
      photoUrl: row['photo_url'] as String?,
      isActive: (row['is_active'] as bool?) ?? true,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider_id': providerId,
        'name': name,
        if (description != null) 'description': description,
        'duration_minutes': durationMinutes,
        'price_cents': priceCents,
        if (photoUrl != null) 'photo_url': photoUrl,
        'is_active': isActive,
        'sort_order': sortOrder,
      };
}
