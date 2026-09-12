import 'package:latlong2/latlong.dart' as ll;

import 'place_autocomplete_service_stub.dart'
    if (dart.library.html) 'place_autocomplete_service_web.dart'
    if (dart.library.io) 'place_autocomplete_service_io.dart' as impl;

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.description,
    this.primaryText,
    this.secondaryText,
    this.isEstablishment = false,
  });

  final String placeId;
  final String description;
  final String? primaryText;
  final String? secondaryText;

  /// True quando a predição é um comércio / ponto de interesse (ex.: "KFC",
  /// "Lavie Shopping") e não apenas uma morada. Usado para mostrar o ícone
  /// de loja em vez do pino de morada, à semelhança do Google Maps.
  final bool isEstablishment;
}

/// Estado do serviço de sugestões no momento de uma pesquisa. Antes o serviço
/// devolvia lista vazia tanto para "sem resultados" como para "o SDK do Google
/// nem sequer carregou" — e o campo de morada morria em silêncio (cliente TVDE
/// perdida 2x na web, 2026-08-31). Agora o widget distingue os três casos.
enum PlaceServiceStatus {
  /// O serviço respondeu; a lista (mesmo vazia) é uma resposta real.
  ready,

  /// O serviço ainda está a carregar (ex.: script do Google Maps a chegar).
  /// Vale a pena tentar outra vez na tecla seguinte.
  loading,

  /// O serviço não está disponível (script bloqueado/falhou e o plano B
  /// também não respondeu). O utilizador tem de poder escrever à mão.
  unavailable,
}

class PredictionsResult {
  const PredictionsResult(this.status, this.predictions);
  final PlaceServiceStatus status;
  final List<PlacePrediction> predictions;
}

abstract class PlaceAutocompleteService {
  Future<List<PlacePrediction>> fetchPredictions(String input);

  /// Igual a [fetchPredictions] mas com o estado do serviço. A implementação
  /// por omissão assume serviço sempre pronto (io/stub); a web substitui.
  Future<PredictionsResult> fetchPredictionsWithStatus(String input) async {
    final list = await fetchPredictions(input);
    return PredictionsResult(PlaceServiceStatus.ready, list);
  }

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
