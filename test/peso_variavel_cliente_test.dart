// 31/10/2026 (fecho-pendentes) — produtos ao quilo dos mercados NÃO-parceiros
// (`products.variable_weight`), lado do cliente. Provas puras, sem rede:
//
//   1. AjustePeso.fromMap (linha de order_weight_adjustments) e o texto
//      "1,12 € → 1,40 €";
//   2. a nota "Preço aproximado · o valor final depende do peso" só aparece
//      nos produtos com variableWeight (nota normal, selo do cartão);
//   3. o cartão "Ajustado ao peso" do pedido só mostra linhas que mudaram;
//   4. CartItem / PartnerProduct sem a chave `variable_weight` dão false.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/services/ajustes_peso_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/ajustes_peso_pedido.dart';
import 'package:bora_app/widgets/bora/bora_product_card.dart';
import 'package:bora_app/widgets/bora/peso_variavel_nota.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _frase = 'Preço aproximado · o valor final depende do peso';

Map<String, dynamic> _linha({
  String productId = 'cnt-banana-1',
  String? nome = 'Banana da Madeira',
  Object? qty = 4,
  Object? est = 112,
  Object? novo = 140,
  Object? delta = 28,
}) =>
    <String, dynamic>{
      'id': '0b6f2c1e-0000-4000-8000-000000000001',
      'order_id': '6a1b2c3d-0000-4000-8000-0000000000aa',
      'product_id': productId,
      'item_name': nome,
      'qty': qty,
      'est_base_cents': 97,
      'real_base_cents': 122,
      'est_client_cents': est,
      'new_client_cents': novo,
      'delta_client_cents': delta,
      'driver_user_id': '11111111-2222-4333-8444-555555555555',
      'payment_method': 'cash',
      'settled_via': null,
      'settled_at': null,
      'notified_at': '2026-10-31T10:15:00+00:00',
      'created_at': '2026-10-31T10:14:59.123+00:00',
      'updated_at': '2026-10-31T10:15:00+00:00',
    };

