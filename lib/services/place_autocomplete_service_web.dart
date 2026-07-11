// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import 'place_autocomplete_service.dart';

PlaceAutocompleteService createPlaceAutocompleteServiceImpl(String apiKey) =>
    _WebPlaceAutocompleteService(apiKey);

/// Web implementation that delegates entirely to the Google Maps JavaScript SDK
/// already loaded in index.html — no HTTP calls, no CORS issues.
class _WebPlaceAutocompleteService implements PlaceAutocompleteService {
  _WebPlaceAutocompleteService(this._apiKey);

  // apiKey is carried in case callers inspect it; the JS SDK uses its own key.
  // ignore: unused_field
  final String _apiKey;

  js.JsObject? _autocompleteSvc;
  js.JsObject? _placesSvc;

  String? _lastQuery;
  List<PlacePrediction> _cachedPredictions = const <PlacePrediction>[];

  /// Lazily creates the two JS service objects.
  /// Returns false if google.maps.places is not yet available.
  bool _init() {
    if (_autocompleteSvc != null) return true;
    try {
      // Explicit existence checks before any cast — avoids null-cast crashes
      // when the Maps JS script is still loading or blocked.
      final googleRaw = js.context['google'];
      if (googleRaw == null || googleRaw is! js.JsObject) return false;

      final mapsRaw = googleRaw['maps'];
      if (mapsRaw == null || mapsRaw is! js.JsObject) return false;

      final placesRaw = mapsRaw['places'];
      if (placesRaw == null || placesRaw is! js.JsObject) return false;

      final autocompleteCtor = placesRaw['AutocompleteService'];
      if (autocompleteCtor == null || autocompleteCtor is! js.JsFunction) {
        return false;
      }

      final placesCtor = placesRaw['PlacesService'];
      if (placesCtor == null || placesCtor is! js.JsFunction) return false;

      _autocompleteSvc = js.JsObject(autocompleteCtor);
      _placesSvc = js.JsObject(placesCtor, [html.DivElement()]);
      return true;
    } catch (_) {
      // Unexpected error — treat as not-yet-loaded
      return false;
    }
  }

  /// Constrói um `google.maps.LatLng` para o viés da Guarda. Devolve null se
  /// o SDK ainda não estiver pronto (o autocomplete funciona na mesma, sem viés).
  js.JsObject? _guardaLatLng() {
    try {
      final googleRaw = js.context['google'];
      if (googleRaw is! js.JsObject) return null;
      final mapsRaw = googleRaw['maps'];
      if (mapsRaw is! js.JsObject) return null;
      final latLngCtor = mapsRaw['LatLng'];
      if (latLngCtor is! js.JsFunction) return null;
      return js.JsObject(latLngCtor, [kGuardaBiasLat, kGuardaBiasLng]);
    } catch (_) {
      return null;
    }
  }

  // ─── fetchPredictions ──────────────────────────────────────────────────────

  /// Reordena as predições para que as da Guarda apareçam primeiro (ordenação
  /// estável). O viés location+radius do Google é fraco; para a cidade única de
  /// operação queremos garantia de que o resultado local ganha o topo.
  List<PlacePrediction> _rankGuardaFirst(List<PlacePrediction> predictions) {
    if (predictions.length < 2) return predictions;
    final guarda = predictions.where(_isGuarda).toList();
    if (guarda.isEmpty) return predictions;
    final outros = predictions.where((p) => !_isGuarda(p)).toList();
    return <PlacePrediction>[...guarda, ...outros];
  }

  bool _isGuarda(PlacePrediction p) =>
      '${p.description} ${p.secondaryText ?? ''}'
          .toLowerCase()
          .contains('guarda');

  List<PlacePrediction> _mergeDedupe(
    List<PlacePrediction> prioritarias,
    List<PlacePrediction> resto,
  ) {
    final vistos = <String>{};
    final out = <PlacePrediction>[];
    for (final p in <PlacePrediction>[...prioritarias, ...resto]) {
      if (vistos.add(p.placeId)) out.add(p);
    }
    return out;
  }

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async {
    final query = input.trim();
    if (query.isEmpty) return const <PlacePrediction>[];

    if (_lastQuery == query && _cachedPredictions.isNotEmpty) {
      return _cachedPredictions;
    }

    if (!_init()) return const <PlacePrediction>[];

    var predictions = await _requestPredictions(query);
    // Espelha o io.dart (v2): o viés do Google é fraco e o gate "só quando não
    // há Guarda" era frágil (um homónimo/rua da Guarda saltava o retry). Dispara
    // SEMPRE a pesquisa explícita "<query> Guarda" e coloca-a à frente (dedup).
    // Cobre o "outra cidade em 1.º" E o "vazio" (comércio local, ex.: "Lavie").
    if (!query.toLowerCase().contains('guarda')) {
      final locais = await _requestPredictions('$query Guarda');
      predictions = _mergeDedupe(locais, predictions);
    }
    predictions = _rankGuardaFirst(predictions);

    _lastQuery = query;
    _cachedPredictions = predictions;
    return predictions;
  }

