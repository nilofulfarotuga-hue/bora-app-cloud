import 'package:bora_app/services/bateria_por_marca.dart';
import 'package:bora_app/services/foreground_service.dart';
import 'package:bora_app/utils/sinal_motorista.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ligadoSemSinal (painel, 24/10)', () {
    final agora = DateTime.utc(2026, 10, 24, 12, 0);

    test('botão desligado nunca é "sem sinal"', () {
      expect(ligadoSemSinal(ligado: false, ultimoSinal: null, agora: agora), isFalse);
      expect(
          ligadoSemSinal(
              ligado: false, ultimoSinal: DateTime.utc(2026, 10, 20, 2, 1), agora: agora),
          isFalse);
    });

    test('ligado com sinal de há 9 min continua online', () {
      expect(
          ligadoSemSinal(
              ligado: true,
              ultimoSinal: agora.subtract(const Duration(minutes: 9)),
              agora: agora),
          isFalse);
    });

    test('ligado com sinal de há 11 min = sem sinal', () {
      expect(
          ligadoSemSinal(
              ligado: true,
              ultimoSinal: agora.subtract(const Duration(minutes: 11)),
              agora: agora),
          isTrue);
    });

    test('ligado e nunca mandou sinal = sem sinal', () {
      expect(ligadoSemSinal(ligado: true, ultimoSinal: null, agora: agora), isTrue);
    });
  });

  group('ligadoSemSinalTexto (hora de Lisboa)', () {
    test('caso Valdemir: 20/10 02:01 UTC = 03:01 em Lisboa (verão)', () {
      expect(
        ligadoSemSinalTexto(DateTime.utc(2026, 10, 20, 2, 1),
            agora: DateTime.utc(2026, 10, 24, 12)),
        'Ligado sem sinal desde 20/10 às 03:01',
      );
    });

    test('no mesmo dia só a hora', () {
      expect(
        ligadoSemSinalTexto(DateTime.utc(2026, 10, 24, 8, 5),
            agora: DateTime.utc(2026, 10, 24, 12)),
        'Ligado sem sinal desde 09:05',
      );
    });

    test('nunca enviou', () {
      expect(ligadoSemSinalTexto(null), 'Ligado sem sinal (nunca enviou)');
    });
  });

  group('bateria por marca', () {
    test('marca sai da primeira palavra do modelo', () {
      expect(marcaDoModelo('samsung SM-A235F'), 'samsung');
      expect(marcaDoModelo('Xiaomi 23021RAAEG'), 'xiaomi');
      expect(marcaDoModelo(null), '');
      expect(marcaDoModelo('  '), '');
    });

    test('Samsung diz onde está "Apps que nunca são suspensas"', () {
      expect(instrucoesBateria('samsung'), contains('nunca são suspensas'));
    });

    test('Xiaomi/Redmi/POCO têm o mesmo caminho', () {
      expect(instrucoesBateria('redmi'), instrucoesBateria('xiaomi'));
      expect(instrucoesBateria('poco'), contains('Sem restrições'));
    });

    test('marca desconhecida cai no texto geral', () {
      expect(instrucoesBateria('nokia'), contains('Não otimizar'));
      expect(instrucoesBateria(''), instrucoesBateria('qualquer'));
    });
  });

  group('resultado do arranque do serviço de fundo', () {
    test('falha do plugin conta como falha (antes contava como sucesso)', () {
      expect(
          BoraForegroundService.resultIsSuccess(
              const ServiceRequestFailure(error: 'x')),
          isFalse);
      expect(
          BoraForegroundService.resultIsSuccess(const ServiceRequestSuccess()),
          isTrue);
      expect(BoraForegroundService.resultIsSuccess(true), isTrue);
      expect(BoraForegroundService.resultIsSuccess(false), isFalse);
    });
  });
}
