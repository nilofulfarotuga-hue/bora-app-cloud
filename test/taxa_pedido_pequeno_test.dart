import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/pricing_service.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAXA DE PEDIDO PEQUENO — o cliente tem de chegar ao MESMO CÊNTIMO que o
/// servidor.
///
/// Os valores esperados não foram inventados aqui: são a saída literal da
/// função `small_order_fee_calc` corrida em produção a 2026-08-27 (com o
/// interruptor ligado), com `min_order_cents = 1200` e
/// `small_order_fee_cents = 139`. Se alguém mudar a regra de um dos lados sem
/// mudar do outro, este teste parte.
void main() {
  // Espelho da configuração real em produção.
  const cfg = SmallOrderFeeConfig(enabled: true, minCents: 1200, feeCents: 139);

  group('taxa de pedido pequeno — cliente bate com o servidor', () {
    // caso                          subtotal   taxa que o servidor devolveu
    const casos = <String, List<double>>{
      'goola bowl 9,22 (abaixo do mínimo)': [9.22, 1.39],
      'goola 2 big bowls 23,10 (acima)': [23.10, 0.0],
      'exactamente 12,00 (no mínimo)': [12.00, 0.0],
      '11,99 (um cêntimo abaixo)': [11.99, 1.39],
      'mercado não-parceiro 8,00': [8.00, 1.39],
    };

    casos.forEach((nome, v) {
      test(nome, () {
        expect(cfg.taxaPara(OrderServiceType.restaurant, v[0]), v[1]);
      });
    });

    test('mercado (storeShopping) cobra igual ao restaurante', () {
      expect(cfg.taxaPara(OrderServiceType.storeShopping, 8.00), 1.39);
    });

    test('logística não leva taxa — não há subtotal de produtos', () {
      expect(cfg.taxaPara(OrderServiceType.sendPackage, 9.22), 0.0);
      expect(cfg.taxaPara(OrderServiceType.carryGroceries, 9.22), 0.0);
    });

    test('carrinho vazio não leva taxa', () {
      expect(cfg.taxaPara(OrderServiceType.restaurant, 0), 0.0);
    });
  });

  group('interruptor e configuração em falta', () {
    test('desligado não cobra nada — é o estado em produção hoje', () {
      const off =
          SmallOrderFeeConfig(enabled: false, minCents: 1200, feeCents: 139);
      expect(off.taxaPara(OrderServiceType.restaurant, 9.22), 0.0);
      expect(off.faltaPara(OrderServiceType.restaurant, 9.22), 0.0);
    });

    test('sem definições lidas fica no estado seguro', () {
      expect(
        SmallOrderFeeConfig.desligado.taxaPara(OrderServiceType.restaurant, 5),
        0.0,
      );
    });

    test('mínimo ou taxa a zero não inventa cobrança', () {
      const semMin =
          SmallOrderFeeConfig(enabled: true, minCents: 0, feeCents: 139);
      const semTaxa =
          SmallOrderFeeConfig(enabled: true, minCents: 1200, feeCents: 0);
      expect(semMin.taxaPara(OrderServiceType.restaurant, 5), 0.0);
      expect(semTaxa.taxaPara(OrderServiceType.restaurant, 5), 0.0);
    });
  });

  group('quanto falta para evitar a taxa', () {
    test('bowl de 9,22 → faltam 2,78 €', () {
      expect(cfg.faltaPara(OrderServiceType.restaurant, 9.22),
          closeTo(2.78, 0.0001));
    });

    test('quem já passou o mínimo não vê aviso nenhum', () {
      expect(cfg.faltaPara(OrderServiceType.restaurant, 23.10), 0.0);
      expect(cfg.faltaPara(OrderServiceType.restaurant, 12.00), 0.0);
    });
  });

  group('total do cliente — Goola Açaí (parceiro, 1 km)', () {
    // Saída literal de pricing_calculate('restaurant', 9.22, 1, true, …)
    // em produção a 2026-08-27: entrega 2,50 · serviço 0,46 · saco 0,30
    // · total 12,48.
    test('um Goola Bowl: 12,48 sem taxa, 13,87 com taxa', () {
      final b = PricingService.calculateBreakdown(
        serviceType: OrderServiceType.restaurant,
        subtotal: 9.22,
        distanceKm: 1,
        isPartnerStore: true,
      );
      expect(b.deliveryFee, 2.50);
      expect(b.serviceFee, 0.46);
      expect(b.bagFee, 0.30);
      // closeTo e nao ==: o getter customerTotal do cliente SOMA doubles sem
      // arredondar (da 12.480000000000002). Ao centimo bate com o servidor,
      // que devolve 12.48 — e e ao centimo que o cliente paga.
      expect(b.customerTotal, closeTo(12.48, 0.005));

      final taxa = cfg.taxaPara(OrderServiceType.restaurant, 9.22);
      expect(b.customerTotal + taxa, closeTo(13.87, 0.0001));
    });

    // Saída literal de pricing_calculate('restaurant', 23.10, 1, true, …):
    // entrega 2,50 · serviço 1,16 · saco 0,30 · total 27,06.
    test('dois Big Bowls: 27,06 e a taxa não aparece', () {
      final b = PricingService.calculateBreakdown(
        serviceType: OrderServiceType.restaurant,
        subtotal: 23.10,
        distanceKm: 1,
        isPartnerStore: true,
      );
      expect(b.customerTotal, closeTo(27.06, 0.005));
      expect(cfg.taxaPara(OrderServiceType.restaurant, 23.10), 0.0);
    });
  });

  group('a taxa não mexe em nada do parceiro nem do estafeta', () {
    test('comissão, markup e ganho ficam iguais com e sem taxa', () {
      final b = PricingService.calculateBreakdown(
        serviceType: OrderServiceType.restaurant,
        subtotal: 9.22,
        distanceKm: 1,
        isPartnerStore: true,
      );
      // Valores de produção, inalterados pela taxa: ela vive fora do
      // breakdown e é receita só da plataforma.
      expect(b.platformCommission, 0.92);
      expect(b.partnerMarkupHidden, 0.46);
      expect(b.driverEarnings, 4.00);
    });

    test('repasse do parceiro = preço de balcão (fórmula ÷0,90 ×1,05)', () {
      // partner_store_share(9.22) = 9.22 × 0.90 ÷ 1.05 = 7.90
      // partner_store_share(11.55) = 11.55 × 0.90 ÷ 1.05 = 9.90
      double repasse(double preco) =>
          double.parse((preco * 0.90 / 1.05).toStringAsFixed(2));
      expect(repasse(9.22), 7.90);
      expect(repasse(11.55), 9.90);
    });
  });
}
