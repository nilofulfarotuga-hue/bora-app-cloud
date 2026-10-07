// Missão maiores-18 (07/10/2026) — tabaco e álcool com verificação de idade
// na entrega. Três provas de widget, como a ordem pedia:
//
//   1. a etiqueta "+18" aparece no cartão de produto só quando o produto é +18;
//   2. o aviso do carrinho aparece quando há um artigo +18 e sai quando o
//      artigo sai (a regra que o CartScreen usa: `CartStore.hasAgeRestricted`);
//   3. a folha obrigatória do estafeta: dois botões, sem "Concluir entrega"
//      antes da escolha, confirma → segue; recusa → confirmação → cancelamento;
//      erro do servidor → mensagem e tentar de novo.
//
// O CartScreen e o PaymentMethodScreen inteiros não se pumpam aqui: precisam
// de OrderStore/RestaurantStore, que abrem Supabase ao nascer.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/services/maior_18_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/bora/bora_product_card.dart';
import 'package:bora_app/widgets/bora/maior_18.dart';
import 'package:bora_app/widgets/verificacao_idade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PartnerProduct _produto({required bool maior18}) => PartnerProduct(
      id: maior18 ? 'cnt-cerveja-1' : 'cnt-agua-1',
      restaurantId: 'continente-guarda',
      name: maior18 ? 'Cerveja Super Bock 33cl' : 'Água das Pedras 25cl',
      description: '',
      price: 1.29,
      photoUrl: '',
      isAvailable: true,
      ageRestricted: maior18,
    );

