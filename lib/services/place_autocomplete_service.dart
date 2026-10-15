import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import 'morada_tolerante.dart';
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

/// Morada escrita à mão que se encontrou no mapa: as coordenadas e, quando o
/// serviço a devolve, a morada como o Google a escreve (para o cliente
/// confirmar que é aquela).
class MoradaGeocodificada {
  const MoradaGeocodificada(this.coords, {this.morada});
  final ll.LatLng coords;
  final String? morada;
}

/// Um resultado de geocodificação ainda por escolher (ver [escolherMelhorNaGuarda]).
class CandidatoGeocode {
  const CandidatoGeocode({
    required this.coords,
    required this.morada,
    required this.tipos,
  });
  final ll.LatLng coords;
  final String morada;
  final List<String> tipos;
}

/// Tipos que dizem "isto é uma cidade/região inteira", não um sítio onde um
/// motorista pare. Um resultado SÓ com estes tipos não serve de recolha.
const Set<String> _tiposLargos = {
  'locality',
  'political',
  'country',
  'administrative_area_level_1',
  'administrative_area_level_2',
  'administrative_area_level_3',
  'administrative_area_level_4',
  'colloquial_area',
};

/// Escolhe o melhor resultado de geocodificação para quem está na Guarda:
/// descarta os que são uma cidade/região inteira (o Google devolve "Guarda"
/// para texto que não entende), e entre os que sobram prefere o que fica na
/// Guarda (no texto ou a menos de 30 km do centro). Sem nenhum na Guarda, fica
/// o primeiro preciso — o cliente vê a morada encontrada e confirma — EXCETO
/// quando [exigirGuarda]: quem escreveu "…, Guarda" e só aparece a mesma rua
/// em Lisboa não quer Lisboa (prova web 15/10: "Av. Rainha D. Amélia 14,
/// Guarda" só dava Lisboa/Sintra/Beja). Aí não há resultado, e o campo diz.
CandidatoGeocode? escolherMelhorNaGuarda(
  List<CandidatoGeocode> candidatos, {
  bool exigirGuarda = false,
  String? textoPesquisado,
}) {
  final precisos = candidatos
      .where((c) => c.tipos.isEmpty || c.tipos.any((t) => !_tiposLargos.contains(t)))
      .where((c) =>
          textoPesquisado == null || partilhaPalavra(textoPesquisado, c.morada))
      .toList();
  if (precisos.isEmpty) return null;
  const centro = ll.LatLng(kGuardaBiasLat, kGuardaBiasLng);
  const distancia = ll.Distance();
  for (final c in precisos) {
    final naGuarda = c.morada.toLowerCase().contains('guarda') ||
        distancia.as(ll.LengthUnit.Kilometer, centro, c.coords) <= 30;
    if (naGuarda) return c;
  }
  return exigirGuarda ? null : precisos.first;
}

/// O cliente escreveu a cidade da Guarda no texto da morada.
bool textoPedeGuarda(String texto) => texto.toLowerCase().contains('guarda');

/// Palavras que aparecem em quase todas as moradas e por isso não provam que
/// o resultado é a morada escrita.
const Set<String> _palavrasGenericas = {
  'rua', 'avenida', 'av', 'largo', 'praca', 'travessa', 'estrada', 'alameda',
  'bairro', 'beco', 'calcada', 'quinta', 'urbanizacao', 'lugar', 'sitio',
  'de', 'da', 'do', 'das', 'dos', 'e', 'a', 'o', 'n', 'no', 'num', 'numero',
  'lote', 'esq', 'dto', 'guarda', 'portugal', 'cidade', 'dr', 'doutor',
};

String _semAcentos(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

Set<String> _palavrasSignificativas(String s) => _semAcentos(s)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) =>
        w.length >= 3 &&
        !_palavrasGenericas.contains(w) &&
        !RegExp(r'^\d').hasMatch(w))
    .toSet();

/// O resultado tem pelo menos uma palavra "a sério" do que o cliente escreveu
/// (nome da rua, do sítio). Prova web 15/10: "Rua Inventada Xyzqw 999,
/// Guarda" voltava "Rua, Portugal" a 6 km — um resultado à toa perto da
/// Guarda, que o filtro da distância deixava passar. Texto só com palavras
/// genéricas (ex.: "Rua 25") não se pode verificar e passa.
bool partilhaPalavra(String escrito, String encontrado) {
  final pedidas = _palavrasSignificativas(escrito);
  if (pedidas.isEmpty) return true;
  final achadas = _palavrasSignificativas(encontrado);
  return pedidas.any(achadas.contains);
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

  /// Geocodifica uma morada escrita à mão, ficando com o melhor resultado na
  /// Guarda e com a morada formatada. Por omissão só sabe as coordenadas
  /// (stub/testes); io e web substituem com a escolha a sério.
  Future<MoradaGeocodificada?> geocodeComMorada(String address) async {
    final c = await geocodeAddress(address);
    return c == null ? null : MoradaGeocodificada(c);
  }

  /// Morada escrita conta sempre (missão tvde-pedir-nunca-trava, 14/10): tenta
  /// o texto todo e, se nada vier, as variantes tolerantes — sem número de
  /// porta, abreviaturas por extenso ("Av." → "Avenida").
  Future<MoradaGeocodificada?> geocodeTolerante(String texto) async {
    for (final v in variantesDeMorada(texto)) {
      final r = await geocodeComMorada(v);
      if (r != null) return r;
    }
    return null;
  }

  /// Sugestões tolerantes: igual a [fetchPredictionsWithStatus], mas quando o
  /// serviço responde e o texto todo não dá nada, repete com as variantes de
  /// [variantesDeMorada], como o Uber faz. Mantém o viés da Guarda (cada
  /// pesquisa passa pela implementação normal).
  Future<PredictionsResult> fetchPredictionsTolerante(String input) async {
    final primeira = await fetchPredictionsWithStatus(input);
    if (primeira.status != PlaceServiceStatus.ready ||
        primeira.predictions.isNotEmpty) {
      return primeira;
    }
    for (final v in variantesDeMorada(input).skip(1)) {
      final r = await fetchPredictionsWithStatus(v);
      if (r.predictions.isNotEmpty) return r;
      if (r.status != PlaceServiceStatus.ready) break;
    }
    return primeira;
  }

  void resetSession();

  void dispose();
}

PlaceAutocompleteService createPlaceAutocompleteService(String apiKey) {
  return impl.createPlaceAutocompleteServiceImpl(apiKey);
}
