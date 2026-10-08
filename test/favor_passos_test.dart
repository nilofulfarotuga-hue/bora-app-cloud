// Favores (08/10/2026, pedido real 74dd4ecc da Cristina) — a rota do
// estafeta e o valor a cobrar. Cada teste falha no código de antes:
//  - sem paragem gravada, o passo 1 (casa) desaparecia;
//  - o "pickup_address" herdado ("Rua do Ferrinho") aparecia no favor;
//  - "Cobrar ao cliente" lia o valor estimado (12,00) em vez do talão (9,88);
//  - o mapa ia para o pickup em vez do passo atual.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/route_optimizer.dart';
import 'package:bora_app/utils/favor_passos.dart';
import 'package:bora_app/widgets/folha_favor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _casa = LatLng(40.5370, -7.2680);
const _farmacia = LatLng(40.5420, -7.2560);
const _ferrinho = LatLng(40.5300, -7.2900);

OrderModel favor({
  OrderStatus status = OrderStatus.driverAccepted,
  bool homeStop = true,
  String? homeAddress,
  double? homeLat,
  double? homeLng,
  int? passo,
  bool hasPurchase = true,
  bool finalizado = false,
  double total = 12.00,
  double? finalTotal,
  double? cashTotalDue,
  PaymentMethod pagamento = PaymentMethod.cash,
  String descricao = 'Vai à farmácia e compra castillium 10mg',
}) {
  return OrderModel(
    id: '74dd4ecc-6d33-4b93-b404-1c70dc8cf0f9',
    total: total,
    serviceType: OrderServiceType.errand,
    status: status,
    paymentMethod: pagamento,
    customerName: 'Cristina Silva',
    errandDescription: descricao,
    errandLocation: 'Farmácia Tavares, Avenida Cidade de Safed, Guarda, Portugal',
    errandLocationLat: _farmacia.latitude,
    errandLocationLng: _farmacia.longitude,
    errandHomeStop: homeStop,
    errandHomeStopReason: 'outro',
    errandHomeStopAddress: homeAddress,
    errandHomeStopLat: homeLat,
    errandHomeStopLng: homeLng,
    errandPasso: passo,
    errandHasPurchase: hasPurchase,
    isPurchaseFinalized: finalizado,
    finalTotal: finalTotal,
    cashTotalDue: cashTotalDue,
    pickupAddress: 'Rua do Ferrinho, Guarda',
    pickupLocation: _ferrinho,
    dropoffAddress: 'Rua Pedro Álvares Cabral 31, Guarda, Portugal',
    destination: _casa,
  );
}

