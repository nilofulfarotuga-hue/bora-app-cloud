// CASA — cartão e MB Way pelo caminho da Limpeza (m11, 09/11/2026). Sem rede.
//
// Prova o que muda na app (o servidor prova-se em docs/casa/prova/provar_cartao_mbway.mjs):
//  1. As regras: "por pagar na app" e "precisa de devolução".
//  2. O cliente vê "Pagar agora" só num pedido por cartão/MB Way à espera do pagamento.
//  3. Com o servidor a dizer pagamento_cartao=true, cartão e MB Way acendem-se no pagamento.
//  4. Painel: o interruptor do cartão só liga com a confirmação forte; sem a chave no servidor fica
//     cinzento e diz que entra com o "autorizo".
//  5. Painel: "Devolver ao cliente" só aparece com devolução pendente num pedido pago na app, e
//     pede confirmação antes de chamar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/screens/admin/admin_casa_definicoes_tab.dart';
import 'package:bora_app/screens/admin/admin_casa_pedidos_tab.dart';
import 'package:bora_app/screens/client/casa/casa_pedido_screen.dart';
import 'package:bora_app/screens/client/casa/casa_regras.dart';
import 'package:bora_app/stores/casa_store.dart';

CasaConfig _config({bool cartao = false}) => CasaConfig.fromJson({
      'visivel': true,
      'enabled': true,
      'pagamento_cartao': cartao,
      'max_cash_cents': 4000,
      'oficios': [
        {'codigo': 'montagem', 'nome': 'Montagem de móveis', 'fase': 1, 'ativo': true},
      ],
      'servicos': [
        {
          'id': 's1', 'oficio': 'montagem', 'nome': 'Montar roupeiro', 'modo': 'fixo',
          'preco_cents': 8000, 'unidade': 'movel', 'min_quantidade': 1, 'max_quantidade': 5,
        },
      ],
    });

CasaPedido _pedido(Map<String, dynamic> extra) => CasaPedido.fromJson({
      'id': 'p1',
      'servico_id': 's1',
      'servico_nome': 'Montar roupeiro',
      'oficio': 'montagem',
      'oficio_nome': 'Montagem de móveis',
      'modo': 'fixo',
      'quantidade': 1,
      'estado': 'aguarda_pagamento',
      'payment_method': 'card',
      'payment_status': 'unpaid',
      'preco_cents': 8000,
      'total_cents': 8000,
      'scheduled_at': '2026-11-12T10:00:00Z',
      'created_at': '2026-11-09T09:00:00Z',
      'morada': {'street': 'Rua do Comércio 5', 'city': 'Guarda'},
      ...extra,
    });

Future<void> _montar(WidgetTester tester, CasaStore store, Widget ecra) async {
  await tester.binding.setSurfaceSize(const Size(800, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider<CasaStore>.value(
    value: store,
    child: MaterialApp(home: ecra),
  ));
  await tester.pump();
}

class _Rpc {
  _Rpc(this.respostas);
  final Map<String, dynamic> respostas;
  final chamadas = <(String, Map<String, dynamic>)>[];
  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, params));
    return respostas[fn];
  }

  List<Map<String, dynamic>> de(String fn) => [for (final c in chamadas) if (c.$1 == fn) c.$2];
}

