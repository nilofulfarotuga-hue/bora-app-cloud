import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:uuid/uuid.dart';

import 'place_autocomplete_service.dart';

PlaceAutocompleteService createPlaceAutocompleteServiceImpl(String apiKey) {
  return _IoPlaceAutocompleteService(apiKey);
}

class _IoPlaceAutocompleteService implements PlaceAutocompleteService {
  _IoPlaceAutocompleteService(this._apiKey);

  final String _apiKey;
  final Uuid _uuid = const Uuid();

  String? _sessionToken;
  String? _lastQuery;
  List<PlacePrediction> _cachedPredictions = const <PlacePrediction>[];

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async {
    final query = input.trim();
    if (query.isEmpty || _apiKey.isEmpty) {
      return const <PlacePrediction>[];
    }

    if (_lastQuery == query && _cachedPredictions.isNotEmpty) {
      return _cachedPredictions;
    }

    _sessionToken ??= _uuid.v4();

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': _apiKey,
        'sessiontoken': _sessionToken!,
        'components': 'country:pt',
        'language': 'pt-PT',
        'types': 'geocode',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
            'PlaceAutocomplete: HTTP ${response.statusCode} => ${response.body}');
        return const <PlacePrediction>[];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        debugPrint(
            'PlaceAutocomplete: API status => $status | error_message => ${data['error_message']}');
        return const <PlacePrediction>[];
      }

      final predictionsJson = data['predictions'] as List<dynamic>? ?? const [];
      final predictions = predictionsJson
          .map((entry) => PlacePrediction(
                placeId:
                    (entry as Map<String, dynamic>)['place_id'] as String? ??
                        '',
                description: entry['description'] as String? ?? '',
                primaryText: (entry['structured_formatting']
                    as Map<String, dynamic>?)?['main_text'] as String?,
                secondaryText: (entry['structured_formatting']
                    as Map<String, dynamic>?)?['secondary_text'] as String?,
              ))
          .where((prediction) => prediction.placeId.isNotEmpty)
          .toList(growable: false);

      _lastQuery = query;
      _cachedPredictions = predictions;
      return predictions;
    } catch (e) {
      debugPrint('PlaceAutocomplete.fetchPredictions: ERROR => $e');
      return const <PlacePrediction>[];
    }
  }

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async {
    if (placeId.isEmpty || _apiKey.isEmpty) {
      return null;
    }

    final token = _sessionToken ?? _uuid.v4();

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'key': _apiKey,
        'sessiontoken': token,
        'language': 'pt-PT',
        'fields': 'geometry',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
            'PlaceDetails: HTTP ${response.statusCode} for placeId=$placeId body=${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        debugPrint(
            'PlaceDetails: status=$status error=${data['error_message']}');
        return null;
      }

      final result = data['result'] as Map<String, dynamic>?;
      final geometry = result?['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;

      final lat = location?['lat'];
      final lng = location?['lng'];

      if (lat is num && lng is num) {
        return ll.LatLng(lat.toDouble(), lng.toDouble());
      }
      return null;
    } catch (e) {
      debugPrint('PlaceAutocomplete.resolvePlaceLocation: ERROR => $e');
      return null;
    } finally {
      resetSession();
    }
  }

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async {
    if (address.isEmpty || _apiKey.isEmpty) return null;
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'address': address,
        'key': _apiKey,
        'language': 'pt-PT',
        'region': 'pt',
      },
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
            'Geocoding: HTTP ${response.statusCode} for "$address" body=${response.body}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        debugPrint('Geocoding: status=$status error=${data['error_message']}');
        return null;
      }
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final geometry = (results.first as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = location?['lat'];
      final lng = location?['lng'];
      if (lat is num && lng is num) {
        return ll.LatLng(lat.toDouble(), lng.toDouble());
      }
      return null;
    } catch (e) {
      debugPrint('Geocoding.geocodeAddress: ERROR => $e');
      return null;
    }
  }

  @override
  void resetSession() {
    _sessionToken = null;
    _lastQuery = null;
    _cachedPredictions = const <PlacePrediction>[];
  }

  @override
  void dispose() {
    resetSession();
  }
}
