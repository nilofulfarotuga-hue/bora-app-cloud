import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/services/modo_ocupado_service.dart';
import 'package:bora_app/widgets/modo_ocupado_ligado.dart';
import 'package:bora_app/widgets/partner/cartao_modo_ocupado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C6 (29/10/2026) — o cartão "Modo ocupado" do painel do parceiro, o botão
/// "Fica pronto às…" e o aviso do cliente. Servidor falso; relógio fixo.
class _ApiFalsa implements ModoOcupadoApi {
  final List<String> chamadas = [];
  String erro = '';
  bool prometerOk = true;
  DateTime fim = DateTime.utc(2026, 10, 29, 16, 30);

  @override
  String get ultimoErro => erro;

  @override
  Future<EstadoOcupado?> definir(String restaurantId, int minutos) async {
    chamadas.add('definir:$restaurantId:$minutos');
    if (erro.isNotEmpty) return null;
    return minutos == 0
        ? EstadoOcupado.nenhum
        : EstadoOcupado(extraMinutos: minutos, ate: fim);
  }

  @override
  Future<bool> prometerPronto(String orderId, DateTime? hora) async {
    chamadas.add('pronto:$orderId:${hora?.toUtc().toIso8601String()}');
    return prometerOk;
  }

  @override
  Future<PainelOcupados?> listarOcupados() async => null;
  @override
  Future<bool> desligarLoja(String restaurantId) async => true;
  @override
  Future<bool> definirInterruptor(bool ligado) async => true;
}

