/// Prestador de serviços (vertical Serviços / Barbearias).
///
/// Espelha a tabela `service_providers`. SELECT público quando
/// `is_online = true AND approval_status = 'approved'` (RLS).
class ServiceProviderModel {
  ServiceProviderModel({
    required this.id,
    required this.name,
    this.userId,
    this.category,
    this.description,
    this.address,
    this.lat,
    this.lng,
    this.phone,
    this.photoUrl,
    this.heroImageUrl,
    this.isOnline = false,
    this.isActiveAdmin = true,
    this.approvalStatus = 'pending',
    this.businessHours,
    this.avgRating = 0,
    this.ratingsCount = 0,
    this.aboutText,
    this.galleryUrls = const [],
    this.socialInstagram,
    this.socialFacebook,
  });

  final String id;
  final String name;
  final String? userId;
  final String? category;
  final String? description;
  final String? address;
  final double? lat;
  final double? lng;
  final String? phone;
  final String? photoUrl;
  final String? heroImageUrl;
  final bool isOnline;
  final bool isActiveAdmin;
  final String approvalStatus;
  final Map<String, dynamic>? businessHours;
  final double avgRating;
  final int ratingsCount;
  final String? aboutText;
  final List<String> galleryUrls;
  final String? socialInstagram;
  final String? socialFacebook;

  factory ServiceProviderModel.fromSupabase(Map<String, dynamic> row) {
    // PostgREST serializa colunas `numeric` (ex.: avg_rating) como String para
    // preservar precisão — `as num` rebentaria. Aceitar num OU String.
    double? toD(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    return ServiceProviderModel(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
      userId: row['user_id'] as String?,
      category: row['category'] as String?,
      description: row['description'] as String?,
      address: row['address'] as String?,
      lat: toD(row['lat']),
      lng: toD(row['lng']),
      phone: row['phone'] as String?,
      photoUrl: row['photo_url'] as String?,
      heroImageUrl: row['hero_image_url'] as String?,
      isOnline: (row['is_online'] as bool?) ?? false,
      isActiveAdmin: (row['is_active_admin'] as bool?) ?? true,
      approvalStatus: (row['approval_status'] as String?) ?? 'pending',
      businessHours: row['business_hours'] is Map
          ? Map<String, dynamic>.from(row['business_hours'] as Map)
          : null,
      avgRating: toD(row['avg_rating']) ?? 0,
      ratingsCount: (row['ratings_count'] as int?) ?? 0,
      aboutText: row['about_text'] as String?,
      galleryUrls: row['gallery_urls'] is List
          ? (row['gallery_urls'] as List).map((e) => e.toString()).toList()
          : const [],
      socialInstagram: row['social_instagram'] as String?,
      socialFacebook: row['social_facebook'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (userId != null) 'user_id': userId,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (phone != null) 'phone': phone,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (heroImageUrl != null) 'hero_image_url': heroImageUrl,
        'is_online': isOnline,
        'is_active_admin': isActiveAdmin,
        'approval_status': approvalStatus,
        if (businessHours != null) 'business_hours': businessHours,
        'avg_rating': avgRating,
        'ratings_count': ratingsCount,
        if (aboutText != null) 'about_text': aboutText,
        'gallery_urls': galleryUrls,
        if (socialInstagram != null) 'social_instagram': socialInstagram,
        if (socialFacebook != null) 'social_facebook': socialFacebook,
      };
}