void main() {
  group('FavorRota — os passos', () {
    test('paragem em casa SEM morada gravada: o passo 1 existe e usa a morada de entrega', () {
      final r = FavorRota.de(favor())!;
      expect(r.passos.map((p) => p.tipo), [
        FavorPassoTipo.casa,
        FavorPassoTipo.favor,
        FavorPassoTipo.entrega,
      ]);
      expect(r.passos[0].nome, 'Casa da cliente — Cristina');
      expect(r.passos[0].morada, 'Rua Pedro Álvares Cabral 31, Guarda, Portugal');
      expect(r.passos[0].coords, _casa);
      expect(r.atual.tipo, FavorPassoTipo.casa);
      expect(r.resumo, 'Casa da cliente → Farmácia Tavares → Casa da cliente');
    });

    test('o pickup_address herdado nunca aparece num favor', () {
      final r = FavorRota.de(favor())!;
      for (final p in r.passos) {
        expect(p.morada.contains('Ferrinho'), isFalse);
        expect(p.coords, isNot(_ferrinho));
      }
    });

    test('sem paragem em casa: começa no favor e tem 2 passos', () {
      final r = FavorRota.de(favor(homeStop: false))!;
      expect(r.passos.length, 2);
      expect(r.atual.nome, 'Farmácia Tavares');
      expect(r.atual.numero, 1);
      expect(r.resumo, 'Farmácia Tavares → Entrega à cliente');
    });

    test('o passo gravado no servidor manda (errand_passo)', () {
      expect(FavorRota.de(favor(passo: 1))!.atual.tipo, FavorPassoTipo.favor);
      expect(FavorRota.de(favor(passo: 2))!.atual.tipo, FavorPassoTipo.entrega);
      // passo 0 sem paragem em casa → o primeiro que existe (o favor)
      expect(FavorRota.de(favor(homeStop: false, passo: 0))!.atual.tipo,
          FavorPassoTipo.favor);
    });

    test('pedido antigo (sem errand_passo): deduz pelo estado como o gatilho', () {
      expect(passoAtual(favor(status: OrderStatus.driverAccepted)), 0);
      expect(passoAtual(favor(status: OrderStatus.pickedUp)), 1);
      expect(passoAtual(favor(status: OrderStatus.pickedUp, finalizado: true)), 2);
      expect(passoAtual(favor(status: OrderStatus.onTheWay)), 2);
      expect(passoAtual(favor(homeStop: false)), 1);
    });

    test('morada da paragem gravada ganha à de entrega', () {
      final r = FavorRota.de(favor(
          homeAddress: 'Rua das Flores 2, Guarda', homeLat: 40.53, homeLng: -7.27))!;
      expect(r.passos[0].morada, 'Rua das Flores 2, Guarda');
      expect(r.passos[0].coords, const LatLng(40.53, -7.27));
      // casa ≠ entrega → o fim chama-se "Entrega à cliente"
      expect(r.resumo, 'Casa da cliente → Farmácia Tavares → Entrega à cliente');
    });

    test('farmácia detectada pela descrição ou pelo local', () {
      expect(favorEhFarmacia(favor()), isTrue);
      expect(favorEhFarmacia(favor(descricao: 'Levanta a encomenda nos CTT')),
          isTrue); // o local é a Farmácia Tavares
      expect(textoPareceFarmacia('comprar remédio para a tosse'), isTrue);
      expect(textoPareceFarmacia('Levanta a encomenda nos CTT'), isFalse);
    });

    test('motivo da paragem em PT-PT', () {
      expect(motivoParagemEmCasa('receita'), 'Buscar a receita médica');
      expect(motivoParagemEmCasa(null), startsWith('Outro motivo'));
    });
  });

  group('Cobrar ao cliente — um só valor', () {
    test('depois do talão manda o final_total (taxa 8 + talão 1,88 = 9,88)', () {
      final o = favor(finalizado: true, finalTotal: 9.88, cashTotalDue: 12.00);
      expect(o.totalToCollectCash, closeTo(9.88, 0.001));
    });

    test('antes do talão: o price (estimado)', () {
      expect(favor().totalToCollectCash, closeTo(12.00, 0.001));
    });
  });

  group('Mapa — paragens do favor', () {
    test('as paragens são os passos que faltam, a começar pelo atual', () {
      final r = RouteOptimizer.optimize([favor()], _ferrinho);
      expect(r.stops.length, 3);
      expect(r.stops.first.location, _casa);
      expect(r.stops.first.passoFavor, 1);
      expect(r.stops[1].location, _farmacia);
      expect(r.stops.last.isPickup, isFalse);
      // nunca o pickup herdado
      expect(r.stops.any((s) => s.location == _ferrinho), isFalse);
    });

    test('no passo da entrega só fica a entrega', () {
      final r = RouteOptimizer.optimize(
          [favor(status: OrderStatus.onTheWay, passo: 2)], _farmacia);
      expect(r.stops.length, 1);
      expect(r.stops.single.location, _casa);
      expect(r.stops.single.passoFavor, 3);
    });
  });

  group('Folha do favor — arranque no passo gravado', () {
    test('passo 0 = o pedido tal e qual (fase recolha)', () {
      final o = favor(passo: 0);
      expect(identical(FolhaFavor.paraArranque(o), o), isTrue);
    });

    test('passo 1 com paragem: cópia sem paragem (a folha abre no talão)', () {
      final c = FolhaFavor.paraArranque(favor(passo: 1));
      expect(c.errandHomeStop, isFalse);
      expect(c.errandHasPurchase, isTrue);
      expect(c.id, '74dd4ecc-6d33-4b93-b404-1c70dc8cf0f9');
    });

    test('passo 2: cópia sem paragem nem compra (a folha abre na entrega)', () {
      final c = FolhaFavor.paraArranque(
          favor(status: OrderStatus.onTheWay, passo: 2, finalizado: true, finalTotal: 9.88));
      expect(c.errandHomeStop, isFalse);
      expect(c.errandHasPurchase, isFalse);
    });
  });
}
