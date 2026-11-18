// Missão farmacia-peca-aqui-18-11 (18/11/2026). Caso real: a cliente procurou "vomidrine" na Farmácia
// da Sé (parceira), não havia no catálogo e a app só lhe deu "Pede ao Amigo". Regra do Danilo:
// "primeiro é o parceiro, depois as outras".
//  * pesquisa vazia numa farmácia aberta com os botões → "Pedir à {farmácia}" primeiro, o Amigo por baixo;
//  * farmácia sem botões e loja normal → como antes (só o Amigo);
//  * adendo 1: na lista da farmácia, os aceites ficam em "À espera do cliente confirmar";
//  * adendo 2: o cartão das receitas conta também os que esperam pelo cliente;
//  * painel: aba "Pedidos especiais (pedido livre)" com o que pediu, a resposta e o tempo.
// Dados de brincar (nada de clientes reais).
import 'dart:async';

import 'package:bora_app/models/pedido_prescricao.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/screens/admin/admin_farmacias_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/client/assistant/assistant_acoes.dart' show lerDestinoPedirFarmacia;
import 'package:bora_app/screens/partner/farmacia/parceiro_prescricoes_screen.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/pesquisa_sem_resultado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

const _se = FarmaciaDaPesquisa(restaurantId: 'farmacia-se-guarda', nome: 'Farmácia da Sé');

PedidoPrescricao _pedido(String id, String estado, {String tipo = 'pedido_livre', String? respondido}) =>
    PedidoPrescricao.fromMap({
      'id': id,
      'created_at': '2026-11-18T11:00:00Z',
      'restaurant_id': 'farmacia-se-guarda',
      'user_id': '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7',
      'tipo': tipo,
      'estado': estado,
      'descricao': tipo == 'pedido_livre' ? 'Vomidrine' : null,
      'morada': 'Rua do Comércio 10, Guarda',
      'valor_medicamentos_cents': estado == 'enviado' ? null : 640,
      'total_cents': estado == 'enviado' ? null : 1240,
      'respondido_em': respondido,
      'expira_em': '2026-11-18T11:30:00Z',
      'taxa_servico_cents': 600,
      'is_demo': false,
    });

