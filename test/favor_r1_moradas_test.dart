// Revisão do Bloco B, ronda 1 (fechar-pendencias-2026-10-20):
//  1. resposta atrasada de uma sugestão ANTERIOR não pode chegar ao ecrã
//     (rede lenta + o cliente escreve/escolhe outra coisa → km errado);
//  2. morada escrita à mão: a procura do TVDE com preferência pela Guarda —
//     o "Rua do Comércio, Guarda" a ~11 km não volta por esse caminho;
//  3. com a rede pendurada a escolha acaba em ~10 s e o campo não fica preso.
import 'dart:async';

import 'package:bora_app/services/location_service.dart';
import 'package:bora_app/services/place_autocomplete_service.dart';
import 'package:bora_app/widgets/address_autocomplete_field.dart';
import 'package:bora_app/widgets/business_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

const _comercioCentro = ll.LatLng(40.5389, -7.2680); // a rua da cidade
const _comercioLonge = ll.LatLng(40.4993, -7.1458); // outra freguesia, ~11 km
const _camoes = ll.LatLng(40.5389, -7.2688);
const _goncalo = ll.LatLng(40.4167, -7.1667); // aldeia, longe do centro

const _sugComercio = PlacePrediction(
  placeId: 'comercio',
  description: 'Rua do Comércio, Guarda, Portugal',
  primaryText: 'Rua do Comércio',
  secondaryText: 'Guarda, Portugal',
);
const _sugCamoes = PlacePrediction(
  placeId: 'camoes',
  description: 'Praça Luís de Camões, Guarda, Portugal',
  primaryText: 'Praça Luís de Camões',
  secondaryText: 'Guarda, Portugal',
);
const _sugIgrejaCidade = PlacePrediction(
  placeId: 'igreja-cidade',
  description: 'Rua da Igreja, Guarda, Portugal',
  primaryText: 'Rua da Igreja',
  secondaryText: 'Guarda, Portugal',
);

/// Serviço falso com respostas comandadas pelo teste.
class _Servico extends PlaceAutocompleteService {
  _Servico({
    this.predicoes = const {},
    this.details = const {},
    this.geocodes = const {},
    this.pendurado = false,
  });

  /// prefixo do texto → sugestões
  final Map<String, List<PlacePrediction>> predicoes;

  /// placeId → resposta (Completer para a atrasar à mão)
  final Map<String, Object> details;

  /// texto → coordenadas do Geocoding
  final Map<String, ll.LatLng> geocodes;

  /// rede pendurada: nada responde
  final bool pendurado;

  int pedidosDeSugestoes = 0;

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async {
    pedidosDeSugestoes++;
    for (final e in predicoes.entries) {
      if (input.startsWith(e.key)) return e.value;
    }
    return const [];
  }

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) {
    if (pendurado) return Completer<ll.LatLng?>().future;
    final r = details[placeId];
    if (r is Completer<ll.LatLng?>) return r.future;
    return Future.value(r as ll.LatLng?);
  }

  @override
  Future<ll.LatLng?> geocodeAddress(String address) {
    if (pendurado) return Completer<ll.LatLng?>().future;
    for (final e in geocodes.entries) {
      if (address.startsWith(e.key)) return Future.value(e.value);
    }
    return Future.value(null);
  }

  @override
  void resetSession() {}

  @override
  void dispose() {}
}

Future<void> _escrever(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField), texto);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump();
}

