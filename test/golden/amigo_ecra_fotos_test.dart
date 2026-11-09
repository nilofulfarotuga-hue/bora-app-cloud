// O AMIGO — fotografias do ecrã do rosto e da entrada na home (m11, 09/11/2026).
// Grava PNG em test/golden/_fotos/ nos 3 tamanhos de ecrã: a saudação, a
// resposta com a deixa em cartão e "a ouvir". Falha se estourar.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/screens/client/assistant/amigo_bora_entrada.dart';
import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/amigo/amigo_rosto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fabrica_de_fotos.dart';

class _Voz extends AmigoMotorVoz {
  @override
  Future<String?> preparar(double velocidade) async => 'Voz de teste (pt-PT)';
  @override
  Future<void> falar(String texto) async {
    scheduleMicrotask(() => aoComecar?.call());
    Timer(Duration(milliseconds: 160 * texto.split(' ').length), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

class _Ouvido extends AmigoOuvido {
  @override
  Future<bool> iniciar({required void Function() aoParar}) async => true;
  @override
  Future<void> ouvir(void Function(String texto, bool fim) aoOuvir) async =>
      Timer(const Duration(milliseconds: 100), () => aoOuvir('quero um hambúrguer', false));
  @override
  Future<void> parar() async {}
}

class _Cerebro extends AmigoCerebro {
  @override
  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) async =>
      AssistantReply.fromJson({
        'texto': 'Boa noite, Ana! Sou o Amigo Bora. Se te apetecer, preparo-te o do costume do Boom.',
        'emocao': 'alegre',
      });
  @override
  Future<AssistantReply> enviar({
    required String? conversationId,
    required String mensagem,
    double? lat,
    double? lng,
    bool apartamento = false,
  }) async =>
      AssistantReply.fromJson({
        'conversation_id': 'c-1',
        'texto': 'Hoje o Boom está fechado, que pena. Mas o Fuku tem hambúrgueres e entrega em 30 minutos.',
        'emocao': 'triste',
        'deixa': {
          'id': 'd-1',
          'tipo': 'tokens',
          'texto': 'Tens 120 tokens a expirar nos próximos 7 dias: usa-os no próximo pedido.',
          'acao': {'tipo': 'abrir_carteira'},
        },
      });
  @override
  Future<(String?, List<AssistantReply>)> conversaRecente() async =>
      (null, const <AssistantReply>[]);
  @override
  Future<void> guardarConversa(String? id) async {}
  @override
  Future<void> evento(String tipo, {int? duracaoS}) async {}
}

Future<void> _correr(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _foto(WidgetTester tester, GlobalKey chave, String nome) async {
  expect(tester.takeException(), isNull, reason: '$nome estourou');
  await tester.runAsync(() async {
    final b = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('test/golden/_fotos/$nome.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AssistantFlags.reset();
  });

  for (final (slug, tamanho) in kTamanhos) {
    testWidgets('ecrã do Amigo — $slug', (tester) async {
      await tester.runAsync(() => AmigoLogoBora.carregar());
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chave = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: chave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: AmigoScreen(cerebro: _Cerebro(), voz: AmigoVoz(motor: _Voz()), ouvido: _Ouvido()),
        ),
      ));
      await _correr(tester, 1200);
      await _foto(tester, chave, 'amigo_ecra_saudacao_$slug');
      await _correr(tester, 3000);

      await tester.tap(find.byKey(const Key('amigo-escrever')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('amigo-caixa-texto')), 'quero um hambúrguer');
      await tester.tap(find.byKey(const Key('amigo-enviar')));
      await _correr(tester, 1500);
      await _foto(tester, chave, 'amigo_ecra_resposta_$slug');
      await _correr(tester, 4000);
      await _foto(tester, chave, 'amigo_ecra_deixa_$slug');

      await tester.tap(find.byKey(const Key('amigo-microfone')));
      await _correr(tester, 400);
      await _foto(tester, chave, 'amigo_ecra_a_ouvir_$slug');

      await tester.pumpWidget(const SizedBox());
      await _correr(tester, 500);
    });
  }

  testWidgets('home: entrada do rosto e mosaico', (tester) async {
    tester.view.physicalSize = kEcraMedio;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chave = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: chave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const AmigoBoraEntrada(),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.88,
                children: [
                  AmigoMosaico(onTap: () {}),
                  for (final a in ['restaurantes', 'supermercados', 'farmacia'])
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/categories/cat_$a.png', fit: BoxFit.cover),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/categories/cat_restaurantes.png'),
        chave.currentContext!));
    await _correr(tester, 600);
    await _foto(tester, chave, 'amigo_home_entrada_mosaico');
  });
}
