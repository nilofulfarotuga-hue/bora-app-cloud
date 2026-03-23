import 'package:latlong2/latlong.dart' as ll;

import 'place_autocomplete_service.dart';

PlaceAutocompleteService createPlaceAutocompleteServiceImpl(String apiKey) {
  return _NoopPlaceAutocompleteService();
}

class _NoopPlaceAutocompleteService implements PlaceAutocompleteService {
  @override
  void dispose() {}

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async {
    return const <PlacePrediction>[];
  }

  @override
  void resetSession() {}

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async {
    return null;
  }
}
