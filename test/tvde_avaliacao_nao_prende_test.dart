import 'dart:io';

import 'package:bora_app/services/pending_rating_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [Missão TVDE 05/09] Corrida real, passageiro a pagar: no fim, o cliente
/// ficou PRESO no ecrã de avaliação. Carregou em "Enviar avaliação" e não
/// aconteceu nada. Só saiu porque carregou em "Agora não".
///
/// A causa não era o envio — era o botão estar morto ANTES de ser tocado:
/// `BoraPrimaryButton(loading: store.busy, ...)` e, lá dentro,
/// `onPressed: loading ? null : onPressed`. O `busy` do `TvdeStore` é um flag
/// GLOBAL ÚNICO, mexido por dezenas de operações — bastava um refresh ou um
/// poll a meio para o botão ficar a rodar para sempre. O "Agora não" era um
/// `TextButton` sem essa dependência: por isso é que esse funcionava.
///
/// Dois grupos de testes:
///  1. regressão mecânica sobre o código-fonte dos dois ecrãs de avaliação —
///     é o que impede alguém de voltar a ligar o botão ao estado global;
///  2. a fila de reenvio — a avaliação nunca se perde nem prende a pessoa.
void main() {
  group('o botão de avaliar não pode depender do estado global do store', () {
    final ecrans = <String, String>{
      'cliente avalia o motorista':
          'lib/screens/client/tvde/tvde_rate_screen.dart',
      'motorista avalia o passageiro':
          'lib/screens/driver/tvde/tvde_driver_rate_screen.dart',
    };

    for (final entry in ecrans.entries) {
      group(entry.key, () {
        final fonte = File(entry.value).readAsStringSync();

        test('não passa um `busy` global ao botão', () {
          // Apanha `loading: store.busy`, `loading: s.busy`, `loading:
          // context.watch<X>().busy` e afins — qualquer `.busy` no `loading:`.
          final ligadoAoGlobal =
              RegExp(r'loading:\s*[A-Za-z_][\w.<>()]*\.busy');
          expect(ligadoAoGlobal.hasMatch(fonte), isFalse,
              reason: 'ficheiro ${entry.value}: o botão de enviar a avaliação '
                  'voltou a depender do `busy` global do store. Foi isto que '
                  'prendeu um cliente real a 05/09/2026. Usa um estado de '
                  'envio LOCAL do próprio ecrã.');
        });

        test('tem estado de envio próprio, local', () {
          expect(fonte, contains('_sending'),
              reason: 'ficheiro ${entry.value}: falta o guarda local de envio');
          expect(RegExp(r'loading:\s*_sending').hasMatch(fonte), isTrue,
              reason: 'ficheiro ${entry.value}: o botão tem de travar no '
                  'próprio pedido, não no do store');
        });

        test('o botão físico de voltar do Android sai do ecrã', () {
          // `PopScope` (não o `WillPopScope`, que está deprecado).
          expect(fonte, contains('PopScope'),
              reason: 'ficheiro ${entry.value}: um ecrã de fim de fluxo tem de '
                  'ter saída sempre viva, incluindo o botão físico');
          expect(fonte.contains('WillPopScope'), isFalse,
              reason: 'ficheiro ${entry.value}: WillPopScope está deprecado');
        });

        test('o envio tem timeout — nunca fica a rodar para sempre', () {
          expect(fonte, contains('.timeout('),
              reason: 'ficheiro ${entry.value}: sem timeout, uma RPC que não '
                  'responde prende a pessoa no ecrã');
        });

        test('uma falha de envio não impede a saída', () {
          expect(fonte, contains('PendingRatingQueue'),
              reason: 'ficheiro ${entry.value}: a avaliação que falha tem de '
                  'ir para a fila de reenvio, e o ecrã fecha na mesma');
        });
      });
    }
  });

  group('fila de reenvio — a avaliação não se perde nem prende ninguém', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('guarda uma avaliação que falhou', () async {
      final ok = await PendingRatingQueue.save(
        kind: PendingRatingQueue.kindDriver,
        rideId: 'r1',
        stars: 5,
        comment: 'boa viagem',
      );
      expect(ok, isTrue);

      final enviadas = <String>[];
      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver,
          (rideId, stars, comment) async {
        enviadas.add('$rideId|$stars|$comment');
      });
      expect(enviadas, ['r1|5|boa viagem']);
    });

    test('o que passou sai da fila e não é reenviado', () async {
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r1', stars: 4);

      var vezes = 0;
      Future<void> enviar(String _, int __, String? ___) async => vezes++;

      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver, enviar);
      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver, enviar);
      expect(vezes, 1, reason: 'reenviou uma avaliação já entregue');
    });

    test('o que falha fica para a próxima', () async {
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r1', stars: 3);

      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver,
          (_, __, ___) async => throw Exception('sem rede'));

      final segundaVolta = <String>[];
      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver,
          (rideId, _, __) async => segundaVolta.add(rideId));
      expect(segundaVolta, ['r1'], reason: 'a avaliação perdeu-se na falha');
    });

    test('reavaliar a mesma corrida substitui, não duplica', () async {
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r1', stars: 1);
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r1', stars: 5);

      final estrelas = <int>[];
      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver,
          (_, s, __) async => estrelas.add(s));
      expect(estrelas, [5]);
    });

    test('a fila do motorista não mexe na do cliente', () async {
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r1', stars: 5);
      await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindPassenger, rideId: 'r2', stars: 4);

      final doCliente = <String>[];
      await PendingRatingQueue.flush(PendingRatingQueue.kindDriver,
          (rideId, _, __) async => doCliente.add(rideId));
      expect(doCliente, ['r1']);

      // A do passageiro continua lá, intacta.
      final doMotorista = <String>[];
      await PendingRatingQueue.flush(PendingRatingQueue.kindPassenger,
          (rideId, _, __) async => doMotorista.add(rideId));
      expect(doMotorista, ['r2']);
    });

    test('guardar nunca lança — no pior caso devolve false', () async {
      // Contrato do ecrã: ele CHAMA isto dentro de um catch e fecha à mesma.
      // Se um dia isto passar a lançar, o cliente volta a ficar preso.
      final ok = await PendingRatingQueue.save(
          kind: PendingRatingQueue.kindDriver, rideId: 'r9', stars: 5);
      expect(ok, isA<bool>());
    });
  });
}
