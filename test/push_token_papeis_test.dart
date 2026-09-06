import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/push_token_service.dart';

/// O buraco medido a 2026-08-28: o token de notificação só era guardado para
/// motorista, estafeta e cliente. A LIMPEZA estava no ar e **nunca conseguiu
/// chamar ninguém**, porque nenhum faxineiro tinha aparelho registado — e nem
/// sequer havia caminho antigo, já que `cleaners` e `washers` não têm coluna
/// `fcm_token` como `drivers` tem.
void main() {
  group('papeisComPush — quem pode ser chamado', () {
    test('o faxineiro e o lavador entram', () {
      expect(PushTokenService.papeisComPush, contains('cleaner'));
      expect(PushTokenService.papeisComPush, contains('washer'));
    });

    test('os três antigos continuam lá — não se partiu nada', () {
      expect(PushTokenService.papeisComPush, containsAll(
          <String>['client', 'driver', 'partner']));
    });

    test('esta lista tem de bater certo com a RPC register_push_token', () {
      // Se divergirem, um lado rejeita em silêncio e ninguém dá por isso —
      // foi assim que o faxineiro ficou mudo durante meses. A migration
      // 20260828120000 aceita exactamente estes cinco.
      expect(
        PushTokenService.papeisComPush,
        equals(<String>{'client', 'driver', 'partner', 'cleaner', 'washer'}),
      );
    });

    test('um papel inventado não entra', () {
      expect(PushTokenService.papeisComPush, isNot(contains('admin')));
      expect(PushTokenService.papeisComPush, isNot(contains('faxineiro')));
    });
  });

  group('tabelaDoPapel — o registo tem de dizer a verdade', () {
    test('os papéis antigos apontam para a tabela própria de cada um', () {
      expect(PushTokenService.tabelaDoPapel('client'), 'client_push_tokens');
      expect(PushTokenService.tabelaDoPapel('driver'), 'driver_push_tokens');
      expect(PushTokenService.tabelaDoPapel('partner'), 'partner_push_tokens');
    });

    test('os de prestador partilham a tabela, distinguidos pela coluna', () {
      // O log antigo dizia "cleaner_push_tokens", uma tabela que não existe.
      expect(PushTokenService.tabelaDoPapel('cleaner'),
          'provider_push_tokens (role=cleaner)');
      expect(PushTokenService.tabelaDoPapel('washer'),
          'provider_push_tokens (role=washer)');
    });

    test('nenhum papel com push fica sem destino escrito', () {
      for (final p in PushTokenService.papeisComPush) {
        expect(PushTokenService.tabelaDoPapel(p), isNotEmpty, reason: p);
      }
    });
  });
}
