import 'package:bora_app/services/place_autocomplete_service.dart';
import 'package:bora_app/widgets/address_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Serviço falso: devolve uma lista fixa, sem rede. Serve para provar que as
/// sugestões RENDERIZAM (a regressão do TVDE era uma caixa branca vazia).
class _FakePlaceService extends PlaceAutocompleteService {
  _FakePlaceService(
    this.results, {
    this.status = PlaceServiceStatus.ready,
    this.geocodeResult,
  });
  final List<PlacePrediction> results;
  final PlaceServiceStatus status;
  final ll.LatLng? geocodeResult;

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async => results;

  @override
  Future<PredictionsResult> fetchPredictionsWithStatus(String input) async =>
      PredictionsResult(status, results);

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async => null;

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async => geocodeResult;

  @override
  void resetSession() {}

  @override
  void dispose() {}
}

Future<void> _pumpField(
  WidgetTester tester, {
  required List<PlacePrediction> results,
  bool insideScrollable = false,
}) async {
  final field = AddressAutocompleteField(
    controller: TextEditingController(),
    onSelected: (_, __) {},
    serviceOverride: _FakePlaceService(results),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: insideScrollable
          ? ListView(children: [const SizedBox(height: 400), field])
          : field,
    ),
  ));
}

void main() {
  testWidgets('sugestões renderizam (lista não vazia) quando há resultados',
      (tester) async {
    await _pumpField(tester, results: const [
      PlacePrediction(
          placeId: '1',
          description: 'Rua das Flores, Lisboa',
          primaryText: 'Rua das Flores',
          secondaryText: 'Lisboa'),
      PlacePrediction(
          placeId: '2',
          description: 'Rua Augusta, Lisboa',
          primaryText: 'Rua Augusta',
          secondaryText: 'Lisboa'),
    ]);

    await tester.enterText(find.byType(TextField), 'rua');
    // Deixa o debounce (250 ms) disparar + o fetch async + o overlay inserir.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    // As sugestões TÊM de estar visíveis no overlay (não caixa vazia).
    expect(find.text('Rua das Flores'), findsOneWidget);
    expect(find.text('Rua Augusta'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('campo a meio de um Scrollable também mostra as sugestões',
      (tester) async {
    // Reproduz a situação do destino do TVDE (campo a meio da página, dentro
    // de um Scrollable) — antes dava caixa branca vazia ao abrir para cima.
    await _pumpField(
      tester,
      insideScrollable: true,
      results: const [
        PlacePrediction(
            placeId: '9',
            description: 'Avenida da Liberdade, Lisboa',
            primaryText: 'Avenida da Liberdade'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'av');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    expect(find.text('Avenida da Liberdade'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('1 caractere já dispara sugestões (estilo Uber)',
      (tester) async {
    await _pumpField(tester, results: const [
      PlacePrediction(
          placeId: '3', description: 'Rossio', primaryText: 'Rossio'),
    ]);

    await tester.enterText(find.byType(TextField), 'r');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    expect(find.text('Rossio'), findsOneWidget);
  });

  testWidgets('comércio/POI mostra ícone de loja + morada (estilo Google Maps)',
      (tester) async {
    // Prova a extensão: predições de estabelecimento (isEstablishment=true)
    // renderizam com o ícone de loja, e moradas normais com o pino.
    await _pumpField(tester, results: const [
      PlacePrediction(
        placeId: 'kfc',
        description: 'KFC, Rua Dr. Francisco de Passos, Guarda',
        primaryText: 'KFC',
        secondaryText: 'Rua Dr. Francisco de Passos, Guarda',
        isEstablishment: true,
      ),
      PlacePrediction(
        placeId: 'rua',
        description: 'Rua Rui de Pina, Guarda',
        primaryText: 'Rua Rui de Pina',
        secondaryText: 'Guarda',
      ),
    ]);

    await tester.enterText(find.byType(TextField), 'kfc');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    // Nome do local + morada visíveis (padrão Google Maps).
    expect(find.text('KFC'), findsOneWidget);
    expect(
        find.text('Rua Dr. Francisco de Passos, Guarda'), findsOneWidget);
    // Ícone de loja só para o POI (o campo não usa storefront).
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    // Pino na morada normal + no prefixo default do próprio campo = 2.
    expect(find.byIcon(Icons.location_on_outlined), findsNWidgets(2));
  });

  // ── Missão endereco-web-2026-08-31: o campo NUNCA morre em silêncio ──────

  testWidgets('serviço indisponível → aviso PT-PT + modo manual',
      (tester) async {
    String? selecionada;
    ll.LatLng? coords;
    final field = AddressAutocompleteField(
      controller: TextEditingController(),
      onSelected: (a, c) {
        selecionada = a;
        coords = c;
      },
      serviceOverride: _FakePlaceService(
        const [],
        status: PlaceServiceStatus.unavailable,
        geocodeResult: ll.LatLng(40.53, -7.26),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));

    await tester.enterText(
        find.byType(TextField), 'Rua da Torre 5, Guarda');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    // Nada de campo mudo: aviso + botão de seguir com a morada escrita.
    expect(
        find.text('Sem sugestões automáticas neste momento.'), findsOneWidget);
    expect(find.textContaining('Usar esta morada'), findsOneWidget);

    await tester.tap(find.textContaining('Usar esta morada'));
    await tester.pump();
    await tester.pump();

    // A morada escrita seguiu, com coordenadas do geocode (plano B).
    expect(selecionada, 'Rua da Torre 5, Guarda');
    expect(coords, isNotNull);
  });

  testWidgets('sem resultados com serviço vivo → mensagem + modo manual',
      (tester) async {
    await _pumpField(tester, results: const []);

    await tester.enterText(find.byType(TextField), 'morada inventada xyz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    expect(find.text('Não encontrei essa morada.'), findsOneWidget);
    expect(find.text('Escreve a rua e o número.'), findsOneWidget);
    expect(find.textContaining('Usar esta morada'), findsOneWidget);
  });

  testWidgets('serviço a carregar → "A procurar moradas…"', (tester) async {
    final field = AddressAutocompleteField(
      controller: TextEditingController(),
      onSelected: (_, __) {},
      serviceOverride:
          _FakePlaceService(const [], status: PlaceServiceStatus.loading),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));

    await tester.enterText(find.byType(TextField), 'rua');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    expect(find.text('A procurar moradas…'), findsOneWidget);
  });
}
