// Convite nas categorias da home (missão home-categorias-convite-2026-11-27).
//
// Provas b) da missão: a onda arranca aos 2,5 s; pára ao toque e ao deslizar;
// só repete uma vez; não arranca com "reduzir animações" nem com a chave a
// false; não volta a correr no mesmo arranque; o toque no mosaico dá escala
// 0,96 com vibração e o onTap original é chamado uma vez só.
import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/widgets/bora/bora_tile_card.dart';
import 'package:bora_app/widgets/home/convite_categorias.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _n = 9; // 3 linhas de 4 (a última incompleta), como uma home pequena.

Widget _grelha({
  required ValueNotifier<bool> ligado,
  bool semAnimacoes = false,
  bool navegacaoAcessivel = false,
  ScrollController? rolar,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: semAnimacoes,
          accessibleNavigation: navegacaoAcessivel,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            controller: rolar,
            child: Column(
              children: [
                ConviteCategorias(
                  colunas: 4,
                  total: _n,
                  ligado: ligado,
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < _n; i++)
                        ConviteMosaico(
                          indice: i,
                          child: ColoredBox(
                            color: const Color(0xFF16A34A),
                            child: Text('m$i'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

double _escala(WidgetTester tester, int i) => tester
    .widget<ScaleTransition>(find.byKey(ValueKey('convite-mosaico-$i')))
    .scale
    .value;

/// Maior escala vista em qualquer mosaico ao longo de [total], em passos de 20 ms.
Future<double> _picoDurante(WidgetTester tester, Duration total) async {
  var pico = 1.0;
  final passos = total.inMilliseconds ~/ 20;
  for (var k = 0; k < passos; k++) {
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < _n; i++) {
      final e = _escala(tester, i);
      if (e > pico) pico = e;
    }
  }
  return pico;
}

void main() {
  setUp(ConviteCategorias.reporParaTestes);

  testWidgets('a onda arranca aos 2,5 s, em onda, e repete só uma vez 7 s depois',
      (tester) async {
    final ligado = ValueNotifier(true);
    await tester.pumpWidget(_grelha(ligado: ligado));

    // Antes dos 2,5 s: tudo quieto.
    expect(await _picoDurante(tester, const Duration(milliseconds: 2400)), 1.0);

    // Aos 2,5 s arranca: o primeiro mosaico chega a ~1,05 a meio dos 460 ms.
    await tester.pump(const Duration(milliseconds: 100)); // 2,5 s: o temporizador dispara
    await tester.pump(); // primeiro frame da onda
    await tester.pump(const Duration(milliseconds: 230));
    expect(_escala(tester, 0), closeTo(1.05, 0.002));
    // Atraso por mosaico: o 5 (coluna 1, linha 1) começa 45 + 70 = 115 ms depois.
    expect(_escala(tester, 5), lessThan(_escala(tester, 0)));
    expect(_escala(tester, 5), greaterThan(1.0));

    // Acaba e volta a 1.
    await tester.pump(const Duration(milliseconds: 800));
    for (var i = 0; i < _n; i++) {
      expect(_escala(tester, i), 1.0);
    }

    // Uma repetição, 7 s depois do arranque da primeira.
    expect(await _picoDurante(tester, const Duration(milliseconds: 5800)), 1.0);
    expect(await _picoDurante(tester, const Duration(seconds: 2)),
        greaterThan(1.04));

    // E mais nenhuma.
    expect(await _picoDurante(tester, const Duration(seconds: 20)), 1.0);
  });

  testWidgets('pára de vez ao primeiro toque, em qualquer sítio', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true)));
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(const Offset(5, 590)); // fora da grelha
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('um toque a meio da onda corta-a e volta tudo a 1', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true)));
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_escala(tester, 0), greaterThan(1.0));
    await tester.tapAt(const Offset(5, 590));
    await tester.pump();
    for (var i = 0; i < _n; i++) {
      expect(_escala(tester, i), 1.0);
    }
    expect(await _picoDurante(tester, const Duration(seconds: 10)), 1.0);
  });

  testWidgets('pára ao deslizar a lista', (tester) async {
    final rolar = ScrollController();
    addTearDown(rolar.dispose);
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true), rolar: rolar));
    await tester.pump(const Duration(seconds: 1));
    rolar.jumpTo(40);
    await tester.pump();
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('pára quando a app vai para segundo plano', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true)));
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('não arranca com "reduzir animações" ligado', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true), semAnimacoes: true));
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('não arranca com navegação acessível (leitor de ecrã)', (tester) async {
    await tester.pumpWidget(
        _grelha(ligado: ValueNotifier(true), navegacaoAcessivel: true));
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('não arranca com home_convite_categorias = false', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(false)));
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  testWidgets('não volta a correr ao voltar à home no mesmo arranque', (tester) async {
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true)));
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(await _picoDurante(tester, const Duration(milliseconds: 600)),
        greaterThan(1.04));
    // A home sai e volta (outro widget, depois a grelha de novo).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_grelha(ligado: ValueNotifier(true)));
    expect(await _picoDurante(tester, const Duration(seconds: 12)), 1.0);
  });

  group('toque no mosaico', () {
    late List<MethodCall> chamadas;

    setUp(() {
      chamadas = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (c) async {
        chamadas.add(c);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Widget mosaico(VoidCallback onTap, {bool semAnimacoes = false}) => MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: semAnimacoes),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 90,
                    height: 102,
                    child: BoraTileCard.image(
                      label: 'Restaurantes',
                      gradient: AppColors.tileRestaurants,
                      imageAsset: 'assets/categories/cat_restaurantes.png',
                      onTap: onTap,
                      compacto: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    double escalaToque(WidgetTester tester) => tester
        .widget<AnimatedScale>(find.byKey(const Key('bora_tile_toque')))
        .scale;

    bool vibrou() => chamadas.any((c) =>
        c.method == 'HapticFeedback.vibrate' &&
        c.arguments == 'HapticFeedbackType.selectionClick');

    testWidgets('pressionar dá 0,96, largar volta a 1, vibra e chama onTap uma vez',
        (tester) async {
      var toques = 0;
      await tester.pumpWidget(mosaico(() => toques++));
      expect(escalaToque(tester), 1.0);

      final gesto = await tester.press(find.text('Restaurantes'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(escalaToque(tester), 0.96);
      final animada = tester.widget<AnimatedScale>(
          find.byKey(const Key('bora_tile_toque')));
      expect(animada.duration, const Duration(milliseconds: 120));
      expect(animada.curve, const Cubic(0.23, 1, 0.32, 1));

      await gesto.up();
      await tester.pumpAndSettle();
      expect(escalaToque(tester), 1.0);
      expect(toques, 1);
      expect(vibrou(), isTrue);
      // Sem som: nenhum SystemSound.play.
      expect(chamadas.where((c) => c.method == 'SystemSound.play'), isEmpty);
    });

    testWidgets('com "reduzir animações" não encolhe mas vibra', (tester) async {
      var toques = 0;
      await tester.pumpWidget(mosaico(() => toques++, semAnimacoes: true));
      final gesto = await tester.press(find.text('Restaurantes'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(escalaToque(tester), 1.0);
      await gesto.up();
      await tester.pumpAndSettle();
      expect(toques, 1);
      expect(vibrou(), isTrue);
    });
  });
}
