import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Cartão por fases · 11/10/2026] Queixa do Danilo numa corrida real: o
/// painel de baixo do motorista ficava minimizado, subia com dificuldade e,
/// aberto, ficava fininho com o "Finalizar viagem" cortado; dizia sempre
/// "recolha → destino" e usava a frase do CLIENTE ("Motorista a caminho").
///
/// O ecrã inteiro não monta num teste (mapa nativo, GPS, Supabase). Monta-se
/// o que ele monta: o cabeçalho da fase, a gaveta e o botão fixo no fundo.
TvdeRide _corrida(
  String status, {
  String id = 'r1',
  int extraStops = 0,
  DateTime? marcada,
  bool emFila = false,
}) =>
    TvdeRide.fromMap({
      'id': id,
      'client_id': 'c1',
      'status': status,
      'origin_lat': 40.5285,
      'origin_lng': -7.2516,
      'dest_lat': 40.5407,
      'dest_lng': -7.2677,
      'est_distance_km': 4.5,
      'est_fare_cents': 700,
      'driver_earn_cents': 520,
      'payment_method': 'cash',
      'origin_label': 'Rua Marquês de Pombal 12',
      'dest_label': 'Estação da Guarda',
      'extra_stops_count': extraStops,
      if (marcada != null) 'scheduled_at': marcada.toUtc().toIso8601String(),
      if (emFila) 'is_queued': true,
    });