PartnerProduct _produto({required bool pesoVariavel}) => PartnerProduct(
      id: pesoVariavel ? 'cnt-banana-1' : 'cnt-agua-1',
      restaurantId: 'continente-guarda',
      name: pesoVariavel ? 'Banana da Madeira' : 'Água das Pedras 25cl',
      description: '',
      price: 0.28,
      photoUrl: '',
      isAvailable: true,
      variableWeight: pesoVariavel,
    );

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. AjustePeso.fromMap e o texto do ajuste', () {
    test('lê a linha toda da tabela', () {
      final a = AjustePeso.fromMap(_linha());
      expect(a.orderId, '6a1b2c3d-0000-4000-8000-0000000000aa');
      expect(a.productId, 'cnt-banana-1');
      expect(a.itemName, 'Banana da Madeira');
      expect(a.qty, 4);
      expect(a.estBaseCents, 97);
      expect(a.realBaseCents, 122);
      expect(a.estClientCents, 112);
      expect(a.newClientCents, 140);
      expect(a.deltaClientCents, 28);
      expect(a.paymentMethod, 'cash');
      expect(a.settledVia, isNull);
      expect(a.acertado, isFalse);
      expect(a.notifiedAt, DateTime.utc(2026, 10, 31, 10, 15));
      expect(a.createdAt, isNotNull);
      expect(a.mudou, isTrue);
    });

    test('"1,12 € → 1,40 €": vírgula decimal e o símbolo depois', () {
      final a = AjustePeso.fromMap(_linha());
      expect(a.antesTexto, '1,12 €');
      expect(a.depoisTexto, '1,40 €');
      expect(a.deAteTexto, '1,12 € → 1,40 €');
      expect(a.diferencaTexto, '+0,28 €');
      expect(textoDeAteCents(112, 140), '1,12 € → 1,40 €');
      expect(textoDeAteCents(1250, 990), '12,50 € → 9,90 €');
      expect(textoDiferencaCents(-10), '-0,10 €');
      expect(textoDiferencaCents(0), '0,00 €');
    });

    test('tolerante: números em texto/decimal, delta em falta, chaves em falta',
        () {
      final a = AjustePeso.fromMap(_linha(qty: '2', est: '112', novo: 140.0,
          delta: null));
      expect(a.qty, 2);
      expect(a.estClientCents, 112);
      expect(a.newClientCents, 140);
      expect(a.deltaClientCents, 28, reason: 'sem delta faz-se a conta');

      final vazio = AjustePeso.fromMap(const <String, dynamic>{});
      expect(vazio.id, '');
      expect(vazio.qty, 1);
      expect(vazio.estClientCents, 0);
      expect(vazio.newClientCents, 0);
      expect(vazio.itemName, isNull);
      expect(vazio.createdAt, isNull);
      expect(vazio.mudou, isFalse);
    });

    test('deLinhas ignora o que não é mapa; soma e filtro dos mudados', () {
      final lista = AjustesPesoService.deLinhas([
        _linha(),
        'lixo',
        _linha(productId: 'cnt-maca-1', nome: 'Maçã Gala', est: 200, novo: 200,
            delta: 0),
        _linha(productId: 'cnt-pera-1', nome: 'Pêra Rocha', est: 300, novo: 290,
            delta: -10),
      ]);
      expect(lista.length, 3);
      expect(AjustesPesoService.deLinhas(null), isEmpty);
      expect(AjustesPesoService.deLinhas('x'), isEmpty);
      expect(AjustesPesoService.somaDiferencaCents(lista), 18);
      expect(AjustesPesoService.soMudados(lista).map((a) => a.productId),
          ['cnt-banana-1', 'cnt-pera-1']);
    });

    test('o aviso do push sobe o contador e guarda o pedido', () {
      final antes = AjustesPesoService.avisos.value;
      AjustesPesoService.avisarNovoAjuste('pedido-x');
      expect(AjustesPesoService.avisos.value, antes + 1);
      expect(AjustesPesoService.ultimoPedidoAvisado, 'pedido-x');
      expect(kTipoAjustePeso, 'order_weight_adjusted');
    });
  });

  group('2. nota "Preço aproximado"', () {
    testWidgets('aparece com variableWeight; não aparece sem', (tester) async {
      await tester.pumpWidget(_app(const PesoVariavelNota(variableWeight: true)));
      expect(find.text(_frase), findsOneWidget);
      expect(find.byIcon(Icons.scale_outlined), findsOneWidget);

      await tester
          .pumpWidget(_app(const PesoVariavelNota(variableWeight: false)));
      expect(find.text(_frase), findsNothing);
      expect(find.byIcon(Icons.scale_outlined), findsNothing);
    });

    testWidgets('selo compacto: frase curta, sem a frase longa', (tester) async {
      await tester.pumpWidget(_app(const Center(
          child: PesoVariavelNota(variableWeight: true, compacta: true))));
      expect(find.text('Preço aproximado'), findsOneWidget);
      expect(find.text(_frase), findsNothing);
      expect(find.byKey(const Key('peso_variavel_selo')), findsOneWidget);
    });

    testWidgets('cartão de produto: selo só no produto ao quilo', (tester) async {
      Widget cartao(bool pesoVariavel) => ChangeNotifierProvider<CartStore>.value(
            value: CartStore(),
            child: _app(SizedBox(
              width: 180,
              height: 240,
              child: BoraProductCard(
                product: _produto(pesoVariavel: pesoVariavel),
                onAdd: () {},
                onTap: () {},
              ),
            )),
          );

      await tester.pumpWidget(cartao(true));
      await tester.pump();
      expect(find.byKey(const Key('peso_variavel_selo')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'sem overflow no cartão');

      await tester.pumpWidget(cartao(false));
      await tester.pump();
      expect(find.byKey(const Key('peso_variavel_selo')), findsNothing);
    });
  });

  group('3. "Ajustado ao peso" no pedido do cliente', () {
    testWidgets('mostra só as linhas que mudaram', (tester) async {
      await tester.pumpWidget(_app(AjustesPesoLista(ajustes: [
        AjustePeso.fromMap(_linha()),
        AjustePeso.fromMap(_linha(
            productId: 'cnt-maca-1', nome: 'Maçã Gala', est: 200, novo: 200,
            delta: 0)),
      ])));
      expect(find.byKey(const Key('ajustes_peso_pedido')), findsOneWidget);
      expect(find.text('4× Banana da Madeira'), findsOneWidget);
      expect(find.text('Ajustado ao peso: 1,12 € → 1,40 €'), findsOneWidget);
      expect(find.textContaining('Maçã Gala'), findsNothing,
          reason: 'voltou ao preço previsto: não há nada a dizer');
    });

    testWidgets('sem linhas (ou só sem mudança) não desenha nada',
        (tester) async {
      await tester.pumpWidget(_app(const AjustesPesoLista(ajustes: [])));
      expect(find.byKey(const Key('ajustes_peso_pedido')), findsNothing);

      await tester.pumpWidget(_app(AjustesPesoLista(ajustes: [
        AjustePeso.fromMap(_linha(est: 150, novo: 150, delta: 0)),
      ])));
      expect(find.byKey(const Key('ajustes_peso_pedido')), findsNothing);
      expect(find.textContaining('Ajustado ao peso'), findsNothing);
    });

    test('a linha no formato pedido', () {
      expect(AjustesPesoLista.linha(AjustePeso.fromMap(_linha())),
          'Ajustado ao peso: 1,12 € → 1,40 €');
    });
  });

  group('4. modelos sem a chave dão false', () {
    test('CartItem.fromJson sem variable_weight → false; com true → true', () {
      final antigo = CartItem.fromJson(<String, dynamic>{
        'productId': 'cnt-banana-1',
        'name': 'Banana da Madeira',
        'price': 0.32,
        'quantity': 4,
      });
      expect(antigo.variableWeight, isFalse);

      final novo = CartItem.fromJson(<String, dynamic>{
        'productId': 'cnt-banana-1',
        'name': 'Banana da Madeira',
        'price': 0.32,
        'quantity': 4,
        'variable_weight': true,
      });
      expect(novo.variableWeight, isTrue);
    });

    test('CartItem.toJson só grava a chave nova quando é true', () {
      final normal =
          CartItem(productId: 'cnt-agua-1', name: 'Água', price: 0.5);
      expect(normal.variableWeight, isFalse);
      expect(normal.toJson().containsKey('variable_weight'), isFalse,
          reason: 'o formato antigo de orders.items fica igual');

      final aoQuilo = CartItem(
          productId: 'cnt-banana-1',
          name: 'Banana',
          price: 0.32,
          variableWeight: true);
      expect(aoQuilo.toJson()['variable_weight'], isTrue);
      expect(CartItem.fromJson(aoQuilo.toJson()).variableWeight, isTrue);
    });

    test('PartnerProduct: default false, linha sem a coluna → false', () {
      expect(_produto(pesoVariavel: false).variableWeight, isFalse);
      expect(
          const PartnerProduct(
            id: 'p',
            restaurantId: 'r',
            name: 'n',
            description: '',
            price: 1,
            photoUrl: '',
            isAvailable: true,
          ).variableWeight,
          isFalse);
      expect(pesoVariavelDaLinha(const <String, dynamic>{}), isFalse);
      expect(pesoVariavelDaLinha(const <String, dynamic>{'variable_weight': null}),
          isFalse);
      expect(pesoVariavelDaLinha(const <String, dynamic>{'variable_weight': true}),
          isTrue);
      final copia = _produto(pesoVariavel: true).copyWith(name: 'Banana');
      expect(copia.variableWeight, isTrue, reason: 'copyWith não perde o campo');
    });
  });
}
