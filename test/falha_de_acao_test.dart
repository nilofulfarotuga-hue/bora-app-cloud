import 'dart:async';

import 'package:bora_app/models/falha_de_acao.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Fix botão preso 2026-08-20]
///
/// O defeito: quando uma acção falhava, o ecrã mostrava o erro cru
/// (`Erro: PostgrestException(...)`, ou pior, `Erro: desconhecido`) e ficava
/// exactamente onde estava. Se a chamada nem respondia, o botão girava para
/// sempre.
///
/// As marcas usadas aqui **não foram inventadas** — saíram de um varrimento às
/// funções em produção a 2026-08-20 (`RAISE EXCEPTION '<marca>'`), e a do
/// `ride_not_found` foi confirmada ao vivo:
/// ```
/// select public.tvde_driver_arrived('00000000-0000-0000-0000-000000000000');
/// ERROR:  P0001: ride_not_found
/// ```
void main() {
  /// Como o supabase_flutter embrulha um `RAISE EXCEPTION 'marca'`.
  Object doServidor(String marca) => Exception(
      'PostgrestException(message: $marca, code: P0001, '
      'details: Internal Server Error, hint: null)');

  group('cada domínio fala a sua língua', () {
    test('"já não existe" usa o nome certo e o género certo', () {
      expect(
          mensagemDeFalhaDeAcao(doServidor('ride_not_found'),
              trabalho: TrabalhoEmCurso.corrida),
          'Esta corrida já não existe.');
      expect(
          mensagemDeFalhaDeAcao(doServidor('booking_not_found'),
              trabalho: TrabalhoEmCurso.limpeza),
          'Esta limpeza já não existe.');
      expect(
          mensagemDeFalhaDeAcao(doServidor('appointment_not_found'),
              trabalho: TrabalhoEmCurso.marcacao),
          'Esta marcação já não existe.');
      expect(
          mensagemDeFalhaDeAcao(doServidor('reservation_not_found'),
              trabalho: TrabalhoEmCurso.reserva),
          'Esta reserva já não existe.');
    });

    test('o pedido é masculino — "Este pedido", "atribuído"', () {
      expect(
          mensagemDeFalhaDeAcao(doServidor('ride_not_found'),
              trabalho: TrabalhoEmCurso.pedido),
          'Este pedido já não existe.');
      expect(
          mensagemDeFalhaDeAcao(doServidor('not_ride_driver'),
              trabalho: TrabalhoEmCurso.pedido),
          'Este pedido já não está atribuído a ti.');
    });

    test('a corrida é feminina — "atribuída"', () {
      expect(
          mensagemDeFalhaDeAcao(doServidor('not_ride_driver'),
              trabalho: TrabalhoEmCurso.corrida),
          'Esta corrida já não está atribuída a ti.');
    });
  });

  group('famílias de erro do servidor', () {
    test('outra pessoa chegou primeiro', () {
      for (final marca in const [
        'ride_already_taken',
        'offer_no_longer_valid',
        'offer_not_yours_or_expired',
      ]) {
        expect(
            mensagemDeFalhaDeAcao(doServidor(marca),
                trabalho: TrabalhoEmCurso.corrida),
            'Já não está disponível — outra pessoa chegou primeiro.',
            reason: marca);
      }
    });

    test('sessão perdida manda entrar outra vez', () {
      for (final marca in const ['not_authenticated', 'auth_required']) {
        expect(
            mensagemDeFalhaDeAcao(doServidor(marca),
                trabalho: TrabalhoEmCurso.pedido),
            'A tua sessão terminou. Entra outra vez para continuar.',
            reason: marca);
      }
    });

    test('estado mudou por baixo → manda atualizar', () {
      expect(
          mensagemDeFalhaDeAcao(doServidor('invalid_status'),
              trabalho: TrabalhoEmCurso.limpeza),
          contains('já não está nesse estado'));
    });

    test('sem rede → manda verificar a ligação', () {
      final erro = Exception(
          "ClientException with SocketException: Failed host lookup: "
          "'ojykpzwqrtusfeakzrna.supabase.co'");
      expect(
          mensagemDeFalhaDeAcao(erro, trabalho: TrabalhoEmCurso.corrida),
          'Sem ligação à internet. Verifica a rede e tenta outra vez.');
    });

    test('servidor não responde → explica a demora, nomeando o trabalho', () {
      final msg = mensagemDeFalhaDeAcao(
          TimeoutException('rpc', kAcaoTimeout),
          trabalho: TrabalhoEmCurso.pedido);
      expect(msg, contains('demorou demasiado'));
      expect(msg, contains('o pedido'));
      expect(msg, contains('tenta outra vez'));
    });
  });

  group('o que o estafeta via antes', () {
    test('o antigo "Erro: desconhecido" passa a frase útil', () {
      // Era isto: 'Erro: ${orderStore.lastUpdateError ?? "desconhecido"}'.
      // Sem erro nenhum guardado, o estafeta lia literalmente "desconhecido".
      final msg = mensagemDeFalhaDeAcao('', trabalho: TrabalhoEmCurso.pedido);

      expect(msg,
          'Não consegui concluir. Verifica o pedido e tenta outra vez.');
      expect(msg, isNot(contains('desconhecido')));
    });
  });

  group('nunca escapa jargão', () {
    test('nenhuma mensagem, em nenhum domínio, deixa passar termos técnicos',
        () {
      final erros = <Object>[
        doServidor('ride_not_found'),
        doServidor('booking_not_yours'),
        doServidor('not_authenticated'),
        doServidor('invalid_status'),
        TimeoutException('rpc', kAcaoTimeout),
        Exception('ClientException with SocketException: Failed host lookup'),
        StateError('Resposta inesperada da RPC: null'),
        '',
      ];

      for (final trabalho in TrabalhoEmCurso.values) {
        for (final e in erros) {
          final msg = mensagemDeFalhaDeAcao(e, trabalho: trabalho);
          for (final proibido in const [
            'Exception',
            'PostgrestException',
            'SocketException',
            'StateError',
            'P0001',
            'RPC',
            'null',
            'desconhecido',
          ]) {
            expect(msg, isNot(contains(proibido)),
                reason: '[$trabalho] "$msg" deixa escapar "$proibido"');
          }
          expect(msg, isNot(isEmpty), reason: '[$trabalho] mensagem vazia');
        }
      }
    });
  });

  group('quando o ecrã tem de sair', () {
    test('já não existe / já não é teu / já foi tirado → sai', () {
      for (final marca in const [
        'ride_not_found',
        'booking_not_found',
        'appointment_not_found',
        'reservation_not_found',
        'not_ride_driver',
        'booking_not_yours',
        'not_your_appointment',
        'ride_already_taken',
      ]) {
        expect(falhaFechaOEcra(doServidor(marca)), isTrue, reason: marca);
      }
    });

    test('rede e timeout NÃO fecham — a acção pode ter-se aplicado', () {
      expect(
          falhaFechaOEcra(
              Exception('ClientException with SocketException: host lookup')),
          isFalse);
      expect(falhaFechaOEcra(TimeoutException('rpc', kAcaoTimeout)), isFalse);
    });

    test('sessão perdida não fecha o ecrã — quem trata disso é o login', () {
      expect(falhaFechaOEcra(doServidor('not_authenticated')), isFalse);
    });
  });

  group('o tecto de tempo', () {
    test('está entre 10 e 15 segundos, como foi pedido', () {
      expect(kAcaoTimeout.inSeconds, greaterThanOrEqualTo(10));
      expect(kAcaoTimeout.inSeconds, lessThanOrEqualTo(15));
    });
  });
}