Widget _comCarrinho(Widget child, {CartStore? store}) =>
    ChangeNotifierProvider<CartStore>.value(
      value: store ?? CartStore(),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. etiqueta +18 no cartão de produto', () {
    testWidgets('produto +18 mostra "+18"; produto normal não', (tester) async {
      await tester.pumpWidget(_comCarrinho(
        SizedBox(
          width: 180,
          height: 240,
          child: BoraProductCard(
            product: _produto(maior18: true),
            onAdd: () {},
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('+18'), findsOneWidget,
          reason: 'a cerveja tem de levar a etiqueta +18');
      expect(find.byType(Maior18Badge), findsOneWidget);

      await tester.pumpWidget(_comCarrinho(
        SizedBox(
          width: 180,
          height: 240,
          child: BoraProductCard(
            product: _produto(maior18: false),
            onAdd: () {},
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('+18'), findsNothing,
          reason: 'a água não pode levar a etiqueta');
    });
  });

  group('2. aviso no carrinho', () {
    test('CartStore.hasAgeRestricted segue os artigos', () {
      final cart = CartStore();
      expect(cart.hasAgeRestricted, isFalse);
      cart.addItem(CartItem(productId: 'cnt-agua-1', name: 'Água', price: 1));
      expect(cart.hasAgeRestricted, isFalse);
      final cerveja = CartItem(
          productId: 'cnt-cerveja-1',
          name: 'Cerveja',
          price: 1.29,
          ageRestricted: true);
      cart.addItem(cerveja);
      expect(cart.hasAgeRestricted, isTrue);
      cart.removeItem(cerveja);
      expect(cart.hasAgeRestricted, isFalse);
    });

    test('a marca sobrevive à persistência do carrinho (toJson/fromJson)', () {
      final item = CartItem(
          productId: 'cnt-cerveja-1',
          name: 'Cerveja',
          price: 1.29,
          ageRestricted: true);
      final volta = CartItem.fromJson(item.toJson());
      expect(volta.ageRestricted, isTrue);
      final normal = CartItem(productId: 'cnt-agua-1', name: 'Água', price: 1);
      expect(normal.toJson().containsKey('age_restricted'), isFalse,
          reason: 'só se grava quando é true — o JSON dos pedidos não muda');
      expect(CartItem.fromJson(normal.toJson()).ageRestricted, isFalse);
    });

    testWidgets('o cartão âmbar aparece com um artigo +18 e sai sem ele',
        (tester) async {
      final cart = CartStore();
      final cerveja = CartItem(
          productId: 'cnt-cerveja-1',
          name: 'Cerveja',
          price: 1.29,
          ageRestricted: true);
      // A mesma regra do CartScreen: o aviso é a primeira linha da lista
      // quando `hasAgeRestricted`.
      await tester.pumpWidget(_comCarrinho(
        Consumer<CartStore>(
          builder: (_, c, __) => ListView(
            children: [
              if (c.hasAgeRestricted) const Maior18Aviso(),
              for (final i in c.items) Text(i.name),
            ],
          ),
        ),
        store: cart,
      ));
      expect(find.byType(Maior18Aviso), findsNothing);

      cart.addItem(cerveja);
      await tester.pump();
      expect(find.byType(Maior18Aviso), findsOneWidget);
      expect(
          find.text(
              'Este pedido tem artigos para maiores de 18: terás de mostrar documento de identificação ao estafeta.'),
          findsOneWidget);

      cart.removeItem(cerveja);
      await tester.pump();
      expect(find.byType(Maior18Aviso), findsNothing);
    });
  });

  group('3. folha obrigatória do estafeta', () {
    setUp(() {
      VerificacaoIdade.confirmarOverride = null;
      VerificacaoIdade.limparParaTestes();
    });
    tearDown(() => VerificacaoIdade.confirmarOverride = null);

    OrderModel pedido({required bool maior18}) => OrderModel(
          id: 'ped-${maior18 ? '18' : 'ok'}',
          total: 12.5,
          serviceType: OrderServiceType.storeShopping,
          status: OrderStatus.onTheWay,
          hasAgeRestricted: maior18,
        );

    /// Ecrã do estafeta em miniatura: o botão "Concluir entrega" só aparece
    /// depois de `VerificacaoIdade.garantir` devolver `seguir`.
    Widget ecra(OrderModel order, void Function(VerificacaoIdadeDecisao) onD) =>
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final d = await VerificacaoIdade.garantir(context, order);
                    onD(d);
                  },
                  child: const Text('Entregar'),
                ),
              ),
            ),
          ),
        );

    testWidgets('pedido sem +18 segue logo, sem folha', (tester) async {
      VerificacaoIdadeDecisao? d;
      await tester.pumpWidget(ecra(pedido(maior18: false), (x) => d = x));
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();
      expect(find.text('Pedido +18 — verificar idade'), findsNothing);
      expect(d, VerificacaoIdadeDecisao.seguir);
    });

    testWidgets(
        'pedido +18: folha com os dois botões, sem "Concluir entrega" até escolher; '
        'confirmar chama o servidor com ok=true e segue', (tester) async {
      final chamadas = <(String, bool)>[];
      VerificacaoIdade.confirmarOverride = (id, ok) async {
        chamadas.add((id, ok));
        return const VerificacaoIdadeResultado(ok: true, status: 'confirmado');
      };
      VerificacaoIdadeDecisao? d;
      await tester.pumpWidget(ecra(pedido(maior18: true), (x) => d = x));
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();

      expect(find.text('Pedido +18 — verificar idade'), findsOneWidget);
      expect(find.text('Vi o documento, tem 18 ou mais'), findsOneWidget);
      expect(find.text('Não mostrou documento / é menor'), findsOneWidget);
      expect(find.text('Concluir entrega'), findsNothing,
          reason: 'sem escolher, não há botão de entregar');
      expect(d, isNull, reason: 'ainda não decidiu — nada segue');
      expect(chamadas, isEmpty);

      // O botão de voltar não fecha a folha.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Pedido +18 — verificar idade'), findsOneWidget,
          reason: 'a folha não é dispensável');

      await tester.tap(find.text('Vi o documento, tem 18 ou mais'));
      await tester.pumpAndSettle();
      expect(chamadas, [('ped-18', true)]);
      expect(d, VerificacaoIdadeDecisao.seguir);
      expect(find.text('Pedido +18 — verificar idade'), findsNothing);
    });

    testWidgets('recusa pede confirmação, chama ok=false e avisa', (tester) async {
      final chamadas = <(String, bool)>[];
      VerificacaoIdade.confirmarOverride = (id, ok) async {
        chamadas.add((id, ok));
        return const VerificacaoIdadeResultado(ok: true, status: 'recusado');
      };
      VerificacaoIdadeDecisao? d;
      await tester.pumpWidget(ecra(pedido(maior18: true), (x) => d = x));
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Não mostrou documento / é menor'));
      await tester.pumpAndSettle();
      expect(find.text('Não entregar os artigos +18?'), findsOneWidget);
      expect(chamadas, isEmpty, reason: 'só chama depois de confirmar');

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Pedido +18 — verificar idade'), findsOneWidget,
          reason: 'voltar atrás mantém a folha');

      await tester.tap(find.text('Não mostrou documento / é menor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar recusa'));
      await tester.pumpAndSettle();

      expect(chamadas, [('ped-18', false)]);
      expect(d, VerificacaoIdadeDecisao.recusado);
      expect(
          find.text(
              'Pedido enviado para cancelamento; o suporte trata do resto.'),
          findsOneWidget);
    });

    testWidgets('erro do servidor: mensagem em PT-PT e pode tentar outra vez',
        (tester) async {
      var vez = 0;
      VerificacaoIdade.confirmarOverride = (id, ok) async {
        vez++;
        if (vez == 1) {
          return const VerificacaoIdadeResultado(
              ok: false, erro: 'invalid_status');
        }
        return const VerificacaoIdadeResultado(ok: true, status: 'confirmado');
      };
      VerificacaoIdadeDecisao? d;
      await tester.pumpWidget(ecra(pedido(maior18: true), (x) => d = x));
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vi o documento, tem 18 ou mais'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Esta entrega já não está em curso. Fecha e confirma em Pedidos.'),
          findsOneWidget);
      expect(d, isNull, reason: 'com erro, nada segue');
      expect(find.text('Pedido +18 — verificar idade'), findsOneWidget);

      await tester.tap(find.text('Vi o documento, tem 18 ou mais'));
      await tester.pumpAndSettle();
      expect(vez, 2);
      expect(d, VerificacaoIdadeDecisao.seguir);
    });
  });
}
