// FARMÁCIAS PARCEIRAS (14/11/2026, AUTORIZO do Danilo): a conta do carrinho
// antes do quote do servidor tem de bater com o ramo farmácia do
// `pricing_calculate_loja` — taxa de serviço 0,99 € + 5 % numa linha só, sem
// saco e sem markup oculto. As outras lojas parceiras ficam como estavam.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
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
  cart.addItem(CartItem(
    productId: 'p-$loja',
    name: 'Produto',
    price: preco,
    basePrice: preco,
  ));
  return cart;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('farmácia parceira: serviço 0,99 + 5 % (8 € → 1,39), sem saco nem markup',
      () {
    SmallOrderFeeService.definirFarmaciaParaTeste('farm-teste',
        taxaFixaCents: 99, taxaPct: 0.05);
    final b = _cesto('farm-teste', 8).pricingBreakdown;
    expect(b.serviceFee, 1.39);
    expect(b.bagFee, 0);
    expect(b.partnerMarkupHidden, 0);
    expect(b.platformCommission, 0);
  });

  test('farmácia parceira: 25 € → serviço 2,24', () {
    SmallOrderFeeService.definirFarmaciaParaTeste('farm-25',
        taxaFixaCents: 99, taxaPct: 0.05);
    expect(_cesto('farm-25', 25).pricingBreakdown.serviceFee, 2.24);
  });

  test('outra loja parceira: continua 5 % e com saco', () {
    SmallOrderFeeService.definirFarmaciaParaTeste('loja-normal',
        farmacia: false, taxaFixaCents: 99, taxaPct: 0.05);
    final b = _cesto('loja-normal', 8).pricingBreakdown;
    expect(b.serviceFee, 0.40);
    expect(b.bagFee, greaterThan(0));
  });

  test('definições da farmácia ainda por ler: fica o valor do PricingService',
      () {
    SmallOrderFeeService.definirFarmaciaParaTeste('farm-sem-defs');
    expect(_cesto('farm-sem-defs', 8).pricingBreakdown.serviceFee, 0.40);
  });
}
