import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:uuid/uuid.dart';

import '../config/maps_config.dart';
import 'place_autocomplete_service.dart';

PlaceAutocompleteService createPlaceAutocompleteServiceImpl(String apiKey) {
  return _IoPlaceAutocompleteService(apiKey);
}

/// Test-only: injeta um [http.Client] falso para exercitar a lógica de viés
/// geográfico da Guarda (retry "<query> Guarda", fallback sem viés, rerank)
/// sem rede nem device. Cobre o bug real (Continente-outra-cidade / Lavie-vazio)
/// que o teste de widget com serviço mock NÃO via.
@visibleForTesting
PlaceAutocompleteService createPlaceAutocompleteServiceForTest(
  String apiKey,
  http.Client client,
) {
  return _IoPlaceAutocompleteService(apiKey, client: client);
}

class _IoPlaceAutocompleteService implements PlaceAutocompleteService {
  _IoPlaceAutocompleteService(this._apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;
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

    try {
      // 1.ª tentativa: com viés geográfico da Guarda (puxa o local para o topo).
      var predictions = await _requestPredictions(query, biased: true);

      // CORREÇÃO (bug real telemóvel): o viés location+radius do Google é FRACO.
      // Para "Continente" ele devolve 5 Continentes de cidades maiores (Lisboa,
      // Porto…) e o da Guarda NEM APARECE no conjunto — logo _rankGuardaFirst
      // não tinha o que reordenar. Sempre que NENHUM resultado local (Guarda)
      // surgiu, disparamos uma pesquisa EXPLÍCITA "<query> Guarda" e colocamos
      // esses resultados à frente (dedup por place_id). Isto GARANTE que o
      // Continente/Pingo Doce/Lavie da Guarda aparece — cobre o caso "outra
      // cidade em 1.º" E o caso "vazio" (comércio local mal indexado, ex.:
      // "Lavie" sozinho sob country:pt não surge, mas "Lavie Guarda" devolve o
      // LaVie Shopping). Só dispara quando não há local → não penaliza moradas.
      final semGuarda = !predictions.any(_isGuarda);
      if (semGuarda && !query.toLowerCase().contains('guarda')) {
        final locais = await _requestPredictions('$query Guarda', biased: true);
        predictions = _mergeDedupe(locais, predictions);
      }

      // Cobertura final: se AINDA vier vazio (nome que o Google não indexa nem
      // com " Guarda"), repete SEM viés (cobertura nacional) para nunca deixar
      // um nome de negócio válido sem qualquer resultado.
      if (predictions.isEmpty) {
        predictions = await _requestPredictions(query, biased: false);
      }

      // Re-ranking determinístico: puxa para o topo qualquer predição da Guarda
      // que exista no conjunto, mantendo ordem estável e sem excluir os demais.
      predictions = _rankGuardaFirst(predictions);

      _lastQuery = query;
      _cachedPredictions = predictions;
      return predictions;
    } catch (e) {
      debugPrint('PlaceAutocomplete.fetchPredictions: ERROR => $e');
      return const <PlacePrediction>[];
    }
  }

  /// Reordena as predições para que as da Guarda apareçam primeiro, mantendo a
  /// ordem relativa original dentro de cada grupo (ordenação estável). O viés
  /// geográfico do Google é apenas um empurrão de ranking; para uma cidade
  /// única de operação (Guarda) queremos garantia, não probabilidade.
  List<PlacePrediction> _rankGuardaFirst(List<PlacePrediction> predictions) {
    if (predictions.length < 2) return predictions;
    final guarda = <PlacePrediction>[];
    final outros = <PlacePrediction>[];
    for (final p in predictions) {
      (_isGuarda(p) ? guarda : outros).add(p);
    }
    if (guarda.isEmpty) return predictions;
    return <PlacePrediction>[...guarda, ...outros];
  }

  /// True se a predição menciona a Guarda (na descrição ou no texto secundário).
  bool _isGuarda(PlacePrediction p) =>
      '${p.description} ${p.secondaryText ?? ''}'
          .toLowerCase()
          .contains('guarda');

  /// Junta duas listas de predições colocando [prioritarias] à frente e
  /// anexando de [resto] só as que ainda não apareceram (dedup por place_id).
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

  Future<List<PlacePrediction>> _requestPredictions(
    String query, {
    required bool biased,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': _apiKey,
        'sessiontoken': _sessionToken!,
        'components': 'country:pt',
        'language': 'pt-PT',
        // Sem 'types': devolve moradas E comércios/POIs (ex.: "KFC", "Lavie
        // Shopping"), tal como a barra de pesquisa do Google Maps.
        if (biased) ...{
          // Viés SUAVE para a Guarda: location + radius empurra os resultados
          // locais para o topo sem os excluir à força (ver maps_config.dart —
          // strictbounds foi removido porque matava comércios locais).
          'location': '$kGuardaBiasLat,$kGuardaBiasLng',
          'radius': '$kGuardaBiasRadiusMeters',
          if (kGuardaStrictBounds) 'strictbounds': 'true',
        },
      },
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      debugPrint(
          'PlaceAutocomplete: HTTP ${response.statusCode} => ${response.body}');
      return const <PlacePrediction>[];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK') {
      // ZERO_RESULTS é esperado no fallback; só logamos erros reais.
      if (status != 'ZERO_RESULTS') {
        debugPrint(
            'PlaceAutocomplete: API status => $status | error_message => ${data['error_message']}');
      }
      return const <PlacePrediction>[];
    }

    final predictionsJson = data['predictions'] as List<dynamic>? ?? const [];
    return predictionsJson
        .map((entry) => PlacePrediction(
              placeId: (entry as Map<String, dynamic>)['place_id'] as String? ??
                  '',
              description: entry['description'] as String? ?? '',
              primaryText: (entry['structured_formatting']
                  as Map<String, dynamic>?)?['main_text'] as String?,
              secondaryText: (entry['structured_formatting']
                  as Map<String, dynamic>?)?['secondary_text'] as String?,
              isEstablishment: (entry['types'] as List<dynamic>?)
                      ?.contains('establishment') ??
                  false,
            ))
        .where((prediction) => prediction.placeId.isNotEmpty)
        .toList(growable: false);
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
      final response = await _client.get(uri);
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
      final response = await _client.get(uri);
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
