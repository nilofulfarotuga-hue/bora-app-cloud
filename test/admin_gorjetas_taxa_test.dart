// Painel admin (PT-BR) — gorjetas com a taxa da Stripe (missão
// gorjetas-taxa-2026-10-30, Bloco E).
//
// Regra do Danilo (30/10/2026): gorjeta no carrinho com cartão/MB Way vai no
// mesmo pagamento da compra, inteira para o prestador; paga depois com
// cartão/MB Way, o prestador recebe a gorjeta menos a taxa exata da Stripe
// desse pagamento; em dinheiro, inteira. A Bora não ganha nada.
//
// Estes testes prendem: como foi paga, quem pagou a taxa, o líquido (com a
// taxa real e com a estimativa 25 cêntimos + 1,5 %), os totais do período, os
// textos do cartão e do reembolso, o rótulo do acerto TVDE e o interruptor da
// gorjeta junto com a compra nas Configurações.
import 'dart:io';

import 'package:bora_app/screens/admin/admin_gorjetas_screen.dart';
import 'package:bora_app/screens/admin/admin_tvde_acertos_tipo_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Linha como a função antiga do servidor a devolve (sem as colunas novas).
Map<String, dynamic> _antiga({
  required int valor,
  required String metodo,
  required String momento,
  String estado = 'succeeded',
  int? taxa,
  bool? junto,
}) =>
    {
      'id': 'g-$valor-$metodo-$momento',
      'criada_em': '2026-10-29T18:00:00+00:00',
      'alvo': 'order',
      'pedido': 'abc12345-0000',
      'cliente_nome': 'Ana',
      'prestador_nome': 'Bruno',
      'valor_cents': valor,
      'metodo': metodo,
      'momento': momento,
      'estado': estado,
      'taxa_stripe_cents': taxa,
      if (junto != null) 'cobrada_junto': junto,
    };

/// A gorjeta real de 29/10 (corrida TVDE, MB Way, paga depois): 2,00 − 0,28.
Map<String, dynamic> _real2910() => {
      ..._antiga(valor: 200, metodo: 'mbway', momento: 'after', taxa: 28),
      'alvo': 'tvde',
      'pedido': null,
      'corrida': 'b36ecbb4-0000',
      'liquido_prestador_cents': 172,
      'cobrada_junto': false,
      'como_foi_paga': 'depois',
      'quem_pagou_taxa': 'prestador',
      'taxa_descontada_prestador_cents': 28,
      'taxa_por_ler': false,
    };

