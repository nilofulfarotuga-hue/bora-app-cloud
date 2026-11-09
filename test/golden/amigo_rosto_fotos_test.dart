// O AMIGO — fotografias das expressões (missão m11-amigo-rosto, 09/11/2026).
//
// Pinta o rosto parado nas 6 expressões do pedido do Danilo (alegre, triste,
// surpreso, pensativo, confuso, a falar) e nas 2 variantes do painel (só a
// cara; cara com camisa e o logótipo da Bora) e grava um PNG de cada uma em
// test/golden/_fotos/, mais uma folha com todas. Falha se alguma lançar ou
// se duas expressões saírem iguais (uma expressão que não mudou nada).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bora_app/widgets/amigo/amigo_rosto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

const _seis = [
  AmigoEmocao.alegre,
  AmigoEmocao.triste,
  AmigoEmocao.surpreso,
  AmigoEmocao.pensativo,
  AmigoEmocao.confuso,
  AmigoEmocao.aFalar,
];

Future<Uint8List> _png(WidgetTester tester, GlobalKey chave) async {
  late Uint8List out;
  await tester.runAsync(() async {
    final b = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    out = bytes!.buffer.asUint8List();
  });
  return out;
}

Future<ByteData> _rgba(WidgetTester tester, GlobalKey chave) async {
  late ByteData out;
  await tester.runAsync(() async {
    final b = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    out = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return out;
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
  });

  for (final variante in AmigoVariante.values) {
    final nomeVar = variante == AmigoVariante.rosto ? 'rosto' : 'rosto_camisa';
    testWidgets('6 expressões, variante $nomeVar: desenham e são todas diferentes',
        (tester) async {
      await tester.runAsync(() => AmigoLogoBora.carregar());
      expect(AmigoLogoBora.imagem, isNotNull,
          reason: 'o logótipo da Bora tem de carregar para a camisa');
      tester.view.physicalSize = const Size(1400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final chaves = {for (final e in _seis) e: GlobalKey()};
      final folha = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFF0FDF4),
          body: RepaintBoundary(
            key: folha,
            child: Container(
              color: const Color(0xFFF0FDF4),
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _seis)
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(amigoEmocaoRotulo(e),
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF15803D))),
                      RepaintBoundary(
                        key: chaves[e],
                        child: AmigoRosto(
                            tamanho: 200, emocao: e, variante: variante, parado: true),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final vistos = <String, AmigoEmocao>{};
      for (final e in _seis) {
        final png = await _png(tester, chaves[e]!);
        File('test/golden/_fotos/amigo_${nomeVar}_${amigoEmocaoNome(e)}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png);
        final rgba = await _rgba(tester, chaves[e]!);
        final assinatura = rgba.buffer.asUint8List().fold<int>(
            0, (h, b) => (h * 31 + b) & 0x7fffffff);
        expect(vistos.containsKey('$assinatura'), isFalse,
            reason: '${amigoEmocaoNome(e)} saiu igual a '
                '${vistos['$assinatura'] == null ? '' : amigoEmocaoNome(vistos['$assinatura']!)}');
        vistos['$assinatura'] = e;
      }
      File('test/golden/_fotos/amigo_${nomeVar}_folha.png')
          .writeAsBytesSync(await _png(tester, folha));
    });
  }

  testWidgets('cores certas: casca verde Bora, ecrã escuro, antena laranja',
      (tester) async {
    final chave = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: chave,
          child: const AmigoRosto(tamanho: 280, parado: true),
        ),
      ),
    ));
    final rgba = await _rgba(tester, chave);
    final w = 280;
    // Na variante "rosto" a caixa começa em x=10, y=-6 e a escala é 1.
    ({int r, int g, int b}) px(double x, double y) {
      final i = (((y + 6).round()) * w + (x - 10).round()) * 4;
      final b = rgba.buffer.asUint8List();
      return (r: b[i], g: b[i + 1], b: b[i + 2]);
    }

    final casca = px(150, 44); // topo da cabeça
    expect(casca.g > casca.r && casca.g > casca.b, isTrue,
        reason: 'casca verde, veio $casca');
    final ecra = px(150, 200); // fundo do ecrã, sem olhos nem boca
    expect((ecra.r + ecra.g + ecra.b) < 160, isTrue, reason: 'ecrã escuro, veio $ecra');
    final antena = px(150, 12);
    expect(antena.r > 200 && antena.b < 120, isTrue, reason: 'antena laranja, veio $antena');
  });
}
