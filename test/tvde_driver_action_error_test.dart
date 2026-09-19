import 'dart:async';

import 'package:bora_app/models/tvde_driver_action_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Fix botão preso 2026-08-20]
///
/// O defeito: quando a acção do motorista falhava, o ecrã mostrava o erro cru
/// (`Não foi possível: PostgrestException(...)`) e ficava exactamente onde
/// estava. Se a RPC nem respondia, o botão girava para sempre.
///
/// Estes testes usam as formas de erro **reais**, não inventadas. A do
/// `ride_not_found` foi arrancada da produção a 2026-08-20:
/// ```
/// select public.tvde_driver_arrived('00000000-0000-0000-0000-000000000000');
/// ERROR:  P0001: ride_not_found
/// ```
void main() {
  group('mensagem que o motorista lê', () {
    test('corrida que já não existe → diz isso, sem jargão', () {
      // Como o supabase_flutter embrulha o P0001 acima.
      final erro = Exception(
          'PostgrestException(message: ride_not_found, code: P0001, '
          'details: Internal Server Error, hint: null)');

      expect(mensagemDeFalhaDeAcao(erro), 'Esta corrida já não existe.');
    });

    test('corrida já não é dele → diz isso', () {
      final erro = Exception(
          'PostgrestException(message: not_ride_driver, code: P0001, '
          'details: Internal Server Error, hint: null)');

      expect(mensagemDeFalhaDeAcao(erro),
          'Esta corrida já não está atribuída a ti.');
    });

    test('servidor não responde → explica a demora e manda tentar de novo', () {
      final msg = mensagemDeFalhaDeAcao(TimeoutException('rpc', const Duration(seconds: 12)));

      expect(msg, contains('demorou demasiado'));
      expect(msg, contains('tenta outra vez'));
    });

    test('sem rede → manda verificar a ligação', () {
      final erro = Exception(
          "ClientException with SocketException: Failed host lookup: "
          "'ojykpzwqrtusfeakzrna.supabase.co'");

      expect(mensagemDeFalhaDeAcao(erro),
          'Sem ligação à internet. Verifica a rede e tenta outra vez.');
    });

    test('erro desconhecido → frase útil, nunca o erro cru', () {
      final msg = mensagemDeFalhaDeAcao(StateError('boom qualquer'));

      expect(msg,
          'Não consegui concluir. Verifica o estado da corrida e tenta outra vez.');
      expect(msg, isNot(contains('boom')));
    });

    test('NENHUMA mensagem deixa escapar jargão técnico', () {
      final erros = <Object>[
        Exception('PostgrestException(message: ride_not_found, code: P0001)'),
        Exception('PostgrestException(message: not_ride_driver, code: P0001)'),
        TimeoutException('rpc', const Duration(seconds: 12)),
        Exception('ClientException with SocketException: Failed host lookup'),
        StateError('Resposta inesperada da RPC: null'),
      ];

      for (final e in erros) {
        final msg = mensagemDeFalhaDeAcao(e);
        for (final proibido in const [
          'Exception',
          'PostgrestException',
          'SocketException',
          'P0001',
          'RPC',
          'null',
        ]) {
          expect(msg, isNot(contains(proibido)),
              reason: 'a frase "$msg" deixa escapar "$proibido"');
        }
      }
    });
  });

  group('quando o ecrã tem de sair', () {
    test('corrida inexistente fecha o ecrã', () {
      expect(
          falhaFechaOEcra(Exception(
              'PostgrestException(message: ride_not_found, code: P0001)')),
          isTrue);
    });

    test('corrida de outro motorista fecha o ecrã', () {
      expect(
          falhaFechaOEcra(Exception(
              'PostgrestException(message: not_ride_driver, code: P0001)')),
          isTrue);
    });

    test('falha de rede NÃO fecha o ecrã — a corrida pode estar viva', () {
      expect(
          falhaFechaOEcra(
              Exception('ClientException with SocketException: Failed host lookup')),
          isFalse);
    });

    test('timeout NÃO fecha o ecrã — a acção pode ter-se aplicado', () {
      expect(
          falhaFechaOEcra(
              TimeoutException('rpc', const Duration(seconds: 12))),
          isFalse);
    });
  });
}
