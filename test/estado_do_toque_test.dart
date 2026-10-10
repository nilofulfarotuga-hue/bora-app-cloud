import 'package:bora_app/services/permission_gate_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [10/10/2026] A 09/10 e 10/10 as ofertas ao estafeta só vibraram (Samsung
/// A36, Android 16, em Vibrar/noite). As ofertas passaram a tocar pelo volume
/// do ALARME; `problemasDoToque` diz o que ainda as pode calar, do mais grave
/// para o menos grave. É função pura: estes testes não precisam de Android.
void main() {
  // Tudo como deve estar: notificações ligadas, canal alto e com som, volume
  // do alarme acima de zero, ecrã inteiro permitido, acesso ao "Não incomodar".
  List<ProblemaToque> calcular({
    bool notificacoesLigadas = true,
    int? canalImportancia = 4,
    bool canalComSom = true,
    int? volumeAlarme = 5,
    bool? ecraInteiroPermitido = true,
    bool acessoNaoIncomodar = true,
  }) =>
      problemasDoToque(
        notificacoesLigadas: notificacoesLigadas,
        canalImportancia: canalImportancia,
        canalComSom: canalComSom,
        volumeAlarme: volumeAlarme,
        ecraInteiroPermitido: ecraInteiroPermitido,
        acessoNaoIncomodar: acessoNaoIncomodar,
      );

  group('problemasDoToque', () {
    test('tudo bem → lista vazia', () {
      expect(calcular(), isEmpty);
    });

    test('volume do alarme a zero → um problema vermelho', () {
      final p = calcular(volumeAlarme: 0);
      expect(p, hasLength(1));
      expect(p.single.grave, isTrue);
      expect(p.single.correcao, CorrecaoToque.volumeAlarme);
      expect(p.single.texto, contains('alarme'));
    });

    test('só sem acesso ao "Não incomodar" → um aviso laranja', () {
      final p = calcular(acessoNaoIncomodar: false);
      expect(p, hasLength(1));
      expect(p.single.grave, isFalse);
      expect(p.single.correcao, CorrecaoToque.naoIncomodar);
    });

    test('notificações desligadas → vermelho e em primeiro lugar', () {
      final p = calcular(
        notificacoesLigadas: false,
        volumeAlarme: 0,
        acessoNaoIncomodar: false,
      );
      expect(p.first.correcao, CorrecaoToque.notificacoes);
      expect(p.first.grave, isTrue);
    });

    test('tudo mal → ordem de gravidade fixa, só o último é aviso', () {
      final p = calcular(
        notificacoesLigadas: false,
        canalImportancia: 2,
        volumeAlarme: 0,
        ecraInteiroPermitido: false,
        acessoNaoIncomodar: false,
      );
      expect(p.map((x) => x.correcao).toList(), [
        CorrecaoToque.notificacoes,
        CorrecaoToque.canalOfertas,
        CorrecaoToque.volumeAlarme,
        CorrecaoToque.ecraInteiro,
        CorrecaoToque.naoIncomodar,
      ]);
      expect(p.map((x) => x.grave).toList(), [true, true, true, true, false]);
      for (final x in p) {
        expect(x.texto.trim(), isNotEmpty);
      }
    });

    test('canal abaixo de "alta" ou sem som → vermelho', () {
      for (final imp in [0, 1, 2, 3]) {
        final p = calcular(canalImportancia: imp);
        expect(p.single.correcao, CorrecaoToque.canalOfertas,
            reason: 'importância $imp devia contar como silenciado');
        expect(p.single.grave, isTrue);
      }
      expect(calcular(canalComSom: false).single.correcao,
          CorrecaoToque.canalOfertas);
    });

    test('valores desconhecidos (null) nunca contam como problema', () {
      expect(
        calcular(
          canalImportancia: null,
          canalComSom: false,
          volumeAlarme: null,
          ecraInteiroPermitido: null,
        ),
        isEmpty,
      );
    });
  });

  group('EstadoDoToque.fromMap', () {
    test('lê o mapa do Android e devolve os problemas', () {
      final e = EstadoDoToque.fromMap(
        {
          'volumeAlarme': 0,
          'volumeAlarmeMax': 15,
          'modoCampainha': 'vibrar',
          'notificacoesLigadas': true,
          'acessoNaoIncomodar': false,
          'canalImportancia': 4,
          'canalComSom': true,
          'canalUsoAlarme': true,
        },
        ecraInteiroPermitido: true,
      );
      expect(e.volumeAlarme, 0);
      expect(e.volumeAlarmeMax, 15);
      expect(e.modoCampainha, 'vibrar');
      expect(e.canalOk, isTrue);
      expect(e.problemas.map((p) => p.correcao).toList(),
          [CorrecaoToque.volumeAlarme, CorrecaoToque.naoIncomodar]);
      expect(e.temProblemaGrave, isTrue);
    });

    test('mapa vazio ou com tipos errados → sem problemas inventados', () {
      expect(EstadoDoToque.fromMap(const {}).problemas, isEmpty);
      final e = EstadoDoToque.fromMap(const {
        'volumeAlarme': 'zero',
        'notificacoesLigadas': 'não',
        'canalImportancia': null,
      });
      expect(e.problemas, isEmpty);
      expect(e.canalOk, isNull);
      expect(e.temProblemaGrave, isFalse);
    });

    test('ecrã inteiro só conta quando é false', () {
      expect(
        EstadoDoToque.fromMap(const {}, ecraInteiroPermitido: false)
            .problemas
            .single
            .correcao,
        CorrecaoToque.ecraInteiro,
      );
      expect(
        EstadoDoToque.fromMap(const {}, ecraInteiroPermitido: null).problemas,
        isEmpty,
      );
    });
  });
}
