// Agendar pedidos (item 5 do adendo 5, 29/10/2026): o seletor do cliente no
// carrinho e o estado da escolha (configuração, gravação, notas). O servidor
// é trocado por uma porta de mentira; o relógio é fixo (segunda 2/11/2026 às
// 10:00 de Lisboa — hora de inverno, Lisboa == UTC).
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/widgets/agendar_pedido_seletor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BusinessHours boom() {
  Map<String, dynamic> terSab() => {
        'open': '12:15',
        'close': '22:15',
        'closed': false,
        'break_start': '14:15',
        'break_end': '19:15',
      };
  return BusinessHours.fromJson({
    'mon': {'open': '19:15', 'close': '22:15', 'closed': false},
    'tue': terSab(),
    'wed': terSab(),
    'thu': terSab(),
    'fri': terSab(),
    'sat': terSab(),
    'sun': {'open': '12:15', 'close': '22:15', 'closed': true},
  });
}

final DateTime agoraFixo = DateTime.utc(2026, 11, 2, 10); // segunda 10:00
DateTime relogio() => agoraFixo;

class ApiFalsa implements AgendarPedidoApi {
  ApiFalsa({
    this.ligado = true,
    this.falhaJanelas = false,
    this.falhasAoGravar = 0,
    this.configFalha = false,
  });

  final bool ligado;
  final bool falhaJanelas;
  final bool configFalha;

  /// Quantas gravações falham antes de uma passar.
  int falhasAoGravar;
  int pedidosConfig = 0;
  final List<DateTime> diasPedidos = [];
  final List<(String, DateTime)> gravados = [];
  int tentativas = 0;

  @override
  Future<ConfigAgendar> config() async {
    pedidosConfig++;
    if (configFalha) throw Exception('sem rede');
    return ConfigAgendar(ligado: ligado);
  }

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async {
    diasPedidos.add(dia);
    if (falhaJanelas) throw Exception('sem rede');
    // Faz de servidor: a mesma regra da função pura.
    return janelasDoDia(horas: boom(), dia: dia, agora: agoraFixo);
  }

  @override
  Future<void> gravar(String orderId, DateTime instante) async {
    tentativas++;
    if (falhasAoGravar > 0) {
      falhasAoGravar--;
      throw Exception('falhou');
    }
    gravados.add((orderId, instante));
  }

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async => const [];
}

Future<AgendarPedidoEstado> estadoCom(ApiFalsa api) async {
  final e = AgendarPedidoEstado.paraTeste(api);
  await e.carregarConfig();
  return e;
}

/// Um ecrã largo: os dias vão numa lista horizontal e só se constrói o que se vê.
void ecraLargo(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget app(Widget filho) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: filho)));

Widget seletor(AgendarPedidoEstado estado, {bool fechada = false, BusinessHours? horas}) =>
    app(AgendarPedidoSeletor(
      restaurantId: 'boom',
      horas: horas ?? boom(),
      lojaFechadaAgora: fechada,
      estado: estado,
      relogio: relogio,
    ));

