import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/services/modo_ocupado_service.dart';
import 'package:bora_app/services/order_eta_service.dart';
import 'package:bora_app/utils/fica_pronto.dart';
import 'package:bora_app/widgets/partner/cartao_modo_ocupado.dart';
import 'package:bora_app/widgets/partner/quando_chamar_estafeta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// "Quando chamamos o estafeta?" (17/11/2026, missão
/// a3-parte2-quando-chamar-17-11). Relógio fixo; servidor falso.
///
/// 17/11/2026 é uma terça; em novembro Lisboa = UTC (por isso as horas UTC
/// dos testes são as horas que a loja vê).

/// Horário real da A3 Guarda (restaurants.business_hours, lido a 17/11).
final _horarioA3 = BusinessHours.fromJson({
  for (final d in ['mon', 'tue', 'wed', 'thu', 'fri'])
    d: {
      'open': '08:30',
      'close': '18:30',
      'break_start': '13:00',
      'break_end': '15:00',
    },
  'sat': {'open': '09:00', 'close': '13:00'},
  'sun': {'open': '09:00', 'close': '13:00', 'closed': true},
});

RestaurantModel _loja({
  BusinessCategory categoria = BusinessCategory.store,
  Set<BusinessCategory> extra = const {BusinessCategory.festas},
  BusinessHours? horario,
}) =>
    RestaurantModel(
      id: 'a3-guarda',
      name: 'A3 Guarda',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: categoria,
      extraCategories: extra,
      businessHours: horario ?? _horarioA3,
    );

class _ApiFalsa implements ModoOcupadoApi {
  final List<String> chamadas = [];

  @override
  String get ultimoErro => '';
  @override
  Future<EstadoOcupado?> definir(String restaurantId, int minutos) async => null;
  @override
  Future<bool> prometerPronto(String orderId, DateTime? hora) async {
    chamadas.add('pronto:$orderId:${hora?.toUtc().toIso8601String()}');
    return true;
  }

  @override
  Future<PainelOcupados?> listarOcupados() async => null;
  @override
  Future<bool> desligarLoja(String restaurantId) async => true;
  @override
  Future<bool> definirInterruptor(bool ligado) async => true;
}

