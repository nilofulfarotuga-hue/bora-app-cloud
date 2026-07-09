// Teste determinístico da LÓGICA de viés geográfico do autocomplete (Guarda),
// exercitando o serviço io real com um http.Client falso — SEM rede, SEM device.
//
// Porquê este teste existe: o teste de widget (address_autocomplete_field_test)
// usa um serviço MOCK e por isso NUNCA tocou na lógica onde o bug real vivia
// (retry "<query> Guarda", fallback sem viés, rerank Guarda-primeiro). Foi
// exactamente esse o buraco: "aprovado só com teste web, não pegou o erro real".
// Aqui reproduzimos os dois cenários que o Danilo viu no telemóvel:
//   1) "Continente" → Google devolve Continentes de OUTRAS cidades e o da Guarda
//      nem aparece → o serviço tem de disparar "Continente Guarda" e pô-lo em 1.º.
//   2) "Lavie" → Google devolve VAZIO (comércio local mal indexado) → o serviço
//      tem de disparar "Lavie Guarda" e devolver o LaVie Shopping.
import 'dart:convert';

import 'package:bora_app/services/place_autocomplete_service_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _ok(List<Map<String, dynamic>> predictions) => http.Response(
      jsonEncode(<String, dynamic>{'status': 'OK', 'predictions': predictions}),
      200,
    );

http.Response _zero() => http.Response(
      jsonEncode(<String, dynamic>{'status': 'ZERO_RESULTS', 'predictions': <dynamic>[]}),
      200,
    );

Map<String, dynamic> _pred(String id, String desc, String secondary) =>
    <String, dynamic>{
      'place_id': id,
      'description': desc,
      'structured_formatting': <String, dynamic>{
        'main_text': desc.split(',').first,
        'secondary_text': secondary,
      },
      'types': <String>['establishment'],
    };

void main() {
  test('"Continente": outra cidade em 1.º → serviço puxa o da Guarda para o topo',
      () async {
    final client = MockClient((request) async {
      final input = request.url.queryParameters['input'] ?? '';
      // 1.ª chamada (viés suave): só Continentes de cidades maiores, SEM Guarda.
      if (input == 'Continente') {
        return _ok(<Map<String, dynamic>>[
          _pred('lx', 'Continente, Lisboa', 'Lisboa'),
          _pred('pt', 'Continente, Porto', 'Porto'),
        ]);
      }
      // Retry explícito "<query> Guarda" — é isto que garante o resultado local.
      if (input == 'Continente Guarda') {
        return _ok(<Map<String, dynamic>>[
          _pred('gd', 'Continente Bom Dia, Guarda', 'Guarda'),
        ]);
      }
      return _zero();
    });

    final service = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    final result = await service.fetchPredictions('Continente');

    expect(result, isNotEmpty);
    // O da Guarda tem de ficar em PRIMEIRO (rerank determinístico).
    expect(result.first.description.toLowerCase(), contains('guarda'));
    // ...sem excluir os das outras cidades (viés suave, não filtro).
    expect(result.length, greaterThanOrEqualTo(2));
    expect(
      result.any((p) => p.description.contains('Lisboa')),
      isTrue,
      reason: 'resultados de outras cidades não devem ser eliminados',
    );
  });

  test('"Lavie": Google devolve VAZIO → serviço tenta "Lavie Guarda" e acha o shopping',
      () async {
    final client = MockClient((request) async {
      final input = request.url.queryParameters['input'] ?? '';
      if (input == 'Lavie') return _zero(); // comércio local mal indexado
      if (input == 'Lavie Guarda') {
        return _ok(<Map<String, dynamic>>[
          _pred('lv', 'LaVie Guarda Shopping, Guarda', 'Guarda'),
        ]);
      }
      return _zero();
    });

    final service = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    final result = await service.fetchPredictions('Lavie');

    expect(result, isNotEmpty, reason: 'nunca deixar um negócio local válido sem resultado');
    expect(result.first.description.toLowerCase(), contains('guarda'));
    expect(result.first.description.toLowerCase(), contains('lavie'));
  });

  test('Cobertura nacional: se nem "<query> Guarda" acha nada, faz fallback sem viés',
      () async {
    var chamadasSemVies = 0;
    final client = MockClient((request) async {
      final temVies = request.url.queryParameters.containsKey('location');
      if (!temVies) {
        chamadasSemVies++;
        return _ok(<Map<String, dynamic>>[
          _pred('nac', 'Negócio Raro, Lisboa', 'Lisboa'),
        ]);
      }
      return _zero(); // viés (com e sem " Guarda") não devolve nada
    });

    final service = createPlaceAutocompleteServiceForTest('FAKE_KEY', client);
    final result = await service.fetchPredictions('NegocioRaro');

    expect(chamadasSemVies, greaterThanOrEqualTo(1),
        reason: 'tem de existir um retry SEM viés como última cobertura');
    expect(result, isNotEmpty);
  });
}