final _paragem = TvdeRideStop(
  id: 's1',
  seq: 1,
  label: 'Farmácia Central',
  lat: 40.535,
  lng: -7.26,
  feeCents: 200,
  driverCents: 150,
);

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  group('título do motorista por fase (driverPhaseTitle)', () {
    test('a caminho: "A caminho da recolha" + nome; sem nome, só a fase', () {
      final r = _corrida('motorista_a_caminho');
      expect(r.driverPhaseTitle(passengerName: 'Maria'),
          'A caminho da recolha · Maria');
      expect(r.driverPhaseTitle(), 'A caminho da recolha');
      expect(r.driverPhaseTitle(passengerName: '  '), 'A caminho da recolha');
    });

    test('reserva por confirmar conta como "a caminho"', () {
      final r = _corrida('motorista_atribuido',
          marcada: DateTime.now().add(const Duration(minutes: 15)));
      expect(r.driverPhaseTitle(passengerName: 'Rui'),
          'A caminho da recolha · Rui');
    });

    test('chegou: "À espera de <nome>"; sem nome, "do passageiro"', () {
      final r = _corrida('motorista_chegou');
      expect(r.driverPhaseTitle(passengerName: 'Maria'), 'À espera de Maria');
      expect(r.driverPhaseTitle(), 'À espera do passageiro');
    });

    test('em viagem: "A levar <nome> ao destino"; sem nome, "o passageiro"',
        () {
      final r = _corrida('em_andamento');
      expect(r.driverPhaseTitle(passengerName: 'Maria'),
          'A levar Maria ao destino');
      expect(r.driverPhaseTitle(), 'A levar o passageiro ao destino');
    });

    test('o statusLabel do CLIENTE não mudou (é ele que o cliente lê)', () {
      expect(_corrida('motorista_a_caminho').statusLabel, 'Motorista a caminho');
      expect(_corrida('motorista_chegou').statusLabel, 'O motorista chegou');
      expect(_corrida('em_andamento').statusLabel, 'Viagem em curso');
    });

    test('nunca leva o ETA no título', () {
      for (final s in [
        'motorista_a_caminho',
        'motorista_chegou',
        'em_andamento'
      ]) {
        expect(_corrida(s).driverPhaseTitle(passengerName: 'Maria'),
            isNot(matches(RegExp(r'\d+ min'))));
      }
    });
  });

  group('cabeçalho da fase (TvdeCorridaCabecalho)', () {
    testWidgets('a caminho: SÓ a morada de recolha, "Chegas em", o ganho',
        (tester) async {
      var navegou = 0;
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _corrida('motorista_a_caminho'),
        passengerName: 'Maria',
        etaMin: 4,
        onNavegar: () => navegou++,
      )));
      expect(find.text('A caminho da recolha · Maria'), findsOneWidget);
      expect(find.text('Rua Marquês de Pombal 12'), findsOneWidget);
      expect(find.textContaining('Estação da Guarda'), findsNothing,
          reason: 'a caminho, o destino não aparece no cabeçalho');
      expect(find.textContaining('→'), findsNothing);
      expect(find.text('Chegas em ~4 min'), findsOneWidget);
      expect(find.textContaining(RegExp(r'~\d+ min')), findsOneWidget,
          reason: 'o ETA aparece UMA vez só');
      expect(find.text('Ganhas €5.20'), findsOneWidget);
      expect(find.text('Motorista a caminho'), findsNothing,
          reason: 'frase do cliente no ecrã do motorista');
      expect(find.bySemanticsLabel('Navegar até à recolha'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tvde_corrida_navegar')));
      expect(navegou, 1);
    });

    testWidgets('chegou: "À espera de <nome>", cronómetro e a recolha',
        (tester) async {
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _corrida('motorista_chegou'),
        passengerName: 'Maria',
        etaMin: 1,
        esperaSegundos: 65,
        onNavegar: () {},
      )));
      expect(find.text('À espera de Maria'), findsOneWidget);
      expect(find.text('À espera do passageiro · 01:05'), findsOneWidget);
      expect(find.text('Rua Marquês de Pombal 12'), findsOneWidget);
      expect(find.textContaining('Estação da Guarda'), findsNothing);
      expect(find.textContaining('~1 min'), findsNothing,
          reason: 'à espera não há "chegas em"');
    });

    testWidgets('em viagem: SÓ a morada do destino e "Chegada em"',
        (tester) async {
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _corrida('em_andamento'),
        passengerName: 'Maria',
        etaMin: 7,
        onNavegar: () {},
      )));
      expect(find.text('A levar Maria ao destino'), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      expect(find.text('Estação da Guarda'), findsOneWidget);
      expect(find.textContaining('Marquês de Pombal'), findsNothing,
          reason: 'em viagem, a recolha já não aparece no cabeçalho');
      expect(find.text('Chegada em ~7 min'), findsOneWidget);
      expect(find.textContaining(RegExp(r'~\d+ min')), findsOneWidget);
      expect(find.text('Viagem em curso'), findsNothing);
      expect(find.bySemanticsLabel('Navegar até ao destino'), findsOneWidget);
    });

    testWidgets('em viagem com paragem: a morada grande é a da paragem',
        (tester) async {
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _corrida('em_andamento', extraStops: 1),
        etaMin: 9,
        proximaParagem: _paragem,
        onNavegar: () {},
      )));
      expect(find.text('A levar o passageiro ao destino'), findsOneWidget);
      expect(find.text('Paragem 1'), findsOneWidget);
      expect(find.text('Farmácia Central'), findsOneWidget);
      expect(find.textContaining('Estação da Guarda'), findsNothing);
      // O tempo é até ao DESTINO (a rota passa pela paragem) — e di-lo.
      expect(find.text('Chegada ao destino em ~9 min'), findsOneWidget);
    });

    testWidgets('balão de mensagem por ler fica à vista no cabeçalho',
        (tester) async {
      var abriu = 0;
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _corrida('motorista_a_caminho'),
        naoLidas: 2,
        onChat: () => abriu++,
      )));
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      expect(abriu, 1);
    });
  });

  group('botão principal fixo (TvdeCorridaBotaoPrincipal)', () {
    Future<String> rotulo(WidgetTester tester, TvdeRide r) async {
      await tester.pumpWidget(_app(TvdeCorridaBotaoPrincipal(
          ride: r, busy: false, onAtualizar: () {})));
      final t = tester.widget<Text>(find.descendant(
          of: find.byType(ElevatedButton), matching: find.byType(Text)));
      return t.data!;
    }

    testWidgets('os ramos de sempre, um por fase', (tester) async {
      expect(await rotulo(tester, _corrida('motorista_a_caminho')),
          'Cheguei ao passageiro');
      expect(await rotulo(tester, _corrida('motorista_chegou')),
          'Iniciar viagem');
      expect(
          await rotulo(tester, _corrida('em_andamento')), 'Finalizar viagem');
      expect(
          await rotulo(
              tester,
              _corrida('motorista_atribuido',
                  marcada: DateTime.now().add(const Duration(minutes: 15)))),
          'Vou a caminho');
      expect(await rotulo(tester, _corrida('motorista_atribuido', emFila: true)),
          'Começa ao terminares esta viagem');
      expect(await rotulo(tester, _corrida('xpto')),
          'A processar… toca para atualizar');
    });

    testWidgets('a enviar: o botão fica parado (guarda local)', (tester) async {
      var n = 0;
      await tester.pumpWidget(_app(TvdeCorridaBotaoPrincipal(
          ride: _corrida('em_andamento'),
          busy: true,
          onFinalizar: () => n++)));
      final b = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(b.onPressed, isNull);
      expect(n, 0);
    });
  });

  group('gaveta + botão no fundo (como o ecrã os monta)', () {
    late DraggableScrollableController ctrl;
    setUp(() => ctrl = DraggableScrollableController());
    tearDown(() => ctrl.dispose());

    Widget ecra({
      required TvdeRide ride,
      required String fase,
      String? nome = 'Maria',
      VoidCallback? onFinalizar,
    }) {
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Corrida')),
          bottomNavigationBar: TvdeCorridaBotaoPrincipal(
            ride: ride,
            busy: false,
            onCheguei: () {},
            onIniciar: () {},
            onFinalizar: onFinalizar ?? () {},
          ),
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.grey)),
              Positioned.fill(
                child: TvdeCorridaGaveta(
                  controller: ctrl,
                  fase: fase,
                  cabecalho: TvdeCorridaCabecalho(
                    ride: ride,
                    passengerName: nome,
                    etaMin: 6,
                    esperaSegundos: 30,
                    onNavegar: () {},
                  ),
                  detalhe: const SizedBox(
                    height: 700,
                    child: Text('detalhe da corrida'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Future<void> telemovel(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets(
        'recolhida: o cabeçalho inteiro à vista e o "Finalizar viagem" '
        'visível e tocável', (tester) async {
      await telemovel(tester);
      var finalizou = 0;
      await tester.pumpWidget(ecra(
          ride: _corrida('em_andamento'),
          fase: 'r1|em_andamento',
          onFinalizar: () => finalizou++));
      await tester.pumpAndSettle();

      expect(ctrl.size, lessThan(0.45), reason: 'nasce recolhida');
      expect(ctrl.size, greaterThan(0.14),
          reason: 'recolhida mostra o cabeçalho, não uma linha cortada');

      final ecraRect = Offset.zero & const Size(390, 844);
      final botao = find.text('Finalizar viagem');
      expect(botao, findsOneWidget);
      expect(ecraRect.contains(tester.getRect(botao).bottomRight), isTrue);
      // A gaveta não o tapa: o toque chega ao botão.
      await tester.tap(botao);
      expect(finalizou, 1);

      // O cabeçalho cabe todo na parte visível da gaveta.
      final gaveta = tester.getRect(find.byType(DecoratedBox).first);
      for (final t in [
        'A levar Maria ao destino',
        'Estação da Guarda',
        'Chegada em ~6 min',
        'Ganhas €5.20',
      ]) {
        final r = tester.getRect(find.text(t));
        expect(r.top, greaterThanOrEqualTo(gaveta.top), reason: t);
        expect(r.bottom, lessThanOrEqualTo(tester.getRect(botao).top),
            reason: '"$t" fica por baixo do botão / cortado');
      }
      expect(tester.getRect(find.text('detalhe da corrida')).top,
          greaterThan(tester.getRect(botao).top - 60),
          reason: 'recolhida, o detalhe fica escondido');
    });

    testWidgets('abre muito além de 0.52 a puxar pela pega', (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(
          ecra(ride: _corrida('em_andamento'), fase: 'r1|em_andamento'));
      await tester.pumpAndSettle();
      final recolhida = ctrl.size;

      await tester.drag(find.byKey(const ValueKey('tvde_corrida_pega')),
          const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(ctrl.size, greaterThan(0.52));
      expect(ctrl.size, closeTo(TvdeCorridaGaveta.maxAberta, 0.01));
      expect(find.text('Finalizar viagem'), findsOneWidget,
          reason: 'aberta, o botão continua no fundo');
      expect(ctrl.size, greaterThan(recolhida));
    });

    testWidgets('tocar no cabeçalho alterna recolhida ↔ aberta',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(
          ecra(ride: _corrida('em_andamento'), fase: 'r1|em_andamento'));
      await tester.pumpAndSettle();
      final recolhida = ctrl.size;

      await tester.tap(find.text('A levar Maria ao destino'));
      await tester.pumpAndSettle();
      expect(ctrl.size, greaterThan(0.52));

      await tester.tap(find.byKey(const ValueKey('tvde_corrida_pega')));
      await tester.pumpAndSettle();
      expect(ctrl.size, closeTo(recolhida, 0.005));
    });

    testWidgets('fase nova: volta à posição recolhida NOVA', (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(ecra(
          ride: _corrida('motorista_chegou'), fase: 'r1|motorista_chegou'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('À espera de Maria'));
      await tester.pumpAndSettle();
      expect(ctrl.size, greaterThan(0.52), reason: 'o motorista abriu-a');

      await tester.pumpWidget(
          ecra(ride: _corrida('em_andamento'), fase: 'r1|em_andamento'));
      await tester.pumpAndSettle();
      expect(ctrl.size, lessThan(0.45),
          reason: 'ao iniciar a viagem volta à recolhida (com o essencial)');
      expect(find.text('A levar Maria ao destino'), findsOneWidget);
      expect(find.text('Finalizar viagem'), findsOneWidget);
    });

    testWidgets('o nome chega depois: a recolhida acompanha a altura nova',
        (tester) async {
      await telemovel(tester);
      await tester.pumpWidget(ecra(
          ride: _corrida('motorista_a_caminho'),
          fase: 'r1|motorista_a_caminho',
          nome: null));
      await tester.pumpAndSettle();
      final antes = ctrl.size;
      await tester.pumpWidget(ecra(
          ride: _corrida('motorista_a_caminho'),
          fase: 'r1|motorista_a_caminho',
          nome: 'Maria Fernanda de Albuquerque e Castro Sampaio'));
      await tester.pumpAndSettle();
      expect(ctrl.size, greaterThan(antes),
          reason: 'título em duas linhas → recolhida mais alta, nada cortado');
      final titulo = tester.getRect(find.textContaining('A caminho da recolha'));
      final botao = tester.getRect(find.text('Cheguei ao passageiro'));
      expect(titulo.bottom, lessThan(botao.top));
      expect(find.text('Rua Marquês de Pombal 12'), findsOneWidget);
      final morada = tester.getRect(find.text('Rua Marquês de Pombal 12'));
      expect(morada.bottom, lessThan(botao.top));
    });
  });

  // [Juiz 11/10] O ecrã real redesenha-se DURANTE o arrasto (a mira segue a
  // gaveta por setState, o cronómetro bate de 1 em 1 s). Com `snapSizes` a
  // nascer lista nova em cada build, o DraggableScrollableSheet comparava por
  // identidade, mandava "assentar" (goBallistic) e cancelava o dedo: a gaveta
  // só abria com toque. O `tester.drag` de cima não o via — manda o gesto
  // inteiro sem frames pelo meio e sem pai a redesenhar.
  testWidgets(
      'arrasto lento com o dedo abre a gaveta mesmo com o ecrã a '
      'redesenhar-se a cada frame', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ctrl = DraggableScrollableController();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(MaterialApp(home: _EcraQueSegue(ctrl: ctrl)));
    await tester.pumpAndSettle();
    final recolhida = ctrl.size;

    final dedo = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tvde_corrida_pega'))));
    for (var i = 0; i < 20; i++) {
      await dedo.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final comODedo = ctrl.size;
    await dedo.up();
    await tester.pumpAndSettle();

    expect(comODedo, greaterThan(recolhida + 0.2),
        reason: 'o arrasto foi cancelado a meio — a gaveta não acompanhou o dedo');
    expect(ctrl.size, greaterThan(recolhida + 0.1));
    expect(tester.state<_EcraQueSegueState>(find.byType(_EcraQueSegue)).builds,
        greaterThan(3),
        reason: 'o pai tem de se redesenhar durante o arrasto, como no ecrã');
  });
}

/// Réplica do que o ecrã real faz à volta da gaveta: segue a altura dela com
/// setState (o NotificationListener da mira e do SOS).
class _EcraQueSegue extends StatefulWidget {
  const _EcraQueSegue({required this.ctrl});
  final DraggableScrollableController ctrl;
  @override
  State<_EcraQueSegue> createState() => _EcraQueSegueState();
}

class _EcraQueSegueState extends State<_EcraQueSegue> {
  double altura = 0.25;
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    final r = _corrida('em_andamento');
    return Scaffold(
      bottomNavigationBar:
          TvdeCorridaBotaoPrincipal(ride: r, busy: false, onFinalizar: () {}),
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.grey)),
          Positioned(
              right: 8, bottom: 600 * altura, child: const Text('mira')),
          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                if ((n.extent - altura).abs() > 0.01) {
                  setState(() => altura = n.extent);
                }
                return false;
              },
              child: TvdeCorridaGaveta(
                controller: widget.ctrl,
                fase: 'r1|em_andamento',
                cabecalho: TvdeCorridaCabecalho(
                    ride: r, passengerName: 'Maria', etaMin: 6),
                detalhe:
                    const SizedBox(height: 700, child: Text('detalhe')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
