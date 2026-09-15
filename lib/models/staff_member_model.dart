/// Profissional/colaborador de um prestador (vertical Serviços).
///
/// Espelha a tabela `staff_members`.
class StaffMemberModel {
  StaffMemberModel({
    required this.id,
    required this.providerId,
    required this.name,
    this.bio,
    this.photoUrl,
    this.specialties = const [],
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String providerId;
  final String name;
  final String? bio;
  final String? photoUrl;
  final List<String> specialties;
  final bool isActive;
  final int sortOrder;

  factory StaffMemberModel.fromSupabase(Map<String, dynamic> row) {
    final raw = row['specialties'];
    final specialties = raw is List
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];
    return StaffMemberModel(
      id: row['id'] as String,
      providerId: row['provider_id'] as String,
      name: (row['name'] as String?) ?? '',
      bio: row['bio'] as String?,
      photoUrl: row['photo_url'] as String?,
      specialties: specialties,
      isActive: (row['is_active'] as bool?) ?? true,
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider_id': providerId,
        'name': name,
        if (bio != null) 'bio': bio,
        if (photoUrl != null) 'photo_url': photoUrl,
        'specialties': specialties,
        'is_active': isActive,
        'sort_order': sortOrder,
      };
}