void main() {
  group('AgendarPedidoSeletor', () {
    testWidgets('interruptor desligado: não aparece nada', (t) async {
      ecraLargo(t);
      final estado = await estadoCom(ApiFalsa(ligado: false));
      await t.pumpWidget(seletor(estado));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-seletor')), findsNothing);
      expect(find.text('Agendar'), findsNothing);
    });

    testWidgets('loja aberta: começa em "Entregar agora"; "Agendar" mostra dias e janelas', (t) async {
      ecraLargo(t);
      final api = ApiFalsa();
      final estado = await estadoCom(api);
      await t.pumpWidget(seletor(estado));
      await t.pumpAndSettle();

      expect(find.text('Quando queres receber?'), findsOneWidget);
      expect(find.text('Entregar agora'), findsOneWidget);
      expect(find.byKey(const Key('agendar-dias')), findsNothing);
      expect(estado.escolha, isNull);
      expect(api.diasPedidos, isEmpty, reason: 'sem agendar, nem pergunta janelas');

      await t.tap(find.text('Agendar'));
      await t.pumpAndSettle();

      // Segunda 2/11 10:00: seg a sáb têm janelas (domingo fechado; segunda 9 já é além de 7 dias).
      expect(find.byKey(const Key('agendar-dias')), findsOneWidget);
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Amanhã'), findsOneWidget);
      expect(find.text('sáb 07/11'), findsOneWidget);
      expect(find.text('dom 08/11'), findsNothing);
      // Hoje é segunda: só a noite.
      expect(find.byKey(const Key('agendar-janela-19:30–20:00')), findsOneWidget);
      expect(find.byKey(const Key('agendar-janela-21:30–22:00')), findsOneWidget);
      expect(find.byKey(const Key('agendar-janela-12:30–13:00')), findsNothing);
      // Ainda sem escolha: o servidor não pede para escolher à força numa loja aberta.
      expect(estado.escolha, isNull);
      expect(find.byKey(const Key('agendar-falta')), findsOneWidget);

      await t.tap(find.byKey(const Key('agendar-janela-20:00–20:30')));
      await t.pumpAndSettle();

      expect(estado.escolhaPara('boom'), isTrue);
      expect(estado.escolha!.horas, '20:00–20:30');
      expect(find.byKey(const Key('agendar-resumo')), findsOneWidget);
      expect(find.text('Agendado para seg 02/11, 20:00–20:30'), findsOneWidget);
      expect(find.text('Podes cancelar sem custo até 1 h antes.'), findsOneWidget);
    });

    testWidgets('trocar de dia pede as janelas desse dia', (t) async {
      ecraLargo(t);
      final api = ApiFalsa();
      final estado = await estadoCom(api);
      await t.pumpWidget(seletor(estado));
      await t.pumpAndSettle();
      await t.tap(find.text('Agendar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Amanhã'));
      await t.pumpAndSettle();

      expect(api.diasPedidos.last, DateTime.utc(2026, 11, 3));
      // Terça: manhã e noite.
      expect(find.byKey(const Key('agendar-janela-12:30–13:00')), findsOneWidget);
      expect(find.byKey(const Key('agendar-janela-19:30–20:00')), findsOneWidget);
      // Nada dentro da pausa (14:15–19:15).
      expect(find.byKey(const Key('agendar-janela-15:00–15:30')), findsNothing);
      expect(find.byKey(const Key('agendar-janela-14:00–14:30')), findsNothing);
    });

    testWidgets('voltar a "Entregar agora" larga a escolha', (t) async {
      ecraLargo(t);
      final estado = await estadoCom(ApiFalsa());
      await t.pumpWidget(seletor(estado));
      await t.pumpAndSettle();
      await t.tap(find.text('Agendar'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agendar-janela-19:30–20:00')));
      await t.pumpAndSettle();
      expect(estado.escolha, isNotNull);

      await t.tap(find.text('Entregar agora'));
      await t.pumpAndSettle();
      expect(estado.escolha, isNull);
      expect(find.byKey(const Key('agendar-dias')), findsNothing);
    });

    testWidgets('loja FECHADA agora: "Entregar agora" desligado e a 1.ª janela já vem escolhida', (t) async {
      ecraLargo(t);
      final estado = await estadoCom(ApiFalsa());
      await t.pumpWidget(seletor(estado, fechada: true));
      await t.pumpAndSettle();

      final botao = t.widget<SegmentedButton<bool>>(find.byKey(const Key('agendar-modo')));
      expect(botao.segments.first.enabled, isFalse);
      expect(botao.selected, {true});
      expect(find.byKey(const Key('agendar-fechada')), findsOneWidget);
      expect(estado.escolhaPara('boom'), isTrue);
      expect(estado.escolha!.horas, '19:30–20:00');
      expect(find.text('Agendado para seg 02/11, 19:30–20:00'), findsOneWidget);
    });

    testWidgets('sem resposta do servidor mostra as janelas do horário da loja', (t) async {
      ecraLargo(t);
      final estado = await estadoCom(ApiFalsa(falhaJanelas: true));
      await t.pumpWidget(seletor(estado));
      await t.pumpAndSettle();
      await t.tap(find.text('Agendar'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-janela-19:30–20:00')), findsOneWidget);
    });

    testWidgets('loja sem nenhum dia útil: diz que não aceita agendados', (t) async {
      ecraLargo(t);
      final fechadaSempre = BusinessHours.fromJson({
        for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
          d: {'open': '12:00', 'close': '22:00', 'closed': true},
      });
      final estado = await estadoCom(ApiFalsa());
      await t.pumpWidget(seletor(estado, fechada: true, horas: fechadaSempre));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-sem-dias')), findsOneWidget);
      expect(find.text('Esta loja não aceita pedidos agendados neste momento.'), findsOneWidget);
      expect(estado.escolha, isNull);
    });
  });

  group('AgendarPedidoEstado', () {
    final janela = JanelaAgendada(
      inicio: DateTime.utc(2026, 11, 3, 19, 30),
      fim: DateTime.utc(2026, 11, 3, 20),
    );

    test('a configuração falhada conta como DESLIGADO', () async {
      final e = AgendarPedidoEstado.paraTeste(ApiFalsa(configFalha: true));
      await e.carregarConfig();
      expect(e.ligado, isFalse);
    });

    test('a configuração tem cache de 5 minutos; "forçar" volta ao servidor', () async {
      final api = ApiFalsa();
      final e = AgendarPedidoEstado.paraTeste(api);
      final t0 = DateTime.utc(2026, 11, 2, 10);
      await e.carregarConfig(agora: t0);
      await e.carregarConfig(agora: t0.add(const Duration(minutes: 4)));
      expect(api.pedidosConfig, 1);
      await e.carregarConfig(agora: t0.add(const Duration(minutes: 6)));
      expect(api.pedidosConfig, 2);
      await e.carregarConfig(forcar: true, agora: t0.add(const Duration(minutes: 6)));
      expect(api.pedidosConfig, 3);
    });

    test('gravarEscolha grava o instante certo no pedido e limpa a escolha', () async {
      final api = ApiFalsa();
      final e = await estadoCom(api);
      e.escolher('boom', janela);
      final ok = await e.gravarEscolha('pedido-1', restaurantId: 'boom', pausa: Duration.zero);
      expect(ok, isTrue);
      expect(api.gravados, [('pedido-1', DateTime.utc(2026, 11, 3, 19, 30))]);
      expect(e.escolha, isNull);
    });

    test('escolha de OUTRA loja nunca é gravada neste pedido', () async {
      final api = ApiFalsa();
      final e = await estadoCom(api);
      e.escolher('outra-loja', janela);
      final ok = await e.gravarEscolha('pedido-1', restaurantId: 'boom', pausa: Duration.zero);
      expect(ok, isTrue);
      expect(api.tentativas, 0);
      expect(e.notaParaLoja('boom'), isNull);
    });

    test('interruptor desligado: não grava nada', () async {
      final api = ApiFalsa(ligado: false);
      final e = await estadoCom(api);
      e.escolher('boom', janela);
      expect(await e.gravarEscolha('pedido-1', restaurantId: 'boom', pausa: Duration.zero), isTrue);
      expect(api.tentativas, 0);
      expect(e.notaParaLoja('boom'), isNull);
    });

    test('falha a gravar: tenta 3 vezes e devolve false', () async {
      final api = ApiFalsa(falhasAoGravar: 99);
      final e = await estadoCom(api);
      e.escolher('boom', janela);
      final ok = await e.gravarEscolha('pedido-1', restaurantId: 'boom', pausa: Duration.zero);
      expect(ok, isFalse);
      expect(api.tentativas, 3);
      expect(e.escolha, isNull, reason: 'o carrinho foi-se; não fica escolha pendurada');
    });

    test('falha uma vez e passa na 2.ª tentativa', () async {
      final api = ApiFalsa(falhasAoGravar: 1);
      final e = await estadoCom(api);
      e.escolher('boom', janela);
      expect(await e.gravarEscolha('pedido-1', restaurantId: 'boom', pausa: Duration.zero), isTrue);
      expect(api.tentativas, 2);
      expect(api.gravados.length, 1);
    });

    test('a nota para o parceiro diz a janela, em português', () async {
      final e = await estadoCom(ApiFalsa());
      e.escolher('boom', janela);
      expect(e.notaParaLoja('boom'), 'Pedido AGENDADO para ter 03/11, 19:30–20:00');
      expect(e.notaParaLoja('outra'), isNull);
    });
  });
}
