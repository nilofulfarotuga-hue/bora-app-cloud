// Missão farmacia-rego-2026-11-23, Adendo 2 (AUTORIZO do Danilo 23/11 13:36): farmácia com
// margem dentro do preço (Farmácia Rêgo) — conta do carrinho antes do quote e painel admin.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/screens/admin/admin_farmacia_taxas.dart';
import 'package:bora_app/services/admin_farmacias_service.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CartStore _cesto(String loja, double preco) {
  final cart = CartStore()
    ..configureSession(
      serviceType: OrderServiceType.storeShopping,
      isPartnerStore: true,
      vendorName: 'Loja $loja',
      vendorRestaurantId: loja,
    );
  cart.addItem(CartItem(productId: 'p-$loja', name: 'Produto', price: preco, basePrice: preco));
  return cart;
}

TaxasFarmacia _taxas({double? margem, int? minimo, int? taxa}) => TaxasFarmacia(
      margem: margem,
      pedidoMinimoCents: minimo,
      taxaPedidoPequenoCents: taxa,
      pedidoMinimoGeralCents: 1500,
      taxaPedidoPequenoGeralCents: 139,
      taxaServicoPct: 0.05,
      taxaServicoFixaFarmaciasCents: 99,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('carrinho (conta antes do quote)', () {
    test('farmácia com margem: 11,50 € → serviço 0,58 (só 5 %, sem os 0,99)', () {
      SmallOrderFeeService.definirFarmaciaParaTeste('farmacia-rego-guarda',
          taxaFixaCents: 99, taxaPct: 0.05, comMargem: true);
      final b = _cesto('farmacia-rego-guarda', 11.50).pricingBreakdown;
      expect(b.serviceFee, 0.58);
      expect(b.bagFee, 0);
    });

    test('farmácia sem margem continua 0,99 + 5 % (8 € → 1,39)', () {
      SmallOrderFeeService.definirFarmaciaParaTeste('farmacia-se-guarda', taxaFixaCents: 99, taxaPct: 0.05);
      expect(_cesto('farmacia-se-guarda', 8).pricingBreakdown.serviceFee, 1.39);
    });

    test('taxaServicoFarmacia sem loja ignora a margem (compatível com quem já chamava)', () {
      SmallOrderFeeService.definirFarmaciaParaTeste('farmacia-rego-guarda',
          taxaFixaCents: 99, taxaPct: 0.05, comMargem: true);
      expect(SmallOrderFeeService.taxaServicoFarmacia(10), 1.49);
      expect(SmallOrderFeeService.taxaServicoFarmacia(10, restaurantId: 'farmacia-rego-guarda'), 0.50);
    });
  });

  group('painel admin — taxas da farmácia', () {
    test('lerPercentagem', () {
      expect(lerPercentagem('15'), 0.15);
      expect(lerPercentagem('15 %'), 0.15);
      expect(lerPercentagem('12,5'), 0.125);
      expect(lerPercentagem(''), isNull);
      expect(lerPercentagem('80')!.isNaN, isTrue);
      expect(lerPercentagem('abc')!.isNaN, isTrue);
    });

    test('lerEurosCents', () {
      expect(lerEurosCents('1,39'), 139);
      expect(lerEurosCents('15'), 1500);
      expect(lerEurosCents(' '), isNull);
      expect(lerEurosCents('x'), -1);
    });

    test('linhas: com margem diz a margem e o pedido pequeno geral', () {
      final l = linhasTaxasFarmacia(_taxas(margem: 0.15));
      expect(l.first, contains('15 %'));
      expect(l.first, contains('farmácia recebe o balcão'));
      expect(l[1], contains('1,39 € abaixo de 15,00 €'));
      expect(l[1], contains('valores gerais'));
    });

    test('linhas: sem margem e com valor da loja', () {
      final l = linhasTaxasFarmacia(_taxas(minimo: 1000, taxa: 99));
      expect(l.first, startsWith('Sem margem'));
      expect(l[1], contains('0,99 € abaixo de 10,00 €'));
      expect(l[1], contains('valor desta loja'));
    });

    test('exemplo do servidor: a conta da Bora (AUTORIZO 23/11)', () {
      final ex = ExemploTaxasFarmacia.deServidor(
        balcao: 10,
        subtotal: 11.50,
        linha: {
          'service_fee': 0.58,
          'delivery_fee': 2.50,
          'bag_fee': 0,
          'customer_total': 14.58,
          'driver_earnings': 4.20,
        },
        pedidoPequeno: 1.39,
        farmaciaRecebe: 10.00,
      );
      expect(ex.clientePaga, closeTo(15.97, 0.001));
      expect(ex.bora, 1.77);
    });
  });
}
