// F-OLHO · Camada 1 — FÁBRICA DE FOTOS (varredura 2026-08-17)
//
// Renderiza telas EM MEMÓRIA (flutter test — sem emulador, sem monitor, sem
// cabo) em 3 tamanhos de ecrã + variante com teclado aberto, e grava um PNG
// de cada uma em test/golden/_fotos/ (pasta versionada).
//
// REGRA DE OURO: overflow/estouro no Flutter lança FlutterError no teste →
// o teste FALHA sozinho. Botão cortado e tela estourada viram ERRO automático.
// Cada foto também é validada com takeException() == null explícito.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carrega a Inter real (assets/fonts) — sem isto o flutter test usa a fonte
/// Ahem (blocos), que engorda todos os textos e cria estouros FALSOS, além de
/// fotos ilegíveis para o juiz de visão (Camada 2). Chamar no setUpAll.
Future<void> carregaFonteInter() async {
  final data = File('assets/fonts/Inter-VariableFont.ttf').readAsBytesSync();
  final loader = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
}

/// Tamanhos canónicos da varredura (lógicos, dpr=1).
const Size kEcraPequeno = Size(320, 640);
const Size kEcraMedio = Size(390, 844);
const Size kEcraGrande = Size(430, 932);

const List<(String, Size)> kTamanhos = [
  ('pequeno', kEcraPequeno),
  ('medio', kEcraMedio),
  ('grande', kEcraGrande),
];

/// Altura simulada do teclado (viewInsets.bottom) na variante "teclado".
const double kTecladoAltura = 280;

final _chaveFoto = GlobalKey();

/// Fotografa [tela] no [tamanho] dado. Falha o teste se a tela estourar
/// (overflow) ou lançar durante o build/layout. Grava o PNG em
/// `test/golden/_fotos/<nome>_<slug>[_teclado].png`.
Future<void> fotografaTela(
  WidgetTester tester, {
  required String nome,
  required Widget tela,
  required (String, Size) tamanho,
  bool teclado = false,
}) async {
  final (slug, size) = tamanho;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = teclado
      ? const FakeViewPadding(bottom: kTecladoAltura)
      : FakeViewPadding.zero;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });

  await tester.pumpWidget(
    RepaintBoundary(
      key: _chaveFoto,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Inter'),
        home: tela,
      ),
    ),
  );
  // Assenta animações curtas de entrada sem esperar loops infinitos.
  await tester.pump(const Duration(milliseconds: 400));

  // REGRA DE OURO — qualquer FlutterError (RenderFlex overflowed incluído)
  // capturado durante o pump falha AQUI, com o nome da tela na mensagem.
  final erro = tester.takeException();
  expect(erro, isNull,
      reason: 'Tela "$nome" ($slug${teclado ? '+teclado' : ''}) '
          'lançou/estourou: $erro');

  await _gravaPng(tester,
      ficheiro: '${nome}_$slug${teclado ? '_teclado' : ''}.png');
}

Future<void> _gravaPng(WidgetTester tester, {required String ficheiro}) async {
  final boundary = _chaveFoto.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) return;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = Directory('test/golden/_fotos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$ficheiro').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