void main() {
  group('como foi paga', () {
    test('dinheiro, junto da compra, à parte no carrinho, depois', () {
      expect(comoFoiPagaGorjeta(_antiga(valor: 100, metodo: 'cash', momento: 'checkout')),
          'dinheiro');
      expect(comoFoiPagaGorjeta(_antiga(valor: 100, metodo: 'cash', momento: 'after')),
          'dinheiro', reason: 'dinheiro é sempre dinheiro, mesmo dado depois');
      expect(
          comoFoiPagaGorjeta(
              _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true)),
          'junto_da_compra');
      expect(
          comoFoiPagaGorjeta(
              _antiga(valor: 250, metodo: 'mbway', momento: 'checkout', junto: false)),
          'a_parte_no_carrinho');
      expect(comoFoiPagaGorjeta(_antiga(valor: 250, metodo: 'card', momento: 'checkout')),
          'a_parte_no_carrinho',
          reason: 'sem a coluna cobrada_junto (função antiga) é à parte');
      expect(comoFoiPagaGorjeta(_antiga(valor: 200, metodo: 'card', momento: 'after')),
          'depois');
    });

    test('quando o servidor já manda a coluna, vale a do servidor', () {
      expect(comoFoiPagaGorjeta({'como_foi_paga': 'junto_da_compra', 'metodo': 'card', 'momento': 'checkout'}),
          'junto_da_compra');
      expect(comoFoiPagaGorjeta(_real2910()), 'depois');
    });

    test('rótulos PT-BR', () {
      expect(rotulosComoFoiPaga['dinheiro'], 'em dinheiro');
      expect(rotulosComoFoiPaga['junto_da_compra'], 'junto da compra (um pagamento só)');
      expect(rotulosComoFoiPaga['a_parte_no_carrinho'], 'à parte no carrinho');
      expect(rotulosComoFoiPaga['depois'], 'depois (na avaliação)');
      expect(rotuloMetodoGorjeta('card'), 'cartão');
      expect(rotuloMetodoGorjeta('mbway'), 'MB Way');
      expect(rotuloMetodoGorjeta('cash'), 'dinheiro');
    });
  });

  group('quem pagou a taxa da Stripe', () {
    test('depois com cartão/MB Way → prestador; à parte no carrinho → Bora; '
        'junto ou dinheiro → nenhuma', () {
      expect(quemPagouTaxaGorjeta(_antiga(valor: 200, metodo: 'mbway', momento: 'after')),
          'prestador');
      expect(quemPagouTaxaGorjeta(_antiga(valor: 250, metodo: 'card', momento: 'checkout')),
          'bora');
      expect(
          quemPagouTaxaGorjeta(
              _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true)),
          'nenhuma');
      expect(quemPagouTaxaGorjeta(_antiga(valor: 100, metodo: 'cash', momento: 'after')),
          'nenhuma');
      expect(quemPagouTaxaGorjeta(_real2910()), 'prestador');
    });

    test('rótulos PT-BR', () {
      expect(rotulosQuemPagouTaxa['prestador'], 'paga pelo prestador');
      expect(rotulosQuemPagouTaxa['bora'], 'paga pela Bora');
      expect(rotulosQuemPagouTaxa['nenhuma'], 'sem taxa à parte');
    });
  });

  group('líquido para o prestador', () {
    test('a gorjeta real de 29/10: 2,00 − 0,28 = 1,72', () {
      expect(liquidoGorjetaCents(_real2910()), 172);
      // Igual sem a coluna do servidor (função antiga), com a taxa real.
      expect(
          liquidoGorjetaCents(
              _antiga(valor: 200, metodo: 'mbway', momento: 'after', taxa: 28)),
          172);
    });

    test('taxa ainda por ler → estimativa 25 cêntimos + 1,5 % para cima', () {
      expect(taxaEstimadaGorjetaCents(200), 28);
      expect(taxaEstimadaGorjetaCents(500), 33); // 25 + ceil(7,5)
      expect(taxaEstimadaGorjetaCents(1000), 40); // 25 + 15
      final l = _antiga(valor: 500, metodo: 'card', momento: 'after');
      expect(liquidoGorjetaCents(l), 467);
      expect(taxaPorLerGorjeta(l), isTrue);
    });

    test('nunca abaixo de zero', () {
      expect(liquidoGorjetaCents(_antiga(valor: 20, metodo: 'card', momento: 'after')), 0);
    });

    test('carrinho (junto ou à parte) e dinheiro vão inteiros', () {
      expect(
          liquidoGorjetaCents(
              _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true)),
          300);
      expect(
          liquidoGorjetaCents(
              _antiga(valor: 250, metodo: 'card', momento: 'checkout', taxa: 29)),
          250,
          reason: 'à parte no carrinho a taxa é paga pela Bora');
      expect(liquidoGorjetaCents(_antiga(valor: 100, metodo: 'cash', momento: 'after')),
          100);
    });
  });

  group('totais do período', () {
    test('só as pagas; taxas dos prestadores e da Bora separadas', () {
      final linhas = [
        _real2910(), // depois, taxa 28 → prestador
        _antiga(valor: 100, metodo: 'cash', momento: 'checkout', estado: 'cancelled'),
        _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true),
        _antiga(valor: 250, metodo: 'card', momento: 'checkout', taxa: 29), // Bora
        _antiga(valor: 150, metodo: 'cash', momento: 'checkout', estado: 'cash_collected'),
        _antiga(valor: 500, metodo: 'card', momento: 'after'), // estimativa 33
        _antiga(valor: 400, metodo: 'card', momento: 'after', taxa: 31, estado: 'refunded'),
      ];
      final t = totaisGorjetas(linhas);
      expect(t.pagas, 5);
      expect(t.valor, 200 + 300 + 250 + 150 + 500);
      expect(t.liquido, 172 + 300 + 250 + 150 + 467);
      expect(t.taxasPrestadores, 28 + 33);
      expect(t.taxasBora, 29);
      expect(t.taxasPorLer, 1);
    });

    test('lista vazia → tudo a zero', () {
      final t = totaisGorjetas(const []);
      expect([t.pagas, t.valor, t.liquido, t.taxasPrestadores, t.taxasBora, t.taxasPorLer],
          everyElement(0));
    });
  });

  group('textos', () {
    test('linha da taxa em cada caso', () {
      expect(linhaTaxaGorjeta(_real2910()),
          'Taxa da Stripe € 0.28, paga pelo prestador · líquido para o prestador € 1.72');
      expect(linhaTaxaGorjeta(_antiga(valor: 500, metodo: 'card', momento: 'after')),
          contains('(estimada, ainda não lida da Stripe)'));
      expect(linhaTaxaGorjeta(_antiga(valor: 250, metodo: 'card', momento: 'checkout', taxa: 29)),
          'Taxa da Stripe € 0.29, paga pela Bora · líquido para o prestador € 2.50');
      expect(linhaTaxaGorjeta(_antiga(valor: 250, metodo: 'card', momento: 'checkout')),
          contains('ainda não lida'));
      expect(
          linhaTaxaGorjeta(
              _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true)),
          'Sem taxa à parte · líquido para o prestador € 3.00 (inteira)');
    });

    test('reembolso: junto da compra é devolvida em parte do pagamento do pedido', () {
      final junto = textoReembolsoGorjeta(
          _antiga(valor: 300, metodo: 'card', momento: 'checkout', junto: true));
      expect(junto, contains('Volta inteira para o cliente.'));
      expect(junto, contains('cobrada junto da compra'));
      expect(junto, contains('em parte do pagamento do pedido'));
      final depois = textoReembolsoGorjeta(_real2910());
      expect(depois, contains('Volta inteira para o cliente.'));
      expect(depois, isNot(contains('pagamento do pedido')));
    });

    test('a regra de 30/10 substituiu o "100% vai para o prestador"', () {
      final s = File('lib/screens/admin/admin_gorjetas_screen.dart').readAsStringSync();
      expect(s, isNot(contains('100% vai para o prestador')));
      expect(s, contains('menos a taxa'));
      expect(s, contains("'charge-tip'"), reason: 'o reembolso continua');
    });
  });

  group('widgets', () {
    testWidgets('cartão dos totais', (tester) async {
      final t = totaisGorjetas([
        _real2910(),
        _antiga(valor: 250, metodo: 'card', momento: 'checkout', taxa: 29),
      ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ListView(children: [CartaoTotaisGorjetas(totais: t)]))));
      expect(find.textContaining('2 gorjetas pagas · € 4.50'), findsOneWidget);
      expect(find.text('Líquido para os prestadores: € 4.22'), findsOneWidget);
      expect(find.textContaining('descontadas aos prestadores (gorjetas pagas depois): € 0.28'),
          findsOneWidget);
      expect(find.textContaining('pagas pela Bora (gorjetas à parte no carrinho): € 0.29'),
          findsOneWidget);
      expect(find.textContaining('A Bora não ganha nada com gorjetas'), findsOneWidget);
    });

    testWidgets('cartão de uma gorjeta mostra taxa, líquido e o botão', (tester) async {
      var carregou = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        LinhaGorjetaAdmin(linha: _real2910(), onReembolsar: () => carregou++),
        LinhaGorjetaAdmin(
            linha: _antiga(
                valor: 150, metodo: 'cash', momento: 'checkout', estado: 'cash_collected')),
      ]))));
      expect(find.textContaining('Corrida b36ecbb4 · MB Way · depois (na avaliação) · paga'),
          findsOneWidget);
      expect(find.textContaining('Taxa da Stripe € 0.28, paga pelo prestador'), findsOneWidget);
      expect(find.textContaining(' · dinheiro · em dinheiro (entregue)'), findsOneWidget);
      expect(find.textContaining('em dinheiro · em dinheiro'), findsNothing);
      expect(find.text('Reembolsar'), findsOneWidget,
          reason: 'só a gorjeta paga por cartão/MB Way se reembolsa');
      await tester.tap(find.text('Reembolsar'));
      expect(carregou, 1);
    });
  });

  group('painel: acerto TVDE e interruptor', () {
    test('acerto por tipo: rótulo das gorjetas líquidas', () {
      expect(kRotuloGorjetasLiquidas, 'Gorjetas (já sem a taxa da Stripe)');
      final s =
          File('lib/screens/admin/admin_tvde_acertos_tipo_tab.dart').readAsStringSync();
      expect(s, isNot(contains("'Gorjetas online (€)'")));
      expect(s, contains(r"'$kRotuloGorjetasLiquidas (€)'"));
    });

    test('tips_checkout_junto_pagamento editável nas Configurações, com explicação', () {
      expect(kChaveGorjetaJunto, 'tips_checkout_junto_pagamento');
      final s =
          File('lib/screens/admin/admin_platform_settings_screen.dart').readAsStringSync();
      // os rótulos vivem no State (privado): confere-se no código do ecrã
      final mapa = s.substring(s.indexOf('static const rotulosGorjetas'));
      expect(mapa.substring(0, mapa.indexOf('};')),
          contains('kChaveGorjetaJunto: kExplicacaoGorjetaJunto'));
      expect(kExplicacaoGorjetaJunto, contains('Ligado = a gorjeta dada no carrinho'));
      expect(RegExp(r'if\s*\(rotulosGorjetas\.containsKey\(key\)\)\s*return\s+true')
          .hasMatch(s), isTrue);
    });

    test('tips_checkout_junto_pagamento também no ecrã Gorjetas, gravado e relido', () {
      final s = File('lib/screens/admin/admin_gorjetas_screen.dart').readAsStringSync();
      final corpo = s.substring(s.indexOf('Future<void> _gravarInterruptor'));
      expect(corpo.indexOf("'get_setting'"), greaterThan(corpo.indexOf("'admin_update_setting'")));
      expect(s, contains('_gravarInterruptor(kChaveGorjetaJunto'));
      expect(s, contains('Gorjeta do carrinho junto com a compra'));
    });
  });
}
