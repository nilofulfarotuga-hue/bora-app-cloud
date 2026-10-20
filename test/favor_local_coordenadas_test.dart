// B1 (fechar-pendencias-2026-10-20) — Favor: a sugestão escolhida no "Local do
// favor" tem de levar as coordenadas DO SÍTIO (Place Details) até à cotação.
//
// Cicatriz (reel 17/10, web): "Rua do Comércio, Guarda, Portugal" — o Details
// deu 40.5389,-7.2680 (centro), a app deitou-o fora e geocodificou o TEXTO, que
// caiu a ~11 km (40.4993,-7.1458) → km extra: 20,74 € em vez de 14,00 €. No
// registo do places-proxy viu-se `detalhes` seguido logo de `geocode` com o
// texto da sugestão — o recurso ao texto disparava quando o Details falhava uma
// vez (resposta depois dos 8 s).
//
// Estes testes falham com o código de antes (o campo ficava com as coordenadas
// do texto) e passam com a correção (2.ª tentativa do Details).
import 'package:bora_app/services/location_service.dart';
import 'package:bora_app/services/place_autocomplete_service.dart';
import 'package:bora_app/utils/favor_passos.dart';
import 'package:bora_app/widgets/address_autocomplete_field.dart';
import 'package:bora_app/widgets/business_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

const _centro = ll.LatLng(40.5389, -7.2680); // Details da sugestão (certo)
const _longe = ll.LatLng(40.4993, -7.1458); // geocode do texto (~11 km)

const _sugestao = PlacePrediction(
  placeId: 'rua-do-comercio',
  description: 'Rua do Comércio, Guarda, Portugal',
  primaryText: 'Rua do Comércio',
  secondaryText: 'Guarda, Portugal',
);

/// Serviço falso: o Details falha nas primeiras [falhasDetails] chamadas
/// (como a resposta do proxy a chegar depois do limite) e depois responde o
/// sítio certo; o geocode do texto responde sempre o sítio errado.
class _ServicoFalso extends PlaceAutocompleteService {
  _ServicoFalso({this.falhasDetails = 1});

  final int falhasDetails;
  int chamadasDetails = 0;
  final List<String> geocodes = [];

  @override
  Future<List<PlacePrediction>> fetchPredictions(String input) async =>
      const [_sugestao];

  @override
  Future<ll.LatLng?> resolvePlaceLocation(String placeId) async {
    chamadasDetails++;
    if (chamadasDetails <= falhasDetails) return null;
    return _centro;
  }

  @override
  Future<ll.LatLng?> geocodeAddress(String address) async {
    geocodes.add(address);
    return _longe;
  }

  @override
  void resetSession() {}

  @override
  void dispose() {}
}

Future<void> _escreverETocar(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Rua do Com');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump();
  expect(find.text('Rua do Comércio'), findsOneWidget);
  await tester.tap(find.text('Rua do Comércio'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  setUp(() => LocationService.applyLocationConsent(false)); // sem GPS no teste
  tearDown(() => LocationService.applyLocationConsent(true));

  group('Local do favor (BusinessAutocompleteField)', () {
    testWidgets(
        'Details falha uma vez → fica a posição do Details, não a do texto',
        (tester) async {
      final svc = _ServicoFalso(falhasDetails: 1);
      ll.LatLng? recebido;
      String? texto;
      final ctrl = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BusinessAutocompleteField(
            controller: ctrl,
            includeAddresses: true,
            placesOverride: svc,
            onSelected: (n, c) {
              texto = n;
              recebido = c;
            },
          ),
        ),
      ));

      await _escreverETocar(tester);

      expect(recebido, _centro,
          reason: 'as coordenadas da sugestão (Details) mandam na cotação');
      expect(texto, 'Rua do Comércio, Guarda, Portugal');
      expect(ctrl.text, 'Rua do Comércio, Guarda, Portugal');
      expect(svc.geocodes, isEmpty,
          reason: 'nunca geocodificar o texto por cima do Details');
    });

    testWidgets('Details falha sempre → último recurso é o texto (não prende)',
        (tester) async {
      final svc = _ServicoFalso(falhasDetails: 99);
      ll.LatLng? recebido;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BusinessAutocompleteField(
            controller: TextEditingController(),
            includeAddresses: true,
            placesOverride: svc,
            onSelected: (_, c) => recebido = c,
          ),
        ),
      ));

      await _escreverETocar(tester);

      expect(svc.chamadasDetails, greaterThanOrEqualTo(2),
          reason: 'duas tentativas do Details antes do texto');
      expect(svc.geocodes, isNotEmpty);
      expect(recebido, isNotNull);
    });
  });

  group('Onde entregar / paragem em casa (AddressAutocompleteField)', () {
    testWidgets(
        'Details falha uma vez → fica a posição do Details, não a do texto',
        (tester) async {
      final svc = _ServicoFalso(falhasDetails: 1);
      ll.LatLng? recebido;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AddressAutocompleteField(
            controller: TextEditingController(),
            serviceOverride: svc,
            onSelected: (_, c) => recebido = c,
          ),
        ),
      ));

      await _escreverETocar(tester);

      expect(recebido, _centro);
      expect(svc.geocodes, isEmpty);
    });
  });

  group('O ecrã do Favor não apaga as coordenadas com o eco da seleção', () {
    const escolhido = 'Rua do Comércio, Guarda, Portugal';

    test('eco com o mesmo texto (ou com espaços) mantém as coordenadas', () {
      expect(coordenadasDoLocalContinuam(escolhido, escolhido), isTrue);
      expect(coordenadasDoLocalContinuam(escolhido, '$escolhido '), isTrue);
    });

    test('o cliente muda o texto → as coordenadas antigas deixam de valer', () {
      expect(coordenadasDoLocalContinuam(escolhido, 'Rua do Comércio, Gua'),
          isFalse);
      expect(coordenadasDoLocalContinuam(escolhido, 'Rua do Comércio 12'),
          isFalse);
      expect(coordenadasDoLocalContinuam(escolhido, ''), isFalse);
    });

    test('sem sugestão escolhida não há coordenadas a guardar', () {
      expect(coordenadasDoLocalContinuam(null, escolhido), isFalse);
      expect(coordenadasDoLocalContinuam('', ''), isFalse);
    });
  });
}
