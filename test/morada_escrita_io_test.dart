// Missão tvde-pedir-nunca-trava-2026-10-14 — caminho Android/iOS.
//
// No telemóvel, a morada escrita à mão vai ao Geocoding da Google por HTTP
// (serviço io). Este teste exercita esse serviço REAL com um cliente HTTP
// falso: pede com a caixa da Guarda, fica com a rua na Guarda, recusa "a
// cidade inteira", recusa a mesma rua noutra cidade quando se escreveu
// "Guarda", e a cascata tolerante chega à avenida da Stela.
import 'dart:convert';

import 'package:bora_app/services/place_autocomplete_service_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _res(String morada, double lat, double lng,
        List<String> tipos) =>
    <String, dynamic>{
      'formatted_address': morada,
      'types': tipos,
      'geometry': <String, dynamic>{
        'location': <String, dynamic>{'lat': lat, 'lng': lng},
      },
    };

http.Response _geo(List<Map<String, dynamic>> results) => http.Response(
      jsonEncode(<String, dynamic>{
        'status': results.isEmpty ? 'ZERO_RESULTS' : 'OK',
        'results': results,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('pede com a caixa da Guarda e fica com a rua na Guarda (não a cidade)',
      () async {
    Uri? pedido;
    final client = MockClient((request) async {
      pedido = request.url;
      return _geo([
        _res('Guarda, Portugal', 40.537, -7.265, ['locality', 'political']),
        _res('Rua Direita 3, Viseu, Portugal', 40.66, -7.91, ['street_address']),
        _res('Rua Direita 3, 6300-700 Guarda, Portugal', 40.538, -7.267,
            ['street_address']),
      ]);
    });
    final s = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    final r = await s.geocodeComMorada('Rua Direita 3, Guarda');

    expect(pedido!.queryParameters['bounds'], isNotNull,
        reason: 'o Geocoding tem de ir com a caixa da Guarda como viés');
    expect(pedido!.queryParameters['components'], 'country:PT');
    expect(r, isNotNull);
    expect(r!.morada, 'Rua Direita 3, 6300-700 Guarda, Portugal');
    expect(r.coords.latitude, closeTo(40.538, 0.0001));
  });

  test('escreveu "Guarda" e o Google só tem a rua em Lisboa → sem resultado',
      () async {
    final client = MockClient((_) async => _geo([
          _res('Av. Rainha Dona Amélia 14, Lisboa, Portugal', 38.71, -9.14,
              ['street_address']),
        ]));
    final s = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    expect(await s.geocodeComMorada('Av. Rainha D. Amélia 14, Guarda'), isNull);
  });

  test('cascata tolerante: a morada da Stela chega à avenida', () async {
    final pedidos = <String>[];
    final client = MockClient((request) async {
      final morada = request.url.queryParameters['address'] ?? '';
      pedidos.add(morada);
      if (morada == 'Avenida Cidade de Safed, Guarda') {
        return _geo([
          _res('Av. Cidade de Safed, 6300-537 Guarda, Portugal', 40.5399,
              -7.2580, ['route']),
        ]);
      }
      return _geo(const []);
    });
    final s = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    final r = await s.geocodeTolerante('Av. Cidade de Safed n8 a 1d, Guarda');

    expect(pedidos.first, 'Av. Cidade de Safed n8 a 1d, Guarda');
    expect(pedidos.last, 'Avenida Cidade de Safed, Guarda');
    expect(r?.morada, 'Av. Cidade de Safed, 6300-537 Guarda, Portugal');
  });
}
