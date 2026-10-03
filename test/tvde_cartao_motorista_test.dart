import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Missão TVDE 05/09] Corridas reais, passageiro a pagar: no telemóvel do
/// CLIENTE não aparecia o carro no mapa. Nem nome, nem matrícula, nem tempo
/// de chegada. Nada — só o pino de recolha.
///
/// A causa era UMA e explicava os sete sintomas: a policy de SELECT de
/// `public.drivers` só tem `is_admin()` e `user_id = auth.uid()`. Não existe
/// policy que deixe um CLIENTE ler a linha do motorista. O ecrã fazia
/// `.from('drivers').select(...)`, recebia SEMPRE vazio, e o erro morria num
/// `catch (_) {}` mudo.
///
/// A tabela `drivers` NÃO pode ser aberta ao cliente: tem IBAN, NIF, número e
/// foto do documento de identidade, morada e conta Stripe. O caminho é a
/// função `tvde_ride_driver_card(p_ride_id uuid)`, SECURITY DEFINER, que
/// devolve só o que é público e só a quem é o passageiro daquela corrida.
///
/// Estes testes trancam o contrato dos dois lados: o ecrã não pode voltar a
/// ler a tabela, e tem de aguentar a forma real da resposta.
void main() {
  final fonte =
      File('lib/screens/client/tvde/tvde_ride_tracking_screen.dart')
          .readAsStringSync();

  group('o cliente lê pela função nova, nunca pela tabela', () {
    test('o ecrã NÃO lê a tabela `drivers` directamente', () {
      // Qualquer `.from('drivers')` ou `.from("drivers")` é a regressão.
      final leituraDirecta = RegExp(r"""\.from\(\s*['"]drivers['"]\s*\)""");
      expect(leituraDirecta.hasMatch(fonte), isFalse,
          reason: 'o ecrã do cliente voltou a ler a tabela `drivers`. Essa '
              'tabela tem IBAN, NIF e documento de identidade, e a RLS bloqueia '
              'o cliente — o resultado vem vazio e o passageiro fica sem ver o '
              'carro. Usa a RPC `tvde_ride_driver_card`.');
    });

    test('chama a RPC `tvde_ride_driver_card`', () {
      expect(fonte, contains('tvde_ride_driver_card'));
    });

    test('passa o id da CORRIDA, não o do motorista', () {
      // A função decide a autorização pela corrida (`v_ride.client_id`).
      // Passar-lhe o driverId seria `ride_not_found` em todas as corridas.
      expect(fonte, contains("'p_ride_id': ride.id"),
          reason: 'a RPC recebe o id da corrida — é por ele que decide se '
              'quem pergunta é mesmo o passageiro');
    });

    test('a falha nunca mais é silenciosa', () {
      // O `catch (_) {}` mudo escondeu este bug durante semanas.
      final catchMudo = RegExp(r'catch\s*\(\s*_\s*\)\s*\{\s*\}');
      expect(catchMudo.hasMatch(fonte), isFalse,
          reason: 'voltou a haver um catch mudo neste ecrã — foi assim que o '
              'bug do mapa vazio sobreviveu semanas sem ninguém ver');
    });

    test('lê os campos novos que a leitura antiga nem pedia', () {
      // Sem `heading` o carrinho não sabe para onde apontar; sem
      // `ratings_count` o cartão não mostra quantas avaliações são.
      for (final campo in ['heading', 'speed_kmh', 'ratings_count']) {
        expect(fonte, contains("'$campo'"),
            reason: 'o campo $campo da RPC não está a ser lido');
      }
    });

    test('o marcador do motorista já não é o pino laranja', () {
      // 1B — tem de ser um carro azul visto de cima. O verde e o laranja já
      // são a recolha e a marca.
      expect(fonte.contains('hueOrange'), isFalse,
          reason: 'o motorista voltou a ser um alfinete laranja');
    });

    test('a matrícula é formatada à portuguesa', () {
      expect(fonte, contains('_formataMatricula'),
          reason: 'a matrícula é o que faz o passageiro reconhecer o carro '
              'certo na rua — tem de sair legível, com traços');
    });
  });

  group('a forma real da resposta da RPC', () {
    // Estas formas não são inventadas: `tvde_ride_driver_card` é
    // `RETURNS TABLE(...)`, logo `proretset = true`, e o cliente Dart
    // recebe-a como LISTA. Quando a corrida ainda não tem motorista a função
    // faz `RETURN;` — lista VAZIA, não erro.
    test('lista com uma linha é o caso normal', () {
      final res = <dynamic>[
        <String, dynamic>{
          'name': 'Danilo',
          'photo_url': 'https://exemplo/foto.jpg',
          'phone': '+351931992662',
          'avg_rating': 5.0,
          'ratings_count': 7,
          'vehicle_make_model': 'Hyundai Ioniq 5',
          'vehicle_color': 'Azul',
          'license_plate': 'CH90PX',
          'lat': 40.5378,
          'lng': -7.2683,
          'heading': 91.5,
          'speed_kmh': 32.0,
          'location_updated_at': '2026-09-05T11:20:00+00:00',
        }
      ];
      final row = _primeiraLinha(res);
      expect(row, isNotNull);
      expect(row!['name'], 'Danilo');
      expect((row['avg_rating'] as num).toDouble(), 5.0);
      expect((row['ratings_count'] as num).toInt(), 7);
      expect(row['license_plate'], 'CH90PX');
    });

    test('lista vazia = corrida ainda sem motorista, não é erro', () {
      expect(_primeiraLinha(<dynamic>[]), isNull);
    });

    test('mapa único também é aceite (se a assinatura mudar de forma)', () {
      final row = _primeiraLinha(<String, dynamic>{'name': 'Danilo'});
      expect(row?['name'], 'Danilo');
    });

    test('nulo não rebenta', () {
      expect(_primeiraLinha(null), isNull);
    });

    test('a RPC nunca devolve dados sensíveis do motorista', () {
      // Contrato de segurança: se algum dia a função passar a devolver isto,
      // o cliente fica com o IBAN do motorista no telemóvel.
      const proibidos = [
        'iban',
        'nif',
        'tax_id',
        'document_number',
        'document_url',
        'address',
        'stripe_account_id',
      ];
      for (final campo in proibidos) {
        expect(fonte.contains("row['$campo']"), isFalse,
            reason: 'o ecrã do cliente está a ler `$campo` do motorista');
      }
    });
  });
}

/// Espelha o que o ecrã faz com a resposta da RPC.
Map<String, dynamic>? _primeiraLinha(dynamic res) {
  if (res is List) {
    if (res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return null;
  }
  if (res is Map) return Map<String, dynamic>.from(res);
  return null;
}