Future<void> _tocar(WidgetTester tester, String rotulo) async {
  expect(find.text(rotulo), findsOneWidget);
  await tester.tap(find.text(rotulo));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  setUp(() => LocationService.applyLocationConsent(false));
  tearDown(() => LocationService.applyLocationConsent(true));

  group('1. resposta atrasada de uma sugestão anterior é deitada fora', () {
    testWidgets('Local do favor: escolhe A (lenta), muda para B → fica B',
        (tester) async {
      final lentoA = Completer<ll.LatLng?>();
      final svc = _Servico(
        predicoes: {
          'Rua do Com': const [_sugComercio],
          'Praça': const [_sugCamoes],
        },
        details: {'comercio': lentoA, 'camoes': _camoes},
      );
      final recebidos = <String>[];
      final ctrl = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BusinessAutocompleteField(
            controller: ctrl,
            includeAddresses: true,
            placesOverride: svc,
            onSelected: (n, c) => recebidos.add('$n@${c.latitude}'),
          ),
        ),
      ));

      await _escrever(tester, 'Rua do Com');
      await _tocar(tester, 'Rua do Comércio'); // Details de A fica a caminho
      await _escrever(tester, 'Praça');
      await _tocar(tester, 'Praça Luís de Camões');
      lentoA.complete(_comercioCentro); // A chega tarde
      await tester.pump();
      await tester.pump();

      expect(recebidos, ['Praça Luís de Camões, Guarda, Portugal@40.5389']);
      expect(ctrl.text, 'Praça Luís de Camões, Guarda, Portugal');
    });

    testWidgets('Local do favor: escolhe A (lenta) e escreve → nada chega',
        (tester) async {
      final lentoA = Completer<ll.LatLng?>();
      final svc = _Servico(
        predicoes: {'Rua do Com': const [_sugComercio]},
        details: {'comercio': lentoA},
      );
      final recebidos = <ll.LatLng>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BusinessAutocompleteField(
            controller: TextEditingController(),
            includeAddresses: true,
            placesOverride: svc,
            onSelected: (_, c) => recebidos.add(c),
          ),
        ),
      ));
      await _escrever(tester, 'Rua do Com');
      await _tocar(tester, 'Rua do Comércio');
      await _escrever(tester, 'Rua do Comércio 12 1º Esq');
      lentoA.complete(_comercioCentro);
      await tester.pump();
      await tester.pump();
      expect(recebidos, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'o "a carregar" desliga-se na mesma');
    });

    testWidgets('Onde entregar: escolhe A (lenta), muda para B → fica B',
        (tester) async {
      final lentoA = Completer<ll.LatLng?>();
      final svc = _Servico(
        predicoes: {
          'Rua do Com': const [_sugComercio],
          'Praça': const [_sugCamoes],
        },
        details: {'comercio': lentoA, 'camoes': _camoes},
      );
      final recebidos = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            controller: TextEditingController(),
            serviceOverride: svc,
            onSelected: (n, c) => recebidos.add('$n@${c?.latitude}'),
          ),
        ),
      ));
      await _escrever(tester, 'Rua do Com');
      await _tocar(tester, 'Rua do Comércio');
      await _escrever(tester, 'Praça');
      await _tocar(tester, 'Praça Luís de Camões');
      lentoA.complete(_comercioCentro);
      await tester.pump();
      await tester.pump();
      expect(recebidos, ['Praça Luís de Camões, Guarda, Portugal@40.5389']);
    });
  });

  group('2. morada escrita à mão: procura do TVDE com a Guarda à frente', () {
    test('"Rua do Comércio, Guarda": o Geocoding dá 11 km, fica a rua da cidade',
        () async {
      final svc = _Servico(
        geocodes: {'Rua do Comércio': _comercioLonge},
        predicoes: {'Rua do Comércio': const [_sugComercio]},
        details: {'comercio': _comercioCentro},
      );
      final r = await svc.procurarMoradaEscrita('Rua do Comércio, Guarda');
      expect(r?.coords, _comercioCentro);
      expect(kmDoCentroDaGuarda(_comercioLonge), greaterThan(10));
    });

    test('morada perto do centro fica a do Geocoding, sem ir às sugestões',
        () async {
      final svc = _Servico(
        geocodes: {'Rua do Comércio': _comercioCentro},
        predicoes: {'Rua do Comércio': const [_sugComercio]},
      );
      final r = await svc.procurarMoradaEscrita('Rua do Comércio, Guarda');
      expect(r?.coords, _comercioCentro);
      expect(svc.pedidosDeSugestoes, 0);
    });

    test('morada de aldeia não é trocada pela rua da cidade com outro nome',
        () async {
      final svc = _Servico(
        geocodes: {'Rua da Igreja': _goncalo},
        predicoes: {'Rua da Igreja': const [_sugIgrejaCidade]},
        details: {'igreja-cidade': _comercioCentro},
      );
      final r = await svc.procurarMoradaEscrita('Rua da Igreja, Gonçalo');
      expect(r?.coords, _goncalo);
    });

    test('Geocoding sem nada: fica a 1.ª sugestão da Guarda (comércio)',
        () async {
      final svc = _Servico(
        predicoes: {'Rua do Comércio': const [_sugComercio]},
        details: {'comercio': _comercioCentro},
      );
      final r = await svc.procurarMoradaEscrita('Rua do Comércio, Guarda');
      expect(r?.coords, _comercioCentro);
    });
  });

  group('3. rede pendurada: a escolha acaba em ~10 s', () {
    testWidgets('coordenadasDaSugestao devolve (null) até aos 10 s',
        (tester) async {
      final svc = _Servico(pendurado: true);
      ll.LatLng? r = const ll.LatLng(0, 0);
      var acabou = false;
      unawaited(svc.coordenadasDaSugestao(_sugComercio).then((c) {
        r = c;
        acabou = true;
      }));
      await tester.pump(const Duration(seconds: 9));
      expect(acabou, isFalse);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(acabou, isTrue);
      expect(r, isNull);
    });

    testWidgets('o campo do Local do favor não fica preso a carregar',
        (tester) async {
      final svc = _Servico(
        pendurado: true,
        predicoes: {'Rua do Com': const [_sugComercio]},
      );
      final recebidos = <ll.LatLng>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BusinessAutocompleteField(
            controller: TextEditingController(),
            includeAddresses: true,
            placesOverride: svc,
            onSelected: (_, c) => recebidos.add(c),
          ),
        ),
      ));
      await _escrever(tester, 'Rua do Com');
      await _tocar(tester, 'Rua do Comércio');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 10, milliseconds: 100));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(recebidos, isEmpty);
    });
  });
}
