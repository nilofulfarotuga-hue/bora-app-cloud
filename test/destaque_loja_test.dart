// "Hambúrguer do mês" — produto em destaque no topo da loja (02/11/2026,
// missão boom-hamburguer-mes, bloco C). Sem rede:
//   - DestaqueLoja.daLinha lê restaurants.produto_destaque_id/_rotulo;
//   - o cartão grande mostra selo, nome, preço (PricingService) e "Adicionar";
//     loja fechada não adiciona;
//   - o editor (parceiro PT-PT / admin PT-BR) guarda, tira e mostra o estado.
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/services/destaque_loja_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/editor_destaque_loja.dart';
import 'package:bora_app/widgets/produto_destaque_loja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

const _cafeParis = PartnerProduct(
  id: 'f2ac93d2-9e77-4f02-8cbe-11a17ce91b32',
  restaurantId: 'boom-burger-guarda',
  name: 'Boom! Café de Paris',
  description: 'Hambúrguer do mês. Pão brioche com sementes sésamo',
  price: 16.10,
  photoUrl: '',
  isAvailable: true,
);

Widget _comCarrinho(Widget filho, {CartStore? cart}) =>
    ChangeNotifierProvider<CartStore>.value(
      value: cart ?? CartStore(),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: filho))),
    );

void main() {
  group('DestaqueLoja.daLinha', () {
    test('com produto e selo', () {
      final d = DestaqueLoja.daLinha({
        'produto_destaque_id': _cafeParis.id,
        'produto_destaque_rotulo': 'Hambúrguer do mês',
      })!;
      expect(d.produtoId, _cafeParis.id);
      expect(d.rotulo, 'Hambúrguer do mês');
    });
    test('selo vazio volta ao de defeito; sem produto = sem destaque', () {
      expect(
          DestaqueLoja.daLinha({'produto_destaque_id': 'x', 'produto_destaque_rotulo': ' '})!
              .rotulo,
          DestaqueLoja.rotuloPorDefeito);
      expect(DestaqueLoja.daLinha({'produto_destaque_id': null}), isNull);
      expect(DestaqueLoja.daLinha(null), isNull);
    });
  });

  group('cartão grande no topo da loja', () {
    testWidgets('selo, nome, preço e Adicionar', (t) async {
      var adicionados = 0;
      await t.pumpWidget(_comCarrinho(ProdutoDestaqueLoja(
        product: _cafeParis,
        rotulo: 'Hambúrguer do mês',
        isPartnerStore: true,
        onAdd: () => adicionados++,
      )));
      await t.pump();
      expect(find.text('🔥 Hambúrguer do mês'), findsOneWidget);
      expect(find.text('Boom! Café de Paris'), findsOneWidget);
      // parceiro: preço puro, sem markup (PricingService.applyMarkup)
      expect(find.textContaining('16,10'), findsOneWidget);
      await t.tap(find.byKey(const Key('produto_destaque_adicionar')));
      await t.pump();
      expect(adicionados, 1);
    });

    testWidgets('loja fechada: o botão não adiciona', (t) async {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: true,
          vendorName: 'Boom! Burger',
          vendorRestaurantId: 'boom-burger-guarda',
          vendorFechada: true,
          vendorAvisoFechada: 'A Boom! Burger está fechada agora.',
          pickupLocation: const LatLng(40.5373, -7.2676),
          deliveryLocation: const LatLng(40.5420, -7.2700),
          dropoffStreet: 'Rua do Comércio 1',
          dropoffCity: 'Guarda',
        );
      expect(cart.lojaFechada, isTrue);
      var adicionados = 0;
      await t.pumpWidget(_comCarrinho(
          ProdutoDestaqueLoja(
            product: _cafeParis,
            rotulo: 'Hambúrguer do mês',
            isPartnerStore: true,
            onAdd: () => adicionados++,
          ),
          cart: cart));
      await t.pump();
      await t.tap(find.byKey(const Key('produto_destaque_adicionar')));
      await t.pump();
      expect(adicionados, 0);
    });
  });

  group('editor do destaque (painéis)', () {
    const produtos = [
      ProdutoEscolhivel('f2ac93d2-9e77-4f02-8cbe-11a17ce91b32', 'Boom! Café de Paris'),
      ProdutoEscolhivel('boom-bombastico', 'Boom! Bombástico'),
    ];

    testWidgets('mostra o estado e guarda o produto escolhido', (t) async {
      final chamadas = <List<String?>>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditorDestaqueLoja(
              produtos: produtos,
              inicial: const DestaqueLoja(
                  produtoId: 'f2ac93d2-9e77-4f02-8cbe-11a17ce91b32',
                  rotulo: 'Hambúrguer do mês'),
              onGuardar: (id, rotulo) async => chamadas.add([id, rotulo]),
            ),
          ),
        ),
      ));
      expect(find.text('Boom! Café de Paris · Hambúrguer do mês'), findsOneWidget);
      await t.tap(find.text('🔥 Produto em destaque'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('editor_destaque_guardar')));
      await t.pumpAndSettle();
      expect(chamadas.single, ['f2ac93d2-9e77-4f02-8cbe-11a17ce91b32', 'Hambúrguer do mês']);
      expect(find.text('Destaque guardado.'), findsOneWidget);
    });

    testWidgets('tirar manda produto nulo', (t) async {
      final chamadas = <List<String?>>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditorDestaqueLoja(
              produtos: produtos,
              inicial: const DestaqueLoja(
                  produtoId: 'boom-bombastico', rotulo: 'Hambúrguer do mês'),
              onGuardar: (id, rotulo) async => chamadas.add([id, rotulo]),
              textos: EditorDestaqueTextos.admin,
            ),
          ),
        ),
      ));
      await t.tap(find.text('🔥 Produto em destaque'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('editor_destaque_tirar')));
      await t.pumpAndSettle();
      expect(chamadas.single.first, isNull);
      expect(find.text('Destaque removido.'), findsOneWidget);
    });

    testWidgets('sem destaque: diz "Sem destaque" e não oferece tirar', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditorDestaqueLoja(
              produtos: produtos,
              inicial: null,
              onGuardar: (_, __) async {},
            ),
          ),
        ),
      ));
      expect(find.byKey(const Key('editor_destaque_estado')), findsOneWidget);
      expect(find.text('Sem destaque'), findsOneWidget);
      await t.tap(find.text('🔥 Produto em destaque'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('editor_destaque_tirar')), findsNothing);
    });
  });
}
