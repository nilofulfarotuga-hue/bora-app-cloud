import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/modo_ocupado_service.dart';
import 'package:bora_app/services/order_eta_service.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// C6 (29/10/2026) — a lógica do modo ocupado do parceiro, sem ecrãs e sem rede:
/// o estado (+N min até HH:MM), a conta que o cliente faz (interruptor desligado =
/// 0), a hora de "fica pronto às…" e a soma no tempo estimado.
void main() {
  // 29/10/2026 está em hora de inverno em Lisboa (UTC+0): 14:30 UTC = 14:30 Lisboa.
  final agora = DateTime.utc(2026, 10, 29, 14, 30);

  group('EstadoOcupado', () {
    test('ativo só com minutos > 0 e fim no futuro', () {
      final fim = DateTime.utc(2026, 10, 29, 16, 30);
      expect(EstadoOcupado(extraMinutos: 20, ate: fim).ativoEm(agora), isTrue);
      expect(EstadoOcupado.nenhum.ativoEm(agora), isFalse);
      expect(const EstadoOcupado(extraMinutos: 20).ativoEm(agora), isFalse,
          reason: 'sem hora de fim não conta');
      expect(EstadoOcupado(extraMinutos: 0, ate: fim).ativoEm(agora), isFalse);
    });

    test('expira sozinho: no instante exato do fim já não conta', () {
      final fim = DateTime.utc(2026, 10, 29, 16, 30);
      final e = EstadoOcupado(extraMinutos: 30, ate: fim);
      expect(e.extraEm(fim.subtract(const Duration(seconds: 1))), 30);
      expect(e.extraEm(fim), 0);
      expect(e.extraEm(fim.add(const Duration(minutes: 5))), 0);
    });

    test('o texto do cartão: "Ocupado: +20 min até 16:30"', () {
      final e = EstadoOcupado(
          extraMinutos: 20, ate: DateTime.utc(2026, 10, 29, 16, 30));
      expect(e.textoEm(agora), 'Ocupado: +20 min até 16:30');
      expect(EstadoOcupado.nenhum.textoEm(agora), '');
    });

    test('lê a resposta de partner_set_busy e uma linha de restaurants', () {
      final r = EstadoOcupado.doMapa({
        'ok': true,
        'extra_minutes': 30,
        'busy_until': '2026-10-29T16:30:00+00:00',
      });
      expect(r, EstadoOcupado(extraMinutos: 30, ate: DateTime.utc(2026, 10, 29, 16, 30)));
      final linha = EstadoOcupado.doMapa({'busy_extra_minutes': 10, 'busy_until': null});
      expect(linha.extraMinutos, 10);
      expect(linha.ate, isNull);
      expect(EstadoOcupado.doMapa({}), EstadoOcupado.nenhum);
    });

    test('os botões são 10, 20 e 30 e dura 2 horas', () {
      expect(kMinutosOcupado, [10, 20, 30]);
      expect(kDuracaoModoOcupado, const Duration(hours: 2));
    });
  });

  group('minutosExtraParaCliente — interruptor desligado = nada muda', () {
    final fim = DateTime.utc(2026, 10, 29, 16, 30);

    test('desligado → 0 mesmo com a loja ocupada', () {
      expect(
          minutosExtraParaCliente(
              interruptorLigado: false,
              busyExtraMinutes: 30,
              busyUntil: fim,
              agora: agora),
          0);
    });

    test('ligado → os minutos da loja', () {
      expect(
          minutosExtraParaCliente(
              interruptorLigado: true,
              busyExtraMinutes: 30,
              busyUntil: fim,
              agora: agora),
          30);
    });

    test('ligado mas expirado, sem fim ou sem minutos → 0', () {
      expect(
          minutosExtraParaCliente(
              interruptorLigado: true,
              busyExtraMinutes: 30,
              busyUntil: agora.subtract(const Duration(minutes: 1)),
              agora: agora),
          0);
      expect(
          minutosExtraParaCliente(
              interruptorLigado: true,
              busyExtraMinutes: 30,
              busyUntil: null,
              agora: agora),
          0);
      expect(
          minutosExtraParaCliente(
              interruptorLigado: true,
              busyExtraMinutes: 0,
              busyUntil: fim,
              agora: agora),
          0);
    });
  });

  group('RestaurantModel — campos do modo ocupado', () {
    RestaurantModel loja({int extra = 0, DateTime? ate}) => RestaurantModel(
          id: 'r1',
          name: 'Loja',
          phone: '',
          address: '',
          email: '',
          photoUrl: '',
          cuisineType: '',
          isPartner: true,
          category: BusinessCategory.restaurant,
          busyExtraMinutes: extra,
          busyUntil: ate,
        );

    test('por defeito não há modo ocupado (loja como sempre foi)', () {
      expect(loja().extraOcupadoEm(agora), 0);
    });

    test('extraOcupadoEm respeita a hora de fim', () {
      final fim = DateTime.utc(2026, 10, 29, 16, 30);
      expect(loja(extra: 20, ate: fim).extraOcupadoEm(agora), 20);
      expect(loja(extra: 20, ate: fim).extraOcupadoEm(fim), 0);
      expect(loja(extra: 20).extraOcupadoEm(agora), 0);
    });

    test('copyWith não perde o modo ocupado', () {
      final fim = DateTime.utc(2026, 10, 29, 16, 30);
      final c = loja(extra: 20, ate: fim).copyWith(isOnline: false);
      expect(c.busyExtraMinutes, 20);
      expect(c.busyUntil, fim);
    });

    test('parseBusyUntil é tolerante', () {
      expect(RestaurantModel.parseBusyUntil(null), isNull);
      expect(RestaurantModel.parseBusyUntil('lixo'), isNull);
      expect(RestaurantModel.parseBusyUntil('2026-10-29T16:30:00+00:00'),
          DateTime.utc(2026, 10, 29, 16, 30));
    });
  });

  group('instanteDoFicaPronto — a hora que a loja escolhe (relógio de Lisboa)', () {
    test('hoje, daqui a 40 minutos', () {
      final i = instanteDoFicaPronto(hora: 15, minuto: 10, agora: agora)!;
      expect(i, DateTime.utc(2026, 10, 29, 15, 10));
    });

    test('quase agora (menos de 1 minuto atrás) ainda é hoje', () {
      final i = instanteDoFicaPronto(hora: 14, minuto: 30, agora: agora)!;
      expect(i, DateTime.utc(2026, 10, 29, 14, 30));
    });

    test('hora que já passou vai para amanhã e, por ser longe, é recusada', () {
      expect(instanteDoFicaPronto(hora: 13, minuto: 0, agora: agora), isNull);
    });

    test('depois da meia-noite: 00:15 às 23:50 é daqui a 25 minutos', () {
      final tarde = DateTime.utc(2026, 10, 29, 23, 50);
      final i = instanteDoFicaPronto(hora: 0, minuto: 15, agora: tarde)!;
      expect(i, DateTime.utc(2026, 10, 30, 0, 15));
    });

    test('mais de 4 horas à frente é recusada (o servidor também recusa)', () {
      expect(instanteDoFicaPronto(hora: 19, minuto: 0, agora: agora), isNull);
      expect(instanteDoFicaPronto(hora: 18, minuto: 25, agora: agora), isNotNull);
    });

    test('verão: o relógio de Lisboa está uma hora à frente do UTC', () {
      final verao = DateTime.utc(2026, 7, 10, 11, 0); // 12:00 em Lisboa
      final i = instanteDoFicaPronto(hora: 12, minuto: 40, agora: verao)!;
      expect(i, DateTime.utc(2026, 7, 10, 11, 40));
      expect(hhmmLisboa(i), '12:40');
    });

    test('hhmmLisboa mostra sempre a hora de Lisboa', () {
      expect(hhmmLisboa(DateTime.utc(2026, 10, 29, 16, 30)), '16:30');
      expect(horaLisboa(DateTime.utc(2026, 10, 29, 16, 30)).hour, 16);
    });
  });

  group('tempo estimado — soma do modo ocupado', () {
    const loja = LatLng(40.5000, -7.2600);
    const cliente = LatLng(40.5300, -7.2600); // ~3,3 km

    setUp(() {
      OrderEtaService.avgSpeedKmh = 30;
    });

    test('sem modo ocupado a janela é a de sempre (e extraMinutes 0 = igual)', () {
      final a = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja)!;
      final b = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja, extraMinutes: 0)!;
      expect(b, a);
    });

    test('+20 min desloca a janela inteira 20 minutos', () {
      final a = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja)!;
      final b = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja, extraMinutes: 20)!;
      expect(b.$1, a.$1 + 20);
      expect(b.$2, a.$2 + 20);
    });

    test('extra negativo conta como 0', () {
      final a = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja)!;
      final b = OrderEtaService.deliveryWindowMinutes(
          clientLocation: cliente, restaurantLocation: loja, extraMinutes: -15)!;
      expect(b, a);
    });

    test('sem coordenadas continua a não haver janela', () {
      expect(
          OrderEtaService.deliveryWindowMinutes(
              clientLocation: null, restaurantLocation: loja, extraMinutes: 30),
          isNull);
    });

    OrderModel pedido({DateTime? pronto, int? prep}) => OrderModel(
          total: 20,
          serviceType: OrderServiceType.restaurant,
          status: OrderStatus.preparing,
          pickupLocation: loja,
          destination: cliente,
          prepTimeMinutes: prep,
          readyAtPromised: pronto,
        );

    test('pedido sem promessa: preparação de sempre', () {
      // ~3,3 km a 30 km/h = 6,7 min + 8 de preparação = 14,7 → 15.
      expect(OrderEtaService.minutesRemaining(pedido(), now: agora), 15);
    });

    test('"fica pronto às" daqui a 30 min: espera + viagem', () {
      // 30 + 6,7 = 36,7 → 40.
      final p = pedido(pronto: agora.add(const Duration(minutes: 30)));
      expect(OrderEtaService.minutesRemaining(p, now: agora), 40);
    });

    test('o tempo vai descendo à medida que a hora prometida se aproxima', () {
      final pronto = agora.add(const Duration(minutes: 30));
      final p = pedido(pronto: pronto);
      final meioCaminho = OrderEtaService.minutesRemaining(
          p, now: agora.add(const Duration(minutes: 20)))!;
      // faltam 10 + 6,7 = 16,7 → 20.
      expect(meioCaminho, 20);
    });

    test('hora prometida já passou: só falta a viagem (mínimo 5)', () {
      final p = pedido(pronto: agora.subtract(const Duration(minutes: 10)));
      expect(OrderEtaService.minutesRemaining(p, now: agora), 10);
    });

    test('a promessa manda sobre o tempo de preparação anunciado', () {
      final p = pedido(prep: 45, pronto: agora.add(const Duration(minutes: 5)));
      // 5 + 6,7 = 11,7 → 15 (e não 45 + 6,7).
      expect(OrderEtaService.minutesRemaining(p, now: agora), 15);
    });
  });

  group('OrderModel.fromSupabase lê ready_at_promised', () {
    Map<String, dynamic> linha([Map<String, dynamic> extra = const {}]) => {
          'id': '00000000-0000-0000-0000-000000000001',
          'status': 'preparing',
          'service_type': 'restaurant',
          'payment_method': 'cash',
          'price': 12.5,
          'items': const [],
          ...extra,
        };

    test('sem a coluna (migração por aplicar) fica null e nada se parte', () {
      expect(OrderModel.fromSupabase(linha()).readyAtPromised, isNull);
    });

    test('com a hora prometida, lê o instante', () {
      final o = OrderModel.fromSupabase(
          linha({'ready_at_promised': '2026-10-29T15:40:00+00:00'}));
      expect(o.readyAtPromised!.toUtc(), DateTime.utc(2026, 10, 29, 15, 40));
    });
  });
}