void main() {
  // terça 17/11/2026 10:00 em Lisboa
  final agora = DateTime.utc(2026, 11, 17, 10, 0);

  group('que lojas escolhem dias (categoria principal)', () {
    test('A3 (loja + festas extra) sim; farmácia, supermercado, festas e beleza sim',
        () {
      expect(_loja().lojaNaoComida, isTrue);
      for (final c in [
        BusinessCategory.pharmacy,
        BusinessCategory.supermarket,
        BusinessCategory.festas,
        BusinessCategory.beauty,
      ]) {
        expect(_loja(categoria: c, extra: const {}).lojaNaoComida, isTrue,
            reason: c.name);
      }
    });

    test('restaurante (mesmo com supermercado extra) e sobremesas não', () {
      expect(
          _loja(
              categoria: BusinessCategory.restaurant,
              extra: const {BusinessCategory.supermarket}).lojaNaoComida,
          isFalse);
      expect(_loja(categoria: BusinessCategory.sobremesa, extra: const {})
              .lojaNaoComida,
          isFalse);
    });
  });

  group('texto do dia e da hora (Lisboa)', () {
    test('hoje, amanhã e dia da semana', () {
      expect(textoDiaHoraLisboa(DateTime.utc(2026, 11, 17, 18, 30), agora),
          'hoje às 18:30');
      expect(textoDiaHoraLisboa(DateTime.utc(2026, 11, 18, 9, 0), agora),
          'amanhã às 09:00');
      expect(textoDiaHoraLisboa(DateTime.utc(2026, 11, 20, 15, 0), agora),
          'sexta, 20/11, às 15:00');
      expect(textoFicaPronto(DateTime.utc(2026, 11, 20, 15, 0), agora),
          'Fica pronto sexta, 20/11, às 15:00');
    });

    test('no verão Lisboa = UTC+1', () {
      final verao = DateTime.utc(2026, 7, 10, 10, 0);
      expect(textoDiaHoraLisboa(DateTime.utc(2026, 7, 10, 14, 0), verao),
          'hoje às 15:00');
    });
  });

  group('opções rápidas (A3, terça 10:00)', () {
    EscolhaChamada opcao(String rotulo, DateTime quando) {
      final d = kOpcoesChamada.firstWhere((o) => o.$1 == rotulo).$2;
      return escolhaDaOpcao(d, agora: quando, loja: _loja());
    }

    test('as 9 opções do Danilo, pela ordem', () {
      expect(kOpcoesChamada.map((o) => o.$1).toList(), [
        '10 min',
        '15 min',
        '20 min',
        '30 min',
        '1 h',
        '2 h',
        '3 h',
        'Amanhã (1 dia)',
        '2 dias',
      ]);
    });

    test('minutos curtos e 1-2 h dentro do horário ficam em minutos (como hoje)',
        () {
      expect(opcao('10 min', agora), const EscolhaChamada.minutos(10));
      expect(opcao('30 min', agora), const EscolhaChamada.minutos(30));
      expect(opcao('1 h', agora), const EscolhaChamada.minutos(60));
      expect(opcao('2 h', agora), const EscolhaChamada.minutos(120));
    });

    test('3 h cai na pausa 13:00-15:00: fica pronto às 15:00', () {
      expect(opcao('3 h', agora),
          EscolhaChamada.instante(DateTime.utc(2026, 11, 17, 15, 0)));
    });

    test('amanhã e 2 dias: o dia e a hora', () {
      expect(opcao('Amanhã (1 dia)', agora),
          EscolhaChamada.instante(DateTime.utc(2026, 11, 18, 10, 0)));
      expect(opcao('2 dias', agora),
          EscolhaChamada.instante(DateTime.utc(2026, 11, 19, 10, 0)));
    });

    test('sexta 16:00: amanhã (sábado fecha às 13:00) e 2 dias (domingo fechado) '
        'passam para segunda às 08:30', () {
      final sexta = DateTime.utc(2026, 11, 20, 16, 0);
      final segunda = EscolhaChamada.instante(DateTime.utc(2026, 11, 23, 8, 30));
      expect(opcao('Amanhã (1 dia)', sexta), segunda);
      expect(opcao('2 dias', sexta), segunda);
    });

    test('1 h depois de fechar: a primeira hora em que abre (sábado 09:00)', () {
      final sextaTarde = DateTime.utc(2026, 11, 20, 18, 0);
      expect(opcao('1 h', sextaTarde),
          EscolhaChamada.instante(DateTime.utc(2026, 11, 21, 9, 0)));
    });

    test('dentro do horário devolve o próprio instante', () {
      final t = DateTime.utc(2026, 11, 17, 11, 0);
      expect(identical(primeiroInstanteAberto(_loja(), t), t), isTrue);
    });
  });

  group('escolher dia e hora', () {
    test('sexta 20/11 às 15:00: aceite', () {
      final r = validarDiaHora(
          loja: _loja(), dia: DateTime(2026, 11, 20), hora: 15, minuto: 0, agora: agora);
      expect(r.erro, isNull);
      expect(r.instante, DateTime.utc(2026, 11, 20, 15, 0));
    });

    test('na pausa, ao domingo ou daqui a 5 min: recusado com a razão', () {
      final pausa = validarDiaHora(
          loja: _loja(), dia: DateTime(2026, 11, 20), hora: 14, minuto: 0, agora: agora);
      expect(pausa.instante, isNull);
      expect(pausa.erro, contains('fechada'));
      expect(pausa.erro, contains('08:30'));

      final domingo = validarDiaHora(
          loja: _loja(), dia: DateTime(2026, 11, 22), hora: 10, minuto: 0, agora: agora);
      expect(domingo.instante, isNull);

      final cedo = validarDiaHora(
          loja: _loja(), dia: DateTime(2026, 11, 17), hora: 10, minuto: 5, agora: agora);
      expect(cedo.erro, contains('10 minutos'));
    });

    test('a hora escolhida é a de Lisboa, também no verão', () {
      final verao = DateTime.utc(2026, 7, 6, 9, 0);
      final r = validarDiaHora(
          loja: _loja(horario: const BusinessHours()),
          dia: DateTime(2026, 7, 10),
          hora: 15,
          minuto: 0,
          agora: verao);
      expect(r.instante, DateTime.utc(2026, 7, 10, 14, 0));
    });

    test('dias do calendário: domingo não abre, sábado abre', () {
      expect(diaAbre(_loja(), DateTime(2026, 11, 22)), isFalse);
      expect(diaAbre(_loja(), DateTime(2026, 11, 21)), isTrue);
    });
  });

  group('cliente: "Fica pronto sexta, 20/11, às 15:00"', () {
    const loja = LatLng(40.5373, -7.2675);
    const casa = LatLng(40.5450, -7.2500);
    OrderModel pedido(DateTime? pronto, {OrderStatus status = OrderStatus.preparing}) =>
        OrderModel(
          total: 20,
          serviceType: OrderServiceType.restaurant,
          status: status,
          pickupLocation: loja,
          destination: casa,
          readyAtPromised: pronto,
        );

    test('prometido para daqui a dias: dia e hora, sem "Chega em ~X min"', () {
      final p = pedido(DateTime.utc(2026, 11, 20, 15, 0));
      expect(OrderEtaService.minutesRemaining(p, now: agora), isNull);
      expect(OrderEtaService.textoProntoLonge(p, now: agora),
          'Fica pronto sexta, 20/11, às 15:00');
    });

    test('prometido para daqui a 30 min: o "Chega em" de sempre', () {
      final p = pedido(agora.add(const Duration(minutes: 30)));
      expect(OrderEtaService.textoProntoLonge(p, now: agora), isNull);
      expect(OrderEtaService.minutesRemaining(p, now: agora), isNotNull);
    });

    test('pedido já entregue ou sem promessa: nada', () {
      expect(
          OrderEtaService.textoProntoLonge(
              pedido(DateTime.utc(2026, 11, 21, 15), status: OrderStatus.delivered),
              now: agora),
          isNull);
      expect(OrderEtaService.textoProntoLonge(pedido(null), now: agora), isNull);
    });
  });

  group('folha "Quando chamamos o estafeta?" (ecrã)', () {
    Future<Future<EscolhaChamada?> Function()> abrir(
      WidgetTester t, {
      EscolherDiaChamada? dia,
      EscolherHoraChamada? hora,
    }) async {
      EscolhaChamada? resultado;
      var fechou = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  resultado = await escolherQuandoChamarEstafeta(
                    ctx,
                    loja: _loja(),
                    agora: () => agora,
                    escolherDia: dia,
                    escolherHora: hora,
                  );
                  fechou = true;
                },
                child: const Text('aceitar'),
              ),
            ),
          ),
        ),
      ));
      return () async => fechou ? resultado : null;
    }

    testWidgets('mostra as 9 opções e "Escolher dia e hora"; "2 dias" devolve quinta 10:00',
        (t) async {
      final ler = await abrir(t);
      await t.pump();
      await t.tap(find.text('aceitar'));
      await t.pumpAndSettle();

      expect(find.text('Quando chamamos o estafeta?'), findsOneWidget);
      for (final o in kOpcoesChamada) {
        expect(find.text(o.$1), findsOneWidget, reason: o.$1);
      }
      expect(find.byKey(const Key('btn_escolher_dia_hora')), findsOneWidget);
      // as opções longas mostram já o dia e a hora
      expect(find.text('quinta, 19/11, às 10:00'), findsOneWidget);

      await t.tap(find.text('2 dias'));
      await t.pumpAndSettle();
      expect(await ler(), EscolhaChamada.instante(DateTime.utc(2026, 11, 19, 10, 0)));
    });

    testWidgets('"10 min" devolve minutos', (t) async {
      final ler = await abrir(t);
      await t.pump();
      await t.tap(find.text('aceitar'));
      await t.pumpAndSettle();
      await t.tap(find.text('10 min'));
      await t.pumpAndSettle();
      expect(await ler(), const EscolhaChamada.minutos(10));
    });

    testWidgets('"Escolher dia e hora": sexta às 15:00', (t) async {
      final ler = await abrir(
        t,
        dia: (c, {required inicial, required primeiro, required ultimo, required podeEscolher}) async {
          expect(podeEscolher(DateTime(2026, 11, 22)), isFalse, reason: 'domingo fechado');
          expect(ultimo, DateTime(2026, 12, 1), reason: '14 dias');
          return DateTime(2026, 11, 20);
        },
        hora: (c, inicial) async => const TimeOfDay(hour: 15, minute: 0),
      );
      await t.pump();
      await t.tap(find.text('aceitar'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('btn_escolher_dia_hora')));
      await t.tap(find.byKey(const Key('btn_escolher_dia_hora')));
      await t.pumpAndSettle();
      expect(await ler(), EscolhaChamada.instante(DateTime.utc(2026, 11, 20, 15, 0)));
    });

    testWidgets('"Escolher dia e hora" na pausa: diz porquê e não fecha', (t) async {
      final ler = await abrir(
        t,
        dia: (c, {required inicial, required primeiro, required ultimo, required podeEscolher}) async =>
            DateTime(2026, 11, 20),
        hora: (c, inicial) async => const TimeOfDay(hour: 14, minute: 0),
      );
      await t.pump();
      await t.tap(find.text('aceitar'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('btn_escolher_dia_hora')));
      await t.tap(find.byKey(const Key('btn_escolher_dia_hora')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('erro_escolher_dia_hora')), findsOneWidget);
      expect(find.textContaining('fechada a essa hora'), findsOneWidget);
      expect(find.text('Quando chamamos o estafeta?'), findsOneWidget);
      expect(await ler(), isNull);
    });
  });

  group('"Mudar quando fica pronto" (pedido já aceite)', () {
    tearDown(() => InterruptoresApp.instance.esquecer());

    testWidgets('loja que não é de comida: sempre visível, sem "Tirar", grava a hora nova',
        (t) async {
      // modo ocupado DESLIGADO: o botão longo aparece na mesma
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.modoOcupadoParceiro: false});
      final api = _ApiFalsa();
      final sexta = DateTime.utc(2026, 11, 20, 15, 0);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BotaoFicaProntoAs(
            orderId: 'p1',
            atual: DateTime.utc(2026, 11, 19, 10, 0),
            loja: _loja(),
            api: api,
            agora: () => agora,
            escolherChamada: (c, l, titulo) async {
              expect(titulo, 'Mudar quando fica pronto');
              return EscolhaChamada.instante(sexta);
            },
          ),
        ),
      ));
      await t.pump();
      expect(find.byKey(const Key('btn_mudar_quando_pronto')), findsOneWidget);
      expect(find.byKey(const Key('btn_tirar_hora')), findsNothing);
      expect(find.text('Fica pronto quinta, 19/11, às 10:00 · mudar'), findsOneWidget);

      await t.tap(find.byKey(const Key('btn_mudar_quando_pronto')));
      await t.pumpAndSettle();
      expect(api.chamadas, ['pronto:p1:2026-11-20T15:00:00.000Z']);
      expect(find.text('Fica pronto sexta, 20/11, às 15:00 · mudar'), findsOneWidget);
    });

    testWidgets('restaurante com o modo ocupado desligado: continua sem botão (como hoje)',
        (t) async {
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.modoOcupadoParceiro: false});
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BotaoFicaProntoAs(
            orderId: 'p2',
            loja: _loja(categoria: BusinessCategory.restaurant, extra: const {}),
            api: _ApiFalsa(),
            agora: () => agora,
          ),
        ),
      ));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('btn_mudar_quando_pronto')), findsNothing);
      expect(find.byKey(const Key('btn_fica_pronto_as')), findsNothing);
    });
  });
}
