// CASA — ecrãs do cliente sem rede (31/10/2026, missão casa-manutencao).
//
// O store nasce com `CasaStore.semRede`: nenhuma leitura sai para o servidor.
// Prova o que o cliente VÊ: "Brevemente" com a categoria desligada, os ofícios
// da fase 1 com o preço que veio do servidor, e em cada estado do pedido só os
// botões certos (chat/ligar só com pode_contactar — decisão 4 do Danilo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/screens/client/casa/casa_categoria_screen.dart';
import 'package:bora_app/screens/client/casa/casa_meus_pedidos_screen.dart';
import 'package:bora_app/screens/client/casa/casa_pedido_screen.dart';
import 'package:bora_app/stores/casa_store.dart';

final _config = CasaConfig.fromJson({
  'visivel': true,
  'enabled': true,
  'max_cash_cents': 4000,
  'max_fotos': 5,
  'min_lead_hours': 2,
  'quote_max_pros': 3,
  'oficios': [
    {
      'codigo': 'montagem',
      'nome': 'Montagem de móveis',
      'descricao': 'Móveis IKEA e outros.',
      'fase': 1,
      'ativo': true,
    },
    {
      'codigo': 'eletricidade',
      'nome': 'Eletricidade',
      'fase': 2,
      'ativo': false,
    },
  ],
  'servicos': [
    {
      'id': 's1',
      'oficio': 'montagem',
      'nome': 'Montar um móvel',
      'modo': 'fixo',
      'preco_cents': 2500,
      'unidade': 'movel',
      'min_quantidade': 1,
      'max_quantidade': 10,
    },
    {
      'id': 's2',
      'oficio': 'montagem',
      'nome': 'Montagem grande ou cozinha',
      'modo': 'orcamento',
      'preco_cents': null,
      'unidade': 'tarefa',
    },
    {
      'id': 's3',
      'oficio': 'eletricidade',
      'nome': 'Trabalho de eletricidade',
      'modo': 'orcamento',
    },
  ],
});

const _rui = {
  'id': 'pro1',
  'name': 'Rui Faz-Tudo',
  'rating_avg': 4.8,
  'ratings_count': 12,
  'jobs_done': 30,
  'selos': ['documentos_verificados', 'seguro'],
};

CasaPedido _pedido(Map<String, dynamic> extra) => CasaPedido.fromJson({
      'id': 'p1',
      'servico_id': 's1',
      'servico_nome': 'Montar um móvel',
      'oficio': 'montagem',
      'oficio_nome': 'Montagem de móveis',
      'modo': 'fixo',
      'quantidade': 2,
      'estado': 'procura',
      'payment_method': 'cash',
      'payment_status': 'unpaid',
      'preco_cents': 5000,
      'total_cents': 5000,
      'scheduled_at': '2026-11-03T10:00:00Z',
      'created_at': '2026-11-01T09:00:00Z',
      'morada': {'street': 'Rua do Comércio 5', 'city': 'Guarda'},
      ...extra,
    });

