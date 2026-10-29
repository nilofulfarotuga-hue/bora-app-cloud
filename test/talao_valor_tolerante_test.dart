// Missão geral 28/10/2026, Bloco A — folha do talão ("Quanto pagaste na
// caixa?"). Caso real: o campo tinha "7. 88", o double.tryParse falhava e o
// aviso ia por SnackBar para o ecrã de TRÁS, escondido pela própria folha:
// o Confirmar parecia não fazer nada.
//
// Aqui: "7. 88" fecha a folha e devolve 788 cêntimos; um valor inválido e um
// erro da câmara aparecem DENTRO da folha (nunca num SnackBar escondido).
import 'dart:convert';
import 'dart:io' as io;

import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _canalCamara = MethodChannel('plugins.flutter.io/image_picker');

// PNG 1×1 — a "foto do talão" do teste (sem câmara nem rede).
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _Resultado {
  bool fechou = false;
  Object? valor;
}

Widget _app(_Resultado r) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final v = await showModalBottomSheet<Object?>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const ReceiptCaptureSheet(isCash: false),
                );
                r
                  ..fechou = true
                  ..valor = v;
              },
              child: const Text('abrir folha'),
            ),
          ),
        ),
      ),
    );

Finder _naFolha(Finder f) =>
    find.descendant(of: find.byType(ReceiptCaptureSheet), matching: f);

Future<void> _abrirETirarFoto(WidgetTester tester, _Resultado r) async {
  await tester.pumpWidget(_app(r));
  await tester.tap(find.text('abrir folha'));
  await tester.pumpAndSettle();
  expect(find.byType(ReceiptCaptureSheet), findsOneWidget);
  await tester.tap(_naFolha(find.text('Foto do talão (ou da conta / do saco)')));
  await tester.pumpAndSettle();
}

void main() {
  late String caminhoFoto;

  setUpAll(() {
    final f = io.File(
        '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}talao_teste_28_10.png')
      ..writeAsBytesSync(_png);
    caminhoFoto = f.path;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalCamara, null);
  });

  void camaraDevolveFoto() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalCamara, (call) async {
      if (call.method == 'pickImage') return caminhoFoto;
      return null;
    });
  }

  testWidgets('"7. 88" + Confirmar fecha a folha e devolve 788 cêntimos',
      (tester) async {
    camaraDevolveFoto();
    final r = _Resultado();
    await _abrirETirarFoto(tester, r);

    await tester.enterText(find.byKey(const Key('fld_valor_talao')), '7. 88');
    await tester.pump();
    // O espaço que o teclado meteu sai logo do campo.
    expect(_naFolha(find.text('7.88')), findsOneWidget);

    await tester.tap(_naFolha(find.text('Confirmar')));
    await tester.pumpAndSettle();

    expect(r.fechou, isTrue);
    expect(find.byType(ReceiptCaptureSheet), findsNothing);
    final (_, centimos) = r.valor! as (Object, int);
    expect(centimos, 788);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('valor inválido ("0"): o erro aparece DENTRO da folha',
      (tester) async {
    camaraDevolveFoto();
    final r = _Resultado();
    await _abrirETirarFoto(tester, r);

    await tester.enterText(find.byKey(const Key('fld_valor_talao')), '0');
    await tester.pump();
    await tester.tap(_naFolha(find.text('Confirmar')));
    await tester.pumpAndSettle();

    expect(r.fechou, isFalse);
    expect(find.byType(ReceiptCaptureSheet), findsOneWidget);
    expect(
        _naFolha(
            find.text('Valor inválido. Escreve só o valor, por exemplo 7,88.')),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Corrigir o valor apaga o aviso e deixa seguir.
    await tester.enterText(find.byKey(const Key('fld_valor_talao')), '7,8');
    await tester.pump();
    expect(
        find.text('Valor inválido. Escreve só o valor, por exemplo 7,88.'),
        findsNothing);
    await tester.tap(_naFolha(find.text('Confirmar')));
    await tester.pumpAndSettle();
    expect(r.fechou, isTrue);
    final (_, centimos) = r.valor! as (Object, int);
    expect(centimos, 780);
  });

  testWidgets('letras ("abc") não entram no campo: Confirmar fica desligado',
      (tester) async {
    camaraDevolveFoto();
    final r = _Resultado();
    await _abrirETirarFoto(tester, r);

    await tester.enterText(find.byKey(const Key('fld_valor_talao')), 'abc');
    await tester.pump();
    final campo =
        tester.widget<TextField>(find.byKey(const Key('fld_valor_talao')));
    expect(campo.controller!.text, '');
    expect(_naFolha(find.text('Escreve o valor que pagaste de facto')),
        findsOneWidget);
  });

  testWidgets('câmara falha: o aviso aparece DENTRO da folha', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalCamara, (call) async {
      throw PlatformException(code: 'camera_access_denied');
    });
    final r = _Resultado();
    await _abrirETirarFoto(tester, r);

    expect(
        _naFolha(find.text('Não foi possível usar a câmara — tenta outra vez.')),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