void main() {
  final agora = DateTime.utc(2026, 10, 29, 14, 30);

  Future<void> montar(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ));
    await t.pump(); // deixa o interruptor responder
    await t.pump();
  }

  void interruptor(bool ligado) => InterruptoresApp.instance
      .definirParaTeste({InterruptoresApp.modoOcupadoParceiro: ligado});

  tearDown(() => InterruptoresApp.instance.esquecer());

  group('cartão Modo ocupado', () {
    testWidgets('interruptor DESLIGADO: não desenha nada (de fábrica)',
        (t) async {
      interruptor(false);
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: _ApiFalsa(), agora: () => agora));
      expect(find.byKey(const Key('cartao_modo_ocupado')), findsNothing);
      expect(find.text('Modo ocupado'), findsNothing);
      expect(find.byKey(const Key('btn_ocupado_20')), findsNothing);
    });

    testWidgets('sem resposta do servidor também fica desligado', (t) async {
      // Sem definirParaTeste: a leitura falha (sem Supabase) e vale o valor de recurso.
      InterruptoresApp.instance.esquecer();
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: _ApiFalsa(), agora: () => agora));
      expect(find.byKey(const Key('cartao_modo_ocupado')), findsNothing);
    });

    testWidgets('LIGADO: mostra +10 / +20 / +30 min e ainda não há "Desligar"',
        (t) async {
      interruptor(true);
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: _ApiFalsa(), agora: () => agora));
      expect(find.text('Modo ocupado'), findsOneWidget);
      expect(find.text('+10 min'), findsOneWidget);
      expect(find.text('+20 min'), findsOneWidget);
      expect(find.text('+30 min'), findsOneWidget);
      expect(find.byKey(const Key('btn_ocupado_desligar')), findsNothing);
    });

    testWidgets('carregar em +20 liga e mostra "Ocupado: +20 min até 16:30"',
        (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: api, agora: () => agora));

      await t.tap(find.byKey(const Key('btn_ocupado_20')));
      await t.pump();
      await t.pump();

      expect(api.chamadas, ['definir:r1:20']);
      expect(find.text('Ocupado: +20 min até 16:30'), findsOneWidget);
      expect(find.byKey(const Key('btn_ocupado_desligar')), findsOneWidget);
      expect(find.textContaining('Modo ocupado: +20 min até às 16:30'), findsOneWidget);
    });

    testWidgets('trocar de botão TROCA o valor (não soma)', (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: api, agora: () => agora));

      await t.tap(find.byKey(const Key('btn_ocupado_20')));
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const Key('btn_ocupado_30')));
      await t.pump();
      await t.pump();

      expect(api.chamadas, ['definir:r1:20', 'definir:r1:30']);
      expect(find.text('Ocupado: +30 min até 16:30'), findsOneWidget);
      expect(find.textContaining('+50'), findsNothing);
    });

    testWidgets('"Desligar" volta ao normal', (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(
          t,
          CartaoModoOcupado(
            restaurantId: 'r1',
            inicial: EstadoOcupado(extraMinutos: 10, ate: api.fim),
            api: api,
            agora: () => agora,
          ));
      expect(find.text('Ocupado: +10 min até 16:30'), findsOneWidget);

      await t.tap(find.byKey(const Key('btn_ocupado_desligar')));
      await t.pump();
      await t.pump();

      expect(api.chamadas, ['definir:r1:0']);
      expect(find.byKey(const Key('btn_ocupado_desligar')), findsNothing);
      expect(find.textContaining('Ocupado: +'), findsNothing);
      expect(find.textContaining('Modo ocupado desligado'), findsOneWidget);
    });

    testWidgets('já abre ocupado quando a loja estava ocupada', (t) async {
      interruptor(true);
      await montar(
          t,
          CartaoModoOcupado(
            restaurantId: 'r1',
            inicial: EstadoOcupado(extraMinutos: 30, ate: DateTime.utc(2026, 10, 29, 15, 45)),
            api: _ApiFalsa(),
            agora: () => agora,
          ));
      expect(find.text('Ocupado: +30 min até 15:45'), findsOneWidget);
    });

    testWidgets('expira sozinho: depois da hora de fim volta a "normal"',
        (t) async {
      interruptor(true);
      await montar(
          t,
          CartaoModoOcupado(
            restaurantId: 'r1',
            inicial: EstadoOcupado(extraMinutos: 30, ate: DateTime.utc(2026, 10, 29, 14, 0)),
            api: _ApiFalsa(),
            agora: () => agora,
          ));
      expect(find.textContaining('Ocupado: +'), findsNothing);
      expect(find.byKey(const Key('btn_ocupado_desligar')), findsNothing);
    });

    testWidgets('servidor recusa (interruptor geral desligado): avisa e não muda',
        (t) async {
      interruptor(true);
      final api = _ApiFalsa()..erro = 'desligado';
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: api, agora: () => agora));

      await t.tap(find.byKey(const Key('btn_ocupado_20')));
      await t.pump();
      await t.pump();

      expect(find.textContaining('não está ligado na plataforma'), findsOneWidget);
      expect(find.textContaining('Ocupado: +'), findsNothing);
    });

    testWidgets('falha de rede: mensagem simples e nada muda', (t) async {
      interruptor(true);
      final api = _ApiFalsa()..erro = 'falhou';
      await montar(t, CartaoModoOcupado(restaurantId: 'r1', api: api, agora: () => agora));

      await t.tap(find.byKey(const Key('btn_ocupado_10')));
      await t.pump();
      await t.pump();

      expect(find.textContaining('Não foi possível mudar o modo ocupado'), findsOneWidget);
      expect(find.byKey(const Key('btn_ocupado_desligar')), findsNothing);
    });
  });

  group('botão "Fica pronto às…"', () {
    Future<TimeOfDay?> Function(BuildContext, TimeOfDay) escolhe(TimeOfDay? t) =>
        (_, __) async => t;

    testWidgets('interruptor DESLIGADO: não desenha nada', (t) async {
      interruptor(false);
      await montar(t, BotaoFicaProntoAs(orderId: 'o1', api: _ApiFalsa(), agora: () => agora));
      expect(find.byKey(const Key('btn_fica_pronto_as')), findsNothing);
    });

    testWidgets('LIGADO: mostra o botão', (t) async {
      interruptor(true);
      await montar(t, BotaoFicaProntoAs(orderId: 'o1', api: _ApiFalsa(), agora: () => agora));
      expect(find.text('Fica pronto às…'), findsOneWidget);
      expect(find.byKey(const Key('btn_tirar_hora')), findsNothing);
    });

    testWidgets('escolher 15:10 grava a hora (relógio de Lisboa → instante)',
        (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(
          t,
          BotaoFicaProntoAs(
            orderId: 'o1',
            api: api,
            agora: () => agora,
            escolherHora: escolhe(const TimeOfDay(hour: 15, minute: 10)),
          ));

      await t.tap(find.byKey(const Key('btn_fica_pronto_as')));
      await t.pump();
      await t.pump();

      expect(api.chamadas, ['pronto:o1:2026-10-29T15:10:00.000Z']);
      expect(find.text('Pronto às 15:10 · mudar'), findsOneWidget);
      expect(find.byKey(const Key('btn_tirar_hora')), findsOneWidget);
      expect(find.textContaining('fica pronto às 15:10'), findsOneWidget);
    });

    testWidgets('a sugestão do relógio é daqui a 15 minutos', (t) async {
      interruptor(true);
      TimeOfDay? sugerida;
      await montar(
          t,
          BotaoFicaProntoAs(
            orderId: 'o1',
            api: _ApiFalsa(),
            agora: () => agora,
            escolherHora: (_, inicial) async {
              sugerida = inicial;
              return null;
            },
          ));
      await t.tap(find.byKey(const Key('btn_fica_pronto_as')));
      await t.pump();
      expect(sugerida, const TimeOfDay(hour: 14, minute: 45));
    });

    testWidgets('hora muito longe (mais de 4 horas) é recusada sem ir ao servidor',
        (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(
          t,
          BotaoFicaProntoAs(
            orderId: 'o1',
            api: api,
            agora: () => agora,
            escolherHora: escolhe(const TimeOfDay(hour: 20, minute: 0)),
          ));
      await t.tap(find.byKey(const Key('btn_fica_pronto_as')));
      await t.pump();
      await t.pump();
      expect(api.chamadas, isEmpty);
      expect(find.textContaining('menos de 4 horas'), findsOneWidget);
    });

    testWidgets('cancelar o relógio não faz nada', (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(
          t,
          BotaoFicaProntoAs(
              orderId: 'o1',
              api: api,
              agora: () => agora,
              escolherHora: escolhe(null)));
      await t.tap(find.byKey(const Key('btn_fica_pronto_as')));
      await t.pump();
      await t.pump();
      expect(api.chamadas, isEmpty);
    });

    testWidgets('abre com a hora já prometida e "Tirar" apaga-a', (t) async {
      interruptor(true);
      final api = _ApiFalsa();
      await montar(
          t,
          BotaoFicaProntoAs(
            orderId: 'o1',
            atual: DateTime.utc(2026, 10, 29, 15, 40),
            api: api,
            agora: () => agora,
          ));
      expect(find.text('Pronto às 15:40 · mudar'), findsOneWidget);

      await t.tap(find.byKey(const Key('btn_tirar_hora')));
      await t.pump();
      await t.pump();

      expect(api.chamadas, ['pronto:o1:null']);
      expect(find.text('Fica pronto às…'), findsOneWidget);
      expect(find.byKey(const Key('btn_tirar_hora')), findsNothing);
    });

    testWidgets('servidor recusa: avisa e a hora não fica gravada', (t) async {
      interruptor(true);
      final api = _ApiFalsa()..prometerOk = false;
      await montar(
          t,
          BotaoFicaProntoAs(
            orderId: 'o1',
            api: api,
            agora: () => agora,
            escolherHora: escolhe(const TimeOfDay(hour: 15, minute: 0)),
          ));
      await t.tap(find.byKey(const Key('btn_fica_pronto_as')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Não foi possível guardar a hora'), findsOneWidget);
      expect(find.text('Fica pronto às…'), findsOneWidget);
    });
  });

  group('aviso do cliente', () {
    testWidgets('ModoOcupadoLigado entrega false de fábrica e true se ligado',
        (t) async {
      interruptor(false);
      bool? visto;
      await montar(t, ModoOcupadoLigado(builder: (_, l) {
        visto = l;
        return const SizedBox.shrink();
      }));
      expect(visto, isFalse);

      interruptor(true);
      await montar(t, ModoOcupadoLigado(
        key: UniqueKey(),
        builder: (_, l) {
          visto = l;
          return const SizedBox.shrink();
        },
      ));
      expect(visto, isTrue);
    });

    testWidgets('o texto do aviso é o combinado com o Danilo', (t) async {
      await montar(t, const AvisoTempoMaior());
      expect(
          find.text('Tempo maior do que o normal: a loja está com muitos pedidos.'),
          findsOneWidget);
    });
  });
}