Future<void> _montar(WidgetTester tester, CasaStore store, Widget ecra) async {
  // Ecrã alto: a lista desenha tudo de uma vez (os botões do fim incluídos).
  await tester.binding.setSurfaceSize(const Size(800, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<CasaStore>.value(
      value: store,
      child: MaterialApp(home: ecra),
    ),
  );
  await tester.pump();
}

void main() {
  group('Entrada da categoria', () {
    testWidgets('categoria desligada: "Brevemente", sem erro', (tester) async {
      final store = CasaStore.semRede(config: const CasaConfig(visivel: false));
      await _montar(tester, store, const CasaCategoriaScreen());
      expect(find.text('Brevemente'), findsOneWidget);
      expect(find.text('Os meus pedidos'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mostra só os ofícios ativos da fase 1, com o preço do servidor',
        (tester) async {
      final store = CasaStore.semRede(config: _config);
      await _montar(tester, store, const CasaCategoriaScreen());
      expect(find.text('Montagem de móveis'), findsOneWidget);
      expect(find.text('Eletricidade'), findsNothing,
          reason: 'fase 2 fica desligada até haver documento DGEG/IMPIC');
      expect(find.text('Os meus pedidos'), findsOneWidget);

      await tester.tap(find.text('Montagem de móveis'));
      await tester.pump();
      expect(find.text('desde 25,00 € por móvel'), findsOneWidget);
      expect(
          find.text('Pedir orçamento — grátis, até 3 profissionais respondem'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Acompanhamento do pedido', () {
    testWidgets('à espera de orçamentos: compara e aceita; sem chat',
        (tester) async {
      final p = _pedido({
        'modo': 'orcamento',
        'estado': 'orcamentos',
        'preco_cents': 0,
        'total_cents': 0,
        'orcamentos': [
          {
            'id': 'o1',
            'preco_cents': 4500,
            'inclui': 'Montagem e nivelamento',
            'materiais_incluidos': true,
            'prazo': 'Amanhã de manhã',
            'estado': 'enviado',
            'profissional': _rui,
          },
          {
            'id': 'o2',
            'preco_cents': 6000,
            'estado': 'enviado',
            'profissional': {'id': 'pro2', 'name': 'Ana'},
          },
        ],
      });
      final store = CasaStore.semRede(config: _config, pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));

      expect(find.text('Aceitar este orçamento'), findsNWidgets(2));
      expect(find.text('45,00 €'), findsOneWidget);
      expect(find.text('60,00 €'), findsOneWidget);
      expect(find.text('Mais barato'), findsOneWidget);
      expect(find.text('Com seguro'), findsOneWidget);
      expect(find.text('Mensagens'), findsNothing);
      expect(find.text('Cancelar pedido'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aceite sem pagamento confirmado: profissional sem contacto',
        (tester) async {
      final p = _pedido({'estado': 'aceite', 'profissional': _rui});
      final store = CasaStore.semRede(config: _config, pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));

      expect(find.text('Rui Faz-Tudo'), findsOneWidget);
      expect(find.text('Mensagens'), findsNothing);
      expect(find.text('Ligar'), findsNothing);
      expect(
          find.text(
              'As mensagens e o telefone aparecem quando o trabalho estiver aceite e pago.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('concluído com pode_contactar: confirmar, refazer, chat e ligar',
        (tester) async {
      final p = _pedido({
        'estado': 'concluido',
        'pode_contactar': true,
        'profissional': {..._rui, 'phone': '+351910000000'},
        'fotos': [
          {'id': 'f1', 'tipo': 'depois', 'storage_path': 'u/p1/depois_1.jpg'},
        ],
      });
      final store = CasaStore.semRede(config: _config, pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));

      expect(find.text('Confirmar que está tudo bem'), findsOneWidget);
      expect(find.text('Algo correu mal? Pedir para refazer'), findsOneWidget);
      expect(find.text('Mensagens'), findsOneWidget);
      expect(find.text('Ligar'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsNothing,
          reason: 'trabalho feito já não se cancela');
      expect(find.text('Avaliar o profissional'), findsNothing,
          reason: 'avalia-se depois de confirmar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('valor extra por responder: aceitar e recusar', (tester) async {
      final p = _pedido({
        'estado': 'em_curso',
        'pode_contactar': true,
        'profissional': _rui,
        'extras': [
          {
            'id': 'e1',
            'valor_cents': 1500,
            'motivo': 'Faltava uma dobradiça',
            'estado': 'pedido',
          },
        ],
      });
      final store = CasaStore.semRede(config: _config, pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));

      expect(find.text('O profissional pede mais 15,00 €'), findsOneWidget);
      expect(find.text('Faltava uma dobradiça'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirmado e pago: avaliar aparece', (tester) async {
      final p = _pedido({'estado': 'confirmado', 'profissional': _rui});
      final store = CasaStore.semRede(config: _config, pedidos: [p]);
      await _montar(tester, store, CasaPedidoScreen(pedido: p));

      expect(find.text('Avaliar o profissional'), findsOneWidget);
      expect(find.text('Confirmar que está tudo bem'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Os meus pedidos', () {
    testWidgets('lista com estado; sem pedidos diz isso', (tester) async {
      final store = CasaStore.semRede(config: _config, pedidos: [
        _pedido({'estado': 'aceite'}),
        _pedido({
          'id': 'p2',
          'servico_nome': 'Trocar torneira',
          'estado': 'cancelado',
        }),
      ]);
      await _montar(tester, store, const CasaMeusPedidosScreen());
      expect(find.text('Montar um móvel'), findsOneWidget);
      expect(find.text('Trocar torneira'), findsOneWidget);
      expect(find.text('Confirmado'), findsOneWidget);
      expect(find.text('Cancelado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('vazio', (tester) async {
      final store = CasaStore.semRede(config: _config);
      await _montar(tester, store, const CasaMeusPedidosScreen());
      expect(find.text('Ainda não fizeste pedidos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
