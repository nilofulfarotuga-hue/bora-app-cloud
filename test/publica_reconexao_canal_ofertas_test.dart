import 'package:bora_app/utils/reconexao_canal_ofertas.dart';
import 'package:flutter_test/flutter_test.dart';

/// B.2 (a) da missão publica-2026-10-29: o canal driver-offer não pode entrar em
/// ciclo de reconexão quando o fecho foi pedido por nós.
void main() {
  group('ReconexaoCanalOfertas', () {
    test('falha real no canal atual reagenda', () {
      final r = ReconexaoCanalOfertas();
      final canal = Object();
      r.canalLigado(canal);
      expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isTrue);
      expect(r.reagendamentos, 1);
    });

    test('estado que não é de falha nunca reagenda', () {
      final r = ReconexaoCanalOfertas();
      final canal = Object();
      r.canalLigado(canal);
      expect(r.deveReagendar(canal: canal, estadoDeFalha: false), isFalse);
      expect(r.reagendamentos, 0);
    });

    test('fecho pedido por mim não reagenda (o closed do removeChannel)', () {
      final r = ReconexaoCanalOfertas();
      final canal = Object();
      r.canalLigado(canal);
      r.vouFechar();
      // o removeChannel dispara `closed` no callback do canal antigo
      expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isFalse);
      r.fechoConcluido();
      expect(r.reagendamentos, 0);
      expect(r.ignorados, 1);
    });

    test('callback atrasado do canal antigo depois do fecho é ignorado', () {
      final r = ReconexaoCanalOfertas();
      final antigo = Object();
      final novo = Object();
      r.canalLigado(antigo);
      r.vouFechar();
      r.fechoConcluido();
      r.canalLigado(novo);
      // o `closed` do antigo chega só agora
      expect(r.deveReagendar(canal: antigo, estadoDeFalha: true), isFalse);
      // uma falha real do novo continua a reagendar
      expect(r.deveReagendar(canal: novo, estadoDeFalha: true), isTrue);
      expect(r.reagendamentos, 1);
      expect(r.ignorados, 1);
    });

    test('ciclo reconnect -> removeChannel -> closed repetido 10 vezes: zero reagendamentos', () {
      final r = ReconexaoCanalOfertas();
      var canal = Object();
      r.canalLigado(canal);
      // 1.ª falha real: reagenda uma vez
      expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isTrue);
      // o timer de reconnect fecha o canal antigo e liga um novo; o fecho dispara
      // `closed` no antigo. Antes da correção isto reagendava outra vez (ciclo).
      for (var i = 0; i < 10; i++) {
        r.vouFechar();
        expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isFalse,
            reason: 'volta $i: o closed do fecho pedido por mim reagendou');
        r.fechoConcluido();
        canal = Object();
        r.canalLigado(canal);
        // o novo canal liga bem (subscribed): não é falha
        expect(r.deveReagendar(canal: canal, estadoDeFalha: false), isFalse);
      }
      expect(r.reagendamentos, 1, reason: 'só a falha real conta');
      expect(r.ignorados, 10);
    });

    test('ao ficar offline (fecho nosso sem canal novo) nada fica agendado', () {
      final r = ReconexaoCanalOfertas();
      final canal = Object();
      r.canalLigado(canal);
      r.vouFechar();
      expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isFalse);
      r.fechoConcluido();
      // sem canal atual, até uma falha "real" de um canal qualquer é ignorada
      expect(r.deveReagendar(canal: canal, estadoDeFalha: true), isFalse);
      expect(r.reagendamentos, 0);
    });
  });
}
