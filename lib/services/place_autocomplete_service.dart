import 'package:latlong2/latlong.dart' as ll;

import 'place_autocomplete_service_stub.dart'
    if (dart.library.html) 'place_autocomplete_service_web.dart'
    if (dart.library.io) 'place_autocomplete_service_io.dart'
    as impl;

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.description,
    this.primaryText,
    this.secondaryText,
  });

  final String placeId;
  final String description;
  final String? primaryText;
  final String? secondaryText;
}

abstract class PlaceAutocompleteService {
  Future<List<PlacePrediction>> fetchPredictions(String input);

  Future<ll.LatLng?> resolvePlaceLocation(String placeId);

  /// Geocode a free-form address string. Used as a fallback when
  /// [resolvePlaceLocation] returns null (e.g. Place Details API not enabled).
  Future<ll.LatLng?> geocodeAddress(String address);

  void resetSession();

  void dispose();
}

PlaceAutocompleteService createPlaceAutocompleteService(String apiKey) {
  return impl.createPlaceAutocompleteServiceImpl(apiKey);
}