  Future<List<PlacePrediction>> _requestPredictions(String query) async {
    final completer = Completer<List<PlacePrediction>>();

    // Sem 'types': devolve moradas E comércios/POIs (ex.: "KFC", "Lavie
    // Shopping"), como a pesquisa do Google Maps. Antes estava preso a
    // 'geocode' (só ruas).
    final request = <String, dynamic>{
      'input': query,
      'componentRestrictions': {'country': 'pt'},
      'language': 'pt-PT',
    };
    // Viés FORTE para a Guarda (location + radius + strictbounds → restringe
    // ao raio de serviço, elimina lojas homónimas de outras cidades). Só
    // aplica se o construtor LatLng existir.
    final biasLocation = _guardaLatLng();
    if (biasLocation != null) {
      request['location'] = biasLocation;
      request['radius'] = kGuardaBiasRadiusMeters;
      if (kGuardaStrictBounds) request['strictbounds'] = true;
    }

    // dart:js.JsObject.callMethod wraps Dart functions automatically.
    _autocompleteSvc!.callMethod('getPlacePredictions', [
      js.JsObject.jsify(request),
      (dynamic predictions, dynamic status) {
        if (completer.isCompleted) return;

        if (status?.toString() != 'OK' || predictions == null) {
          completer.complete(const <PlacePrediction>[]);
          return;
        }

        try {
          final arr = predictions as js.JsArray;
          final list = <PlacePrediction>[];
          for (var i = 0; i < arr.length; i++) {
            final p = arr[i] as js.JsObject;
            final placeId = p['place_id'] as String? ?? '';
            if (placeId.isEmpty) continue;
            final sf = p['structured_formatting'] as js.JsObject?;
            final types = p['types'];
            final isEstablishment = types is js.JsArray &&
                types.any((t) => t?.toString() == 'establishment');
            list.add(PlacePrediction(
              placeId: placeId,
              description: p['description'] as String? ?? '',
              primaryText: sf?['main_text'] as String?,
              secondaryText: sf?['secondary_text'] as String?,
              isEstablishment: isEstablishment,
            ));
          }
          completer.complete(list);
        } catch (_) {
          completer.complete(const <PlacePrediction>[]);
        }
      },
    ]);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return const <PlacePrediction>[];
    }
  }

  // ─── resolvePlaceLocation ──────────────────────────────────────────────────

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async {
    if (placeId.isEmpty) return null;
    if (!_init()) return null;

    final completer = Completer<ll.LatLng?>();

    _placesSvc!.callMethod('getDetails', [
      js.JsObject.jsify({
        'placeId': placeId,
        'fields': ['geometry'],
        'language': 'pt-PT',
      }),
      (dynamic result, dynamic status) {
        if (completer.isCompleted) return;

        if (status?.toString() != 'OK' || result == null) {
          completer.complete(null);
          return;
        }

        try {
          final geometry = (result as js.JsObject)['geometry'] as js.JsObject?;
          final location = geometry?['location'] as js.JsObject?;
          if (location == null) {
            completer.complete(null);
            return;
          }
          final lat = (location.callMethod('lat', const []) as num).toDouble();
          final lng = (location.callMethod('lng', const []) as num).toDouble();
          completer.complete(ll.LatLng(lat, lng));
        } catch (_) {
          completer.complete(null);
        }
      },
    ]);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      resetSession();
    }
  }

  // ─── geocodeAddress ────────────────────────────────────────────────────────

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async {
    if (address.isEmpty) return null;

    final googleRaw = js.context['google'];
    if (googleRaw == null || googleRaw is! js.JsObject) return null;
    final mapsRaw = googleRaw['maps'];
    if (mapsRaw == null || mapsRaw is! js.JsObject) return null;
    final geocoderCtor = mapsRaw['Geocoder'];
    if (geocoderCtor == null || geocoderCtor is! js.JsFunction) return null;

    final geocoder = js.JsObject(geocoderCtor);
    final completer = Completer<ll.LatLng?>();

    geocoder.callMethod('geocode', [
      js.JsObject.jsify({'address': address, 'region': 'pt'}),
      (dynamic results, dynamic status) {
        if (completer.isCompleted) return;
        if (status?.toString() != 'OK' || results == null) {
          completer.complete(null);
          return;
        }
        try {
          final arr = results as js.JsArray;
          if (arr.isEmpty) {
            completer.complete(null);
            return;
          }
          final first = arr[0] as js.JsObject;
          final geometry = first['geometry'] as js.JsObject?;
          final location = geometry?['location'] as js.JsObject?;
          if (location == null) {
            completer.complete(null);
            return;
          }
          final lat = (location.callMethod('lat', const []) as num).toDouble();
          final lng = (location.callMethod('lng', const []) as num).toDouble();
          completer.complete(ll.LatLng(lat, lng));
        } catch (_) {
          completer.complete(null);
        }
      },
    ]);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  // ─── session / lifecycle ───────────────────────────────────────────────────

  @override
  void resetSession() {
    _lastQuery = null;
    _cachedPredictions = const <PlacePrediction>[];
  }

  @override
  void dispose() {
    resetSession();
    _autocompleteSvc = null;
    _placesSvc = null;
  }
}