void main() {
  group('pesquisa vazia dentro da farmácia', () {
    setUp(() => AssistantFlags.enabled.value = true);

    testWidgets('farmácia aberta com os botões: "Pedir à Farmácia da Sé" primeiro, com o termo; o Amigo por baixo',
        (t) async {
      FarmaciaDaPesquisa? pedidaA;
      String? termo;
      String? aoAmigo;
      await t.pumpWidget(_app(PesquisaSemResultado(
        termo: ' vomidrine ',
        loja: 'Farmácia da Sé',
        farmacia: _se,
        aoPedirAFarmacia: (f, x) {
          pedidaA = f;
          termo = x;
        },
        aoPedirAoAmigo: (m) => aoAmigo = m,
      )));
      final farmacia = find.byKey(const Key('pedir-a-farmacia'));
      final amigo = find.byKey(const Key('pede-ao-amigo'));
      expect(farmacia, findsOneWidget);
      expect(find.text('Pedir à Farmácia da Sé'), findsOneWidget);
      expect(find.text('A farmácia confirma se tem e o preço. Só pagas depois de confirmar.'), findsOneWidget);
      expect(amigo, findsOneWidget);
      expect(t.getTopLeft(farmacia).dy, lessThan(t.getTopLeft(amigo).dy), reason: 'a farmácia vem primeiro');

      await t.tap(farmacia);
      await t.pump();
      expect(pedidaA?.restaurantId, 'farmacia-se-guarda');
      expect(termo, 'vomidrine');

      await t.tap(amigo);
      await t.pump();
      expect(aoAmigo, 'Não encontrei "vomidrine" na Farmácia da Sé. Ajuda-me a pedir à farmácia ou diz-me onde mais há.');
    });

    testWidgets('farmácia fechada ou sem os botões para esta pessoa: fica como antes (só o Amigo)', (t) async {
      String? aoAmigo;
      await t.pumpWidget(_app(PesquisaSemResultado(
        termo: 'vomidrine',
        loja: 'Farmácia da Sé',
        aoPedirAoAmigo: (m) => aoAmigo = m,
      )));
      expect(find.byKey(const Key('pedir-a-farmacia')), findsNothing);
      await t.tap(find.byKey(const Key('pede-ao-amigo')));
      expect(aoAmigo, 'Não encontrei "vomidrine" em Farmácia da Sé. Procura noutras lojas ou propõe-me um Favor.');
    });

    testWidgets('loja normal: só o Amigo, mensagem de sempre', (t) async {
      await t.pumpWidget(_app(const PesquisaSemResultado(termo: 'gelado', loja: 'Continente')));
      expect(find.byKey(const Key('pedir-a-farmacia')), findsNothing);
      expect(find.byKey(const Key('pede-ao-amigo')), findsOneWidget);
      expect(find.text('Não encontrei "gelado" aqui.'), findsOneWidget);
    });

    testWidgets('com o Amigo desligado no painel, o pedido à farmácia continua lá', (t) async {
      AssistantFlags.enabled.value = false;
      addTearDown(() => AssistantFlags.enabled.value = true);
      await t.pumpWidget(_app(const PesquisaSemResultado(termo: 'vomidrine', loja: 'Farmácia da Sé', farmacia: _se)));
      expect(find.byKey(const Key('pedir-a-farmacia')), findsOneWidget);
      expect(find.byKey(const Key('pede-ao-amigo')), findsNothing);
    });
  });

  test('destino da ação pedir_farmacia do Amigo: "loja|produto"', () {
    final d = lerDestinoPedirFarmacia('farmacia-se-guarda|vomidrine');
    expect(d?.restaurantId, 'farmacia-se-guarda');
    expect(d?.termo, 'vomidrine');
    expect(lerDestinoPedirFarmacia('farmacia-se-guarda')?.termo, '');
    expect(lerDestinoPedirFarmacia('|vomidrine'), isNull);
    expect(kAssistantAcoesSuportadas, contains('pedir_farmacia'));
  });

  group('adendo 1 e 2 — a farmácia vê o que está à espera do cliente', () {
    testWidgets('aceite sai de "À espera de resposta" e fica logo a seguir, com o valor e há quanto tempo',
        (t) async {
      await t.pumpWidget(_app(ParceiroPrescricoesLista(
        agora: () => DateTime.utc(2026, 11, 18, 11, 22),
        pedidos: [
          _pedido('00000000-0000-4000-8000-000000000001', 'enviado'),
          _pedido('00000000-0000-4000-8000-000000000002', 'aceite', respondido: '2026-11-18T11:10:00Z'),
          _pedido('00000000-0000-4000-8000-000000000003', 'recusado', respondido: '2026-11-18T11:05:00Z'),
        ],
      )));
      final espera = find.text('À espera de resposta (1)');
      final cliente = find.text('À espera do cliente confirmar (1)');
      final respondidos = find.text('Respondidos (1)');
      expect(espera, findsOneWidget);
      expect(cliente, findsOneWidget);
      expect(respondidos, findsOneWidget, reason: 'só o recusado fica em Respondidos');
      expect(t.getTopLeft(espera).dy, lessThan(t.getTopLeft(cliente).dy));
      expect(t.getTopLeft(cliente).dy, lessThan(t.getTopLeft(respondidos).dy));
      expect(find.textContaining('Valor 12,40 €'), findsOneWidget);
      expect(find.textContaining('À espera há 12 min'), findsOneWidget);
    });

    testWidgets('o cartão do separador Pedidos conta os aceites à espera do cliente (sem "Sem pedidos à espera")',
        (t) async {
      const farmacia = RestaurantModel(
        id: 'farmacia-se-guarda',
        name: 'Farmácia da Sé',
        phone: '',
        address: '',
        email: '',
        photoUrl: '',
        cuisineType: '',
        isPartner: true,
        category: BusinessCategory.pharmacy,
      );
      final ctl = StreamController<List<PedidoPrescricao>>();
      addTearDown(ctl.close);
      await t.pumpWidget(_app(FarmaciaReceitasCartao(restaurant: farmacia, pedidos: ctl.stream)));
      final ha10min = DateTime.now().toUtc().subtract(const Duration(minutes: 10)).toIso8601String();
      final ha2dias = DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String();
      ctl.add([
        _pedido('00000000-0000-4000-8000-000000000002', 'aceite', respondido: ha10min),
        // aceite velho (o aceite não expira): não conta para sempre no cartão.
        _pedido('00000000-0000-4000-8000-000000000004', 'aceite', respondido: ha2dias),
      ]);
      await t.pump();
      expect(find.text('1 à espera do cliente confirmar'), findsOneWidget);
      expect(find.text('Sem pedidos à espera'), findsNothing);
    });

    testWidgets('aceite com mais de 6 horas vai para "Respondidos"', (t) async {
      await t.pumpWidget(_app(ParceiroPrescricoesLista(
        agora: () => DateTime.utc(2026, 11, 18, 11, 22),
        pedidos: [_pedido('00000000-0000-4000-8000-000000000005', 'aceite', respondido: '2026-11-13T10:21:00Z')],
      )));
      expect(find.text('À espera do cliente confirmar (1)'), findsNothing);
      expect(find.text('Respondidos (1)'), findsOneWidget);
    });
  });

  group('painel — pedidos especiais (pedido livre)', () {
    test('tempo até responder e resposta da farmácia em texto curto', () {
      final r = {
        'created_at': '2026-11-18T11:48:00Z',
        'respondido_em': '2026-11-18T13:03:00Z',
        'itens_disponiveis': 'Vomidrine 10 comprimidos',
        'valor_medicamentos_cents': 640,
      };
      expect(minutosAteResponder(r), 75);
      expect(tempoRespostaTxt(r), '1 h 15 min');
      expect(respostaFarmaciaTxt(r), 'tem: Vomidrine 10 comprimidos · preço 6,40 €');
      expect(tempoRespostaTxt({'created_at': '2026-11-18T11:48:00Z'}), 'ainda não respondeu');
      expect(respostaFarmaciaTxt(const {}), '—');
    });

    testWidgets('a aba mostra só os pedidos especiais, com o que o cliente pediu', (t) async {
      Future<List<Map<String, dynamic>>> listar({String? estado}) async => [
            {
              'id': 'a',
              'created_at': '2026-11-18T11:48:00Z',
              'loja': 'Farmácia da Sé',
              'tipo': 'pedido_livre',
              'estado': 'aceite',
              'descricao': 'Vomidrine',
              'respondido_em': '2026-11-18T11:51:00Z',
              'valor_medicamentos_cents': 640,
            },
            {'id': 'b', 'created_at': '2026-11-18T10:00:00Z', 'loja': 'Farmácia da Sé', 'tipo': 'receita', 'estado': 'enviado'},
          ];
      await t.pumpWidget(_app(AdminPedidosReceitaAba(tipo: 'pedido_livre', listar: listar)));
      await t.pumpAndSettle();
      expect(find.textContaining('Pediu: "Vomidrine"'), findsOneWidget);
      expect(find.textContaining('tempo até responder: 3 min'), findsOneWidget);
      expect(find.textContaining('Receita'), findsNothing, reason: 'as receitas ficam na outra aba');
    });

    test('o menu do painel tem "Pedidos especiais das farmácias"', () {
      final item = adminMenuAllItems().where((i) => i.id == 'farmacias_pedidos_especiais');
      expect(item, hasLength(1));
      expect(item.first.title, 'Pedidos especiais das farmácias');
    });
  });
}
