import 'package:latlong2/latlong.dart';

enum BusinessCategory {
  restaurant,
  supermarket,
  store,
  pharmacy,
}

extension BusinessCategoryLabel on BusinessCategory {
  String get label {
    switch (this) {
      case BusinessCategory.restaurant:
        return 'Restaurante';
      case BusinessCategory.supermarket:
        return 'Supermercado';
      case BusinessCategory.store:
        return 'Loja';
      case BusinessCategory.pharmacy:
        return 'Farmácia';
    }
  }
}

class RestaurantModel {
  const RestaurantModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    required this.photoUrl,
    required this.cuisineType,
    required this.isPartner,
    required this.category,
    this.isOnline = true,
    this.lat,
    this.lng,
    this.reservationsEnabled = false,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String photoUrl;
  final String cuisineType;
  final bool isPartner;
  final BusinessCategory category;
  final bool isOnline;
  final double? lat;
  final double? lng;

  /// BR §14.10 — whether this restaurant accepts table reservations.
  /// Default false. Partner toggles it from the dashboard.
  final bool reservationsEnabled;

  /// Returns a [LatLng] when both coordinates are stored; null otherwise.
  LatLng? get location =>
      (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  RestaurantModel copyWith({
    bool? isOnline,
    double? lat,
    double? lng,
    bool? reservationsEnabled,
  }) {
    return RestaurantModel(
      id: id,
      name: name,
      phone: phone,
      address: address,
      email: email,
      photoUrl: photoUrl,
      cuisineType: cuisineType,
      isPartner: isPartner,
      category: category,
      isOnline: isOnline ?? this.isOnline,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
    );
  }
}
