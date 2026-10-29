import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/substituicao_service.dart';
import 'package:bora_app/widgets/admin/admin_substituicao_section.dart';
import 'package:bora_app/widgets/substituicao_seletor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C7 (adendo 5, item 7, 29/10/2026) — o estafeta vê a escolha do cliente na
/// lista de compras e o admin vê-a (com as devoluções) no detalhe do pedido.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrderModel.fromSupabase lê substitution_preference', () {
    Map<String, dynamic> linha([Map<String, dynamic> extra = const {}]) => {
          'id': '00000000-0000-0000-0000-000000000007',
          'status': 'driverAccepted',
          'service_type': 'storeShopping',
          'payment_method': 'card',
          'price': 12.5,
          'items': const [],
          ...extra,
        };

    test('sem a coluna (migração por aplicar) fica null e nada se parte', () {
      expect(OrderModel.fromSupabase(linha()).substitutionPreference, isNull);
    });

    test('com a escolha do cliente, lê o código', () {
      final o = OrderModel.fromSupabase(
          linha({'substitution_preference': 'tirar_devolver'}));
      expect(o.substitutionPreference, 'tirar_devolver');
    });
  });

  group('SubstituicaoLinhaEstafeta (lista de compras)', () {
    Widget app(String? pref) => MaterialApp(
          home: Scaffold(body: SubstituicaoLinhaEstafeta(preferencia: pref)),
        );

    testWidgets('sem escolha do cliente não desenha nada', (t) async {
      for (final vazio in <String?>[null, '', 'qualquer']) {
        await t.pumpWidget(app(vazio));
        expect(
            find.byKey(const Key('substituicao_linha_estafeta')), findsNothing,
            reason: 'pref=$vazio');
      }
    });

    testWidgets('cada escolha mostra a sua frase', (t) async {
      for (final e in SubstituicaoEscolha.values) {
        await t.pumpWidget(app(e.codigo));
        expect(find.byKey(const Key('substituicao_linha_estafeta')),
            findsOneWidget,
            reason: e.codigo);
        expect(find.text(e.fraseEstafeta), findsOneWidget, reason: e.codigo);
      }
      expect(SubstituicaoEscolha.trocar.fraseEstafeta,
          'Se faltar um produto, o cliente quer: trocar por um parecido.');
      expect(SubstituicaoEscolha.tirarDevolver.fraseEstafeta,
          'Se faltar um produto, o cliente quer: tirar do pedido (marca "não há").');
      expect(SubstituicaoEscolha.ligar.fraseEstafeta,
          'Se faltar um produto, o cliente quer: falar contigo no chat, com foto.');
    });

    testWidgets('a linha é laranja (a cor de destaque da app)', (t) async {
      await t.pumpWidget(app('ligar'));
      final caixa = t.widget<Container>(
          find.byKey(const Key('substituicao_linha_estafeta')));
      final deco = caixa.decoration! as BoxDecoration;
      final borda = (deco.border! as Border).top.color;
      // O laranja Bora (F97316): vermelho alto, verde médio, azul baixo.
      expect(borda.r, greaterThan(0.85));
      expect(borda.g, inInclusiveRange(0.3, 0.6));
      expect(borda.b, lessThan(0.25));
    });
  });

  group('AdminSubstituicaoSection (detalhe do pedido, PT-BR)', () {
    Widget app(Map<String, dynamic> pedido, DadosSubstituicao dados) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSubstituicaoSection(
                order: pedido,
                carregar: () async => dados,
              ),
            ),
          ),
        );

    testWidgets('sem escolha e sem produto em falta não mostra nada',
        (t) async {
      await t.pumpWidget(app({'id': 'o1'}, const DadosSubstituicao()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_substituicao_cartao')), findsNothing);
    });

    testWidgets('um reembolso de cancelamento sozinho não é desta secção',
        (t) async {
      await t.pumpWidget(app({
        'id': 'o1',
        'refund_amount': 9.5,
        'refund_status': 'refunded',
      }, const DadosSubstituicao()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_substituicao_cartao')), findsNothing);
    });

    testWidgets('mostra a escolha do cliente', (t) async {
      await t.pumpWidget(
          app({'id': 'o1'}, const DadosSubstituicao(preferencia: 'trocar')));
      await t.pumpAndSettle();
      expect(
          find.byKey(const Key('admin_substituicao_cartao')), findsOneWidget);
      expect(find.text('Preferência se faltar produto: Trocar por um parecido'),
          findsOneWidget);
      expect(find.byKey(const Key('admin_substituicao_tirados')), findsNothing);
      expect(find.byKey(const Key('admin_substituicao_credito')), findsNothing);
    });

    testWidgets('mostra os produtos tirados, o crédito e o reembolso',
        (t) async {
      await t.pumpWidget(app(
        {
          'id': 'o1',
          'refund_amount': 3.5,
          'refund_status': 'refunded',
          'refund_method': 'stripe',
        },
        const DadosSubstituicao(
          preferencia: 'tirar_devolver',
          itensTirados: [
            ItemTirado(nome: 'Leite meio-gordo', quantidade: 2, centimos: 198),
            ItemTirado(nome: 'Pão', quantidade: 1, centimos: 0),
          ],
          creditos: [CreditoPorFalta(centimos: 198)],
        ),
      ));
      await t.pumpAndSettle();

      expect(
          find.text(
              'Preferência se faltar produto: Tirar do pedido e devolver o valor'),
          findsOneWidget);
      expect(find.text('Produtos tirados do pedido (€1,98):'), findsOneWidget);
      expect(find.text('2× Leite meio-gordo · €1,98'), findsOneWidget);
      expect(find.text('1× Pão'), findsOneWidget);
      expect(find.text('Devoluções feitas:'), findsOneWidget);
      expect(find.text('Crédito no saldo Bora por produto em falta: €1,98'),
          findsOneWidget);
      expect(find.text('Reembolso do pedido: €3,50 · refunded · stripe'),
          findsOneWidget);
    });

    testWidgets(
        'cliente sem escolha mas com produto em falta: diz que não escolheu',
        (t) async {
      await t.pumpWidget(app(
        {'id': 'o1'},
        const DadosSubstituicao(itensTirados: [
          ItemTirado(nome: 'Arroz', quantidade: 1, centimos: 129),
        ]),
      ));
      await t.pumpAndSettle();
      expect(find.text('Preferência se faltar produto: o cliente não escolheu'),
          findsOneWidget);
      expect(find.text('Produtos tirados do pedido (€1,29):'), findsOneWidget);
    });

    testWidgets('a leitura falha: não desenha nada e não rebenta', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminSubstituicaoSection(
            order: const {'id': 'o1'},
            carregar: () async => throw Exception('sem rede'),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('admin_substituicao_cartao')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('AdminSubstituicaoSection.itensTiradosDaLista', () {
    test('lê só os marcados "unavailable", com o valor da linha', () {
      final itens = AdminSubstituicaoSection.itensTiradosDaLista([
        {
          'name': 'Leite',
          'price': 0.99,
          'quantity': 2,
          'purchaseStatus': 'unavailable'
        },
        {
          'name': 'Pão',
          'price': 0.5,
          'quantity': 1,
          'purchaseStatus': 'bought'
        },
        {'name': 'Ovos', 'price': 2.1, 'purchase_status': 'unavailable'},
        'lixo',
      ]);
      expect(itens.map((i) => i.nome), ['Leite', 'Ovos']);
      expect(itens[0].quantidade, 2);
      expect(itens[0].centimos, 198);
      expect(itens[1].quantidade, 1);
      expect(itens[1].centimos, 210);
    });

    test('lista ausente ou de outro tipo dá vazio', () {
      expect(AdminSubstituicaoSection.itensTiradosDaLista(null), isEmpty);
      expect(AdminSubstituicaoSection.itensTiradosDaLista('x'), isEmpty);
    });

    test('euros: vírgula e duas casas', () {
      expect(AdminSubstituicaoSection.euros(198), '€1,98');
      expect(AdminSubstituicaoSection.euros(5), '€0,05');
      expect(AdminSubstituicaoSection.euros(1000), '€10,00');
    });
  });
}
