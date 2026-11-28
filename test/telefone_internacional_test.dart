import 'dart:io';

import 'package:bora_app/utils/contact_validators.dart';
import 'package:bora_app/utils/telefone_internacional.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// 28/11/2026 — missão pedido-exige-telefone-e-morada. Adendo do Danilo
/// (10:10): "não tem que ser só telefone em português, tem que ser qualquer
/// outro tipo de telefone". Casos conferidos com o Dart no PC antes do envio.
void main() {
  group('telemóvel de qualquer país, gravado com o indicativo', () {
    test('Portugal: com e sem indicativo, móvel e fixo', () {
      expect(telefoneInternacional('912345678', IsoCode.PT), '+351912345678');
      expect(telefoneInternacional('+351 912 345 678', IsoCode.PT), '+351912345678');
      expect(telefoneInternacional('271 123 456', IsoCode.PT), '+351271123456');
    });

    test('Brasil, Espanha, Reino Unido (com e sem o 0 nacional)', () {
      expect(telefoneInternacional('11 98765-4321', IsoCode.BR), '+5511987654321');
      expect(telefoneInternacional('612 34 56 78', IsoCode.ES), '+34612345678');
      expect(telefoneInternacional('07400 123456', IsoCode.GB), '+447400123456');
      expect(telefoneInternacional('7400 123456', IsoCode.GB), '+447400123456');
    });

    test('colado inteiro com + ou 00 vale o indicativo do número', () {
      expect(telefoneInternacional('+55 11 98765-4321', IsoCode.PT), '+5511987654321');
      expect(telefoneInternacional('0044 7400 123456', IsoCode.PT), '+447400123456');
    });

    test('inválidos: curtos, letras, vazio, fora do plano do país', () {
      for (final v in ['12345', 'abc', '', '812345678']) {
        expect(telefoneInternacional(v, IsoCode.PT), isNull, reason: v);
        expect(validarTelefone(v, IsoCode.PT), isNotNull, reason: v);
      }
    });

    test('nunca recusa por não ser português', () {
      expect(validarTelefone('11 98765-4321', IsoCode.BR), isNull);
      expect(telefoneGuardadoValido('+5511987654321'), isTrue);
      expect(contactoDoClienteCompleto(nome: 'Ana Silva', telemovel: '+5511987654321'),
          isTrue);
    });

    test('os antigos guardados sem indicativo continuam a valer (Portugal)', () {
      expect(telefoneGuardadoValido('912345678'), isTrue);
      expect(telefoneEstrangeiro('912345678'), isFalse);
      final p = separarTelefone('912345678');
      expect(p.pais.iso, IsoCode.PT);
      expect(p.nacional, '912345678');
    });

    test('estrangeiro → WhatsApp com os dígitos certos', () {
      expect(telefoneEstrangeiro('+5511987654321'), isTrue);
      expect(digitosWhatsApp('+5511987654321'), '5511987654321');
      final p = separarTelefone('+5511987654321');
      expect(p.pais.nome, 'Brasil');
      expect(p.nacional, '11987654321');
    });

    test('Portugal é o primeiro e o defeito do seletor', () {
      expect(kPaisesTelefone.first.iso, IsoCode.PT);
      expect(kPaisTelefonePorDefeito.indicativo, '351');
      expect(kPaisesTelefone.map((p) => p.iso).toSet().length, kPaisesTelefone.length);
    });
  });

  group('o passo "Falta só isto" está ligado antes de pagar', () {
    String ler(String p) => File(p).readAsStringSync();

    test('o carrinho e o ecrã de pagamento pedem telemóvel e morada', () {
      expect(ler('lib/screens/cart_screen.dart'),
          contains('precisaMorada: !cartStore.isTakeaway'));
      final pag = ler('lib/screens/payment_method_screen.dart');
      expect(pag, contains('garantirContactoDoCliente('));
      expect(pag, contains("err.contains('SEM_TELEFONE')"));
      expect(pag, contains("err.contains('SEM_MORADA')"));
    });

    test('o texto do estafeta fala de chamada ou WhatsApp', () {
      expect(ler('lib/screens/client/falta_so_isto_screen.dart'),
          contains('O estafeta usa este número para te contactar (chamada ou WhatsApp) se precisar.'));
    });

    test('a morada exige rua e número e tem o pino que se arrasta', () {
      final s = ler('lib/screens/client/falta_so_isto_screen.dart');
      expect(s, contains('draggable: true'));
      expect(s, contains('Confirma onde é a tua porta'));
      expect(s, contains("'Falta o número da porta (ex.: Rua do Comércio, 12).'"));
      expect(s, contains('isDefault: ja.isEmpty'));
    });
  });
}