void _ecraGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('regras', () {
    test('por pagar na app: só cartão/MB Way à espera do pagamento', () {
      expect(casaPorPagarNaApp(_pedido({})), isTrue);
      expect(casaPorPagarNaApp(_pedido({'payment_method': 'mbway'})), isTrue);
      expect(casaPorPagarNaApp(_pedido({'payment_method': 'cash', 'estado': 'procura'})), isFalse);
      expect(casaPorPagarNaApp(_pedido({'estado': 'procura', 'payment_status': 'held'})), isFalse);
    });

    test('precisa de devolução: cancelado/expirado com o pagamento da app retido', () {
      expect(casaPrecisaDeDevolucao(_pedido({'estado': 'cancelado', 'payment_status': 'held'})), isTrue);
      expect(casaPrecisaDeDevolucao(_pedido({'estado': 'expirado', 'payment_status': 'held'})), isTrue);
      expect(casaPrecisaDeDevolucao(_pedido({'estado': 'cancelado', 'payment_status': 'estornado'})), isFalse);
      expect(casaPrecisaDeDevolucao(_pedido({'estado': 'cancelado', 'payment_status': 'unpaid'})), isFalse);
      expect(casaPrecisaDeDevolucao(_pedido({'estado': 'procura', 'payment_status': 'held'})), isFalse);
      expect(
          casaPrecisaDeDevolucao(
              _pedido({'estado': 'cancelado', 'payment_status': 'held', 'payment_method': 'cash'})),
          isFalse);
    });

    test('com o servidor a ligar o cartão, o roupeiro de 80 € pede-se por cartão ou MB Way', () {
      final desligado = casaMetodosPagamento(totalCents: 8000, config: _config());
      expect(desligado.where((m) => m.disponivel), isEmpty);
      final ligado = casaMetodosPagamento(totalCents: 8000, config: _config(cartao: true));
      expect([for (final m in ligado) if (m.disponivel) m.codigo], containsAll(['card', 'mbway']));
      expect(ligado.firstWhere((m) => m.codigo == 'cash').disponivel, isFalse);
    });

    test('na web o cartão fica cinzento (só na app do telemóvel) e o MB Way dá', () {
      final web = casaMetodosPagamento(
          totalCents: 8000, config: _config(cartao: true), cartaoNestaPlataforma: false);
      expect([for (final m in web) if (m.disponivel) m.codigo], ['mbway']);
      expect(web.firstWhere((m) => m.codigo == 'card').rotulo, 'Cartão — só na app do telemóvel');
      expect(casaPorqueIndisponivel('card', totalCents: 8000, config: _config(cartao: true)),
          'O cartão só dá na app do telemóvel. Aqui, paga com MB Way.');
    });
  });

  group('ecrã do pedido', () {
    testWidgets('"Pagar agora" num pedido por cartão à espera do pagamento', (tester) async {
      final p = _pedido({});
      final store = CasaStore.semRede(config: _config(cartao: true), pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));
      expect(find.byKey(const Key('casa_pagar_agora')), findsOneWidget);
      expect(find.textContaining('só segue para os profissionais depois de pago'), findsOneWidget);
    });

    testWidgets('em dinheiro não há "Pagar agora"', (tester) async {
      final p = _pedido({'payment_method': 'cash', 'estado': 'procura', 'total_cents': 4000});
      final store = CasaStore.semRede(config: _config(cartao: true), pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));
      expect(find.byKey(const Key('casa_pagar_agora')), findsNothing);
    });
  });

  group('painel (PT-BR)', () {
    Map<String, dynamic> resumo() => {
          'enabled': true,
          'valores_autorizados': {'autorizado': true},
        };

    testWidgets('interruptor do cartão: sem a chave no servidor fica cinzento', (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_definicoes': [
          {'key': 'casa_enabled', 'value': true, 'description': 'Casa ligada'},
        ],
        'admin_casa_resumo': resumo(),
      });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminCasaDefinicoesTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      final sw = tester.widget<SwitchListTile>(find.byKey(const ValueKey('casa-pagamento-app')));
      expect(sw.onChanged, isNull);
      expect(find.textContaining('entra com o "autorizo" do Danilo'), findsOneWidget);
    });

    testWidgets('interruptor do cartão: ligar pede LIGAR antes de chamar', (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_definicoes': [
          {'key': 'casa_enabled', 'value': true, 'description': 'Casa ligada'},
          {'key': kCasaChavePagamentoApp, 'value': false, 'description': 'Cartão e MB Way'},
        ],
        'admin_casa_resumo': resumo(),
        'admin_casa_guardar_definicao': {'ok': true},
      });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminCasaDefinicoesTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      expect(find.text('Cartão e MB Way desligados (só dinheiro)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('casa-pagamento-app')));
      await tester.pumpAndSettle();
      expect(find.text('LIGAR cartão e MB Way na Casa?'), findsOneWidget);
      expect(find.textContaining('ISTO MEXE EM PAGAMENTO/DINHEIRO'), findsOneWidget);
      FilledButton ok() => tester.widget<FilledButton>(find.byKey(const ValueKey('casa-confirmar-ok')));
      expect(ok().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('casa-confirmar-texto')), 'ligar');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_guardar_definicao'), [
        {'p_key': kCasaChavePagamentoApp, 'p_value': true}
      ]);
    });

    Map<String, dynamic> fichaCancelada(Map<String, dynamic> extra) => {
          'id': 'x1',
          'estado': 'cancelado',
          'servico_nome': 'Montar roupeiro',
          'oficio': 'montagem',
          'modo': 'fixo',
          'total_cents': 8000,
          'cancel_fee_cents': 0,
          'morada': {'street': 'Rua A', 'city': 'Guarda', 'postal': '6300-000'},
          'cliente': {'nome': 'Ana'},
          ...extra,
        };

    testWidgets('"Devolver ao cliente" só com devolução pendente e pago na app; confirma antes',
        (tester) async {
      _ecraGrande(tester);
      final rpc = _Rpc({
        'admin_casa_pedido': fichaCancelada({'payment_method': 'card', 'reembolso_pendente': true}),
      });
      final pedidos = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: AdminCasaPedidoScreen(
              id: 'x1',
              rpc: rpc.call,
              devolver: (id) async {
                pedidos.add(id);
                return {'ok': true, 'note': 'reversed', 'backCents': 8000};
              })));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('casa-pedido-devolver')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('casa-pedido-devolver')));
      await tester.pumpAndSettle();
      expect(find.text('Devolver ao cliente?'), findsOneWidget);
      expect(pedidos, isEmpty);
      await tester.tap(find.byKey(const ValueKey('casa-confirmar-ok')));
      await tester.pumpAndSettle();
      expect(pedidos, ['x1']);
    });

    testWidgets('sem devolução pendente, ou em dinheiro, não há botão', (tester) async {
      _ecraGrande(tester);
      for (final extra in [
        {'payment_method': 'card', 'reembolso_pendente': false},
        {'payment_method': 'cash', 'reembolso_pendente': true},
      ]) {
        final rpc = _Rpc({'admin_casa_pedido': fichaCancelada(extra)});
        await tester.pumpWidget(MaterialApp(home: AdminCasaPedidoScreen(id: 'x1', rpc: rpc.call)));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('casa-pedido-devolver')), findsNothing, reason: '$extra');
      }
    });
  });
}
