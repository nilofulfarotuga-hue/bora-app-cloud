// B4 (2026-06-11) — sonda de pintura do header.
// Prova empírica: renderiza os padrões de AppBar usados na app com o tema
// real e lê pixels da zona do header para verificar se o gradiente pinta
// (verde #16A34A) ou se fica o fundo claro do Scaffold (#F0F2EF).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/widgets/bora/bora_screen_app_bar.dart';

// toImage/toByteData usam o engine async — fora de runAsync o fake event
// loop do flutter_test fica pendurado até ao timeout (visto na 1ª corrida).
Future<ui.Image> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() => boundary.toImage()))!;
}

Future<Color> _pixel(WidgetTester tester, ui.Image img, int x, int y) async {
  final data = (await tester.runAsync(
      () => img.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final offset = (y * img.width + x) * 4;
  final r = data!.getUint8(offset);
  final g = data.getUint8(offset + 1);
  final b = data.getUint8(offset + 2);
  return Color.fromARGB(255, r, g, b);
}

// Color.r/g/b são normalizados 0..1 no Flutter 3.41 (não 0..255).
bool _isGreenish(Color c) => c.g > 0.4 && c.g > c.r + 0.15 && c.g > c.b + 0.15;
bool _isLight(Color c) => c.r > 0.8 && c.g > 0.8 && c.b > 0.8;

void main() {
  testWidgets('BoraScreenAppBar pinta o header verde', (tester) async {
    const key = Key('probe');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const RepaintBoundary(
        key: key,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: BoraScreenAppBar(title: 'Agenda'),
          body: SizedBox.expand(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final img = await _capture(tester, key);
    // Pontos dentro da toolbar (toolbar ~56px + status bar 0 no test env).
    final p1 = await _pixel(tester, img, 10, 28);
    final p2 = await _pixel(tester, img, img.width ~/ 2, 28);
    final p3 = await _pixel(tester, img, img.width - 10, 28);
    debugPrint('[PROBE BoraScreenAppBar] p1=$p1 p2=$p2 p3=$p3 '
        'size=${img.width}x${img.height}');
    expect(_isGreenish(p1), isTrue,
        reason: 'header esq. devia ser verde, foi $p1');
    expect(_isGreenish(p2), isTrue,
        reason: 'header centro devia ser verde, foi $p2');
    expect(_isGreenish(p3), isTrue,
        reason: 'header dir. devia ser verde, foi $p3');
  });

  testWidgets('AppBar pós-fix (primary + DecoratedBox inline) pinta verde',
      (tester) async {
    const key = Key('probe2');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            // Padrão B4 pós-fix: fundo sólido primary garante o header verde
            // mesmo com o flexibleSpace DecoratedBox a não pintar (provado:
            // pixels #F0F2EF na 1ª corrida com Colors.transparent).
            backgroundColor: AppColors.primary,
            elevation: 0,
            flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.headerGradient),
            ),
            foregroundColor: Colors.white,
            title: const Text('Sugestões IA'),
          ),
          body: const SizedBox.expand(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final img = await _capture(tester, key);
    final p = await _pixel(tester, img, img.width ~/ 2, 28);
    debugPrint('[PROBE inline pós-fix] p=$p');
    expect(_isGreenish(p), isTrue,
        reason: 'header devia ser verde, foi $p (claro=${_isLight(p)})');
  });
}
