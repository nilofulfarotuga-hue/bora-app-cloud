import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// M10 b2-textos (09/11/2026) — missão m10-noite-toda-sem-travas-2026-11-08.
///
/// Um grupo por item da missão. O repo testa muito pela fonte: aqui lê-se o
/// ficheiro .dart e confirma-se o que o ecrã faz, e onde dá, desenha-se o
/// widget.
String _ler(String caminho) => File(caminho).readAsStringSync();

/// Pedaço da fonte entre [inicio] (inclusive) e [fim] (exclusive).
String _entre(String src, String inicio, String fim) {
  final a = src.indexOf(inicio);
  expect(a, isNonNegative, reason: 'não encontrei "$inicio"');
  final b = src.indexOf(fim, a + inicio.length);
  expect(b, greaterThan(a), reason: 'não encontrei "$fim" depois de "$inicio"');
  return src.substring(a, b);
}

void main() {
  // ── 2.12 — reembolso ao cancelar no acompanhamento do pedido ──────────────
  group('M10 2.12 — cancelar no acompanhamento: o cliente escolhe o reembolso',
      () {
    // Lido dentro de cada teste: o expect() do _entre só vale num teste.
    late String cancelar;
    setUp(() {
      cancelar = _entre(_ler('lib/screens/order_tracking_screen.dart'),
          'Future<void> _confirmClientCancel', 'class _CodeDigit');
    });

    test('nada vem marcado à partida (antes: cartão por defeito)', () {
      expect(cancelar, isNot(contains("String refundTarget = 'card';")));
      expect(cancelar, contains('String? refundTarget;'));
    });

    test('saiu o texto antigo "80% saldo + 20% pontos" e os rádios pequenos',
        () {
      // O texto no ecrã (literal com .tr); o comentário que explica a mudança
      // pode citá-lo.
      expect(cancelar,
          isNot(contains("'Na carteira, imediato (80% saldo + 20% pontos)'")));
      expect(cancelar, isNot(contains("'De volta ao cartão (~5 dias úteis)'")));
      expect(cancelar, isNot(contains('RadioListTile')));
    });

    test('duas opções grandes, com os mesmos textos do RefundChoiceDialog', () {
      expect(cancelar, contains("Key('opcao_reembolso_wallet')"));
      expect(cancelar, contains("Key('opcao_reembolso_meio')"));
      expect(cancelar, contains("'Carteira Bora'.tr"));
      expect(cancelar, contains("'Devolver para a minha conta'.tr"));
      // MB Way na hora / cartão 5 a 10 dias úteis, conforme o meio do pedido.
      expect(
          cancelar,
          matches(RegExp(
              r'prazoDevolucaoAoMeio\(\s*widget\.order\.paymentMethod\.name\)')));
      // Tokens voltam como tokens.
      expect(cancelar, contains('voltam como tokens'));
    });

    test('os valores enviados ao servidor são os mesmos: wallet | card', () {
      expect(cancelar, contains("refundTarget = 'wallet'"));
      expect(cancelar, contains("refundTarget = 'card'"));
      expect(cancelar, contains("refundTarget: refundTarget ?? 'card'"));
      // A API do OrderStore não mudou.
      expect(_ler('lib/stores/order_store.dart'),
          contains("'refund_target': refundTarget"));
    });

    test('sem escolha feita, "Confirmar cancelamento" fica desligado', () {
      expect(cancelar, contains('(canChooseRefund && refundTarget == null)'));
      // Fechar o diálogo (ou "Não") nunca cancela.
      expect(cancelar,
          contains('if (confirmed != true || !context.mounted) return;'));
    });
  });
}
