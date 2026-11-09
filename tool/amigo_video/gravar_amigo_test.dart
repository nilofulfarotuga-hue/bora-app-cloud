// O AMIGO — gravador do vídeo de prova (missão m11-amigo-rosto, 09/11/2026).
//
// NÃO faz parte da suíte (está fora de test/). Corre-se à mão:
//   flutter test tool/amigo_video/gravar_amigo_test.dart
// com AMIGO_VOZ_CACHE = pasta voz/cache do protótipo do Dipsy (MP3 da voz
// Raquel + tempo de cada palavra) e AMIGO_VIDEO_OUT = pasta das imagens.
//
// Grava o ECRÃ VERDADEIRO do Amigo (AmigoScreen, AmigoRosto, legenda,
// cartões) imagem a imagem, a 25 por segundo, com relógio exato: a boca é
// acertada pelos tempos reais de cada palavra do áudio, como o motor de voz
// faz no telemóvel. O "servidor" e o microfone são um guião com dados de
// demonstração (a Casa do Burger e o Rui não existem). Depois o ffmpeg junta
// as imagens e o som (ver docs/amigo/provas/LEIA-video.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/amigo/amigo_rosto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/golden/fabrica_de_fotos.dart';

const _quadroMs = 40; // 25 imagens por segundo

class _Frase {
  _Frase(this.texto, this.audio, this.palavras);
  final String texto;
  final String audio;
  final List<Map<String, dynamic>> palavras;
  double get fim {
    final u = palavras.last;
    return (u['t'] as num).toDouble() + (u['d'] as num).toDouble();
  }
}

double relogio = 0;
final faixas = <Map<String, Object>>[];

/// Voz do guião: diz frases do protótipo (voz Raquel), com os eventos de
/// palavra nos tempos certos.
class _VozGuiao extends AmigoMotorVoz {
  _VozGuiao(this.frases);
  final Map<String, _Frase> frases;
  final List<Timer> _t = [];

  @override
  Future<String?> preparar(double velocidade) async => 'Microsoft Raquel (Natural) pt-PT';

  @override
  Future<void> falar(String texto) async {
    var resto = texto.trim();
    var cursor = 0;
    var base = 0.0;
    scheduleMicrotask(() => aoComecar?.call());
    while (resto.isNotEmpty) {
      final f = frases.values.where((x) => resto.startsWith(x.texto)).fold<_Frase?>(
          null, (m, x) => m == null || x.texto.length > m.texto.length ? x : m);
      if (f == null) throw StateError('frase sem áudio: "$resto"');
      faixas.add({'audio': f.audio, 't0': relogio + base});
      for (final p in f.palavras) {
        final w = p['w'] as String;
        final i = texto.indexOf(w, cursor);
        if (i >= 0) cursor = i + w.length;
        final letra = i >= 0 ? i : cursor;
        _t.add(Timer(Duration(milliseconds: (base + (p['t'] as num)).round()),
            () => aoPalavra?.call(letra)));
      }
      base += f.fim + 300;
      resto = resto.substring(f.texto.length).trim();
    }
    _t.add(Timer(Duration(milliseconds: base.round()), () => aoAcabar?.call()));
  }

  @override
  Future<void> parar() async {
    for (final t in _t) {
      t.cancel();
    }
    _t.clear();
  }
}

class _OuvidoGuiao extends AmigoOuvido {
  final fila = <String>[];
  @override
  Future<bool> iniciar({required void Function() aoParar}) async => true;
  @override
  Future<void> ouvir(void Function(String texto, bool fim) aoOuvir) async {
    final frase = fila.removeAt(0);
    final palavras = frase.split(' ');
    for (var i = 1; i <= palavras.length; i++) {
      final parcial = palavras.take(i).join(' ');
      Timer(Duration(milliseconds: 280 * i), () => aoOuvir(parcial, i == palavras.length));
    }
  }

  @override
  Future<void> parar() async {}
}

class _CerebroGuiao extends AmigoCerebro {
  final respostas = <Map<String, dynamic>>[];
  @override
  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) async =>
      AssistantReply.fromJson({
        'texto': 'Olá, eu sou o Amigo! Vivo dentro do Bora e ajudo-te a pedir comida, compras e muito mais.',
        'emocao': 'alegre',
      });
  @override
  Future<AssistantReply> enviar({
    required String? conversationId,
    required String mensagem,
    double? lat,
    double? lng,
    bool apartamento = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    return AssistantReply.fromJson(respostas.removeAt(0));
  }

  @override
  Future<(String?, List<AssistantReply>)> conversaRecente() async =>
      (null, const <AssistantReply>[]);
  @override
  Future<void> guardarConversa(String? id) async {}
  @override
  Future<void> evento(String tipo, {int? duracaoS}) async {}
}

void main() {
  final cache = Platform.environment['AMIGO_VOZ_CACHE'] ??
      r'C:\Users\danil\Desktop\bora-amigo-teste\voz\cache';
  final saida = Directory(Platform.environment['AMIGO_VIDEO_OUT'] ?? 'build/amigo_video');

  testWidgets('grava o vídeo do Amigo (3 cenas)', (tester) async {
    await carregaFonteInter();
    await carregaFontesSdk();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AmigoLogoBora.carregar());
    final frases = <String, _Frase>{};
    for (final f in Directory(cache).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      if (j['voz'] != 'raquel') continue;
      final mp3 = f.path.replaceAll('.json', '.mp3');
      frases[j['texto'] as String] = _Frase(j['texto'] as String, mp3,
          (j['palavras'] as List).cast<Map<String, dynamic>>());
    }
    if (saida.existsSync()) saida.deleteSync(recursive: true);
    saida.createSync(recursive: true);

    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    final cerebro = _CerebroGuiao();
    final ouvido = _OuvidoGuiao();
    final voz = AmigoVoz(motor: _VozGuiao(frases), relogio: () => relogio);
    final cena = ValueNotifier<String>('Cena 1 · "Olá, eu sou o Amigo"');
    final chave = GlobalKey();
    var n = 0;

    Future<void> quadro() async {
      relogio += _quadroMs;
      await tester.pump(const Duration(milliseconds: _quadroMs));
      await tester.runAsync(() async {
        final b = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${saida.path}/q_${(n++).toString().padLeft(5, '0')}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> correr(int ms) async {
      for (var t = 0; t < ms; t += _quadroMs) {
        await quadro();
      }
    }

    Future<void> ateCalar({int depois = 900}) async {
      // primeiro espera que comece a falar (o servidor pensa ~1,4 s), depois
      // que acabe — senão o guião tocava no microfone a meio da resposta
      var guarda = 0;
      while (voz.estado.value != AmigoVozEstado.aFalar && guarda++ < 250) {
        await quadro();
      }
      guarda = 0;
      while (voz.estado.value == AmigoVozEstado.aFalar && guarda++ < 800) {
        await quadro();
      }
      await correr(depois);
    }

    Future<void> clienteDiz(String frase, Map<String, dynamic> resposta) async {
      ouvido.fila.add(frase);
      cerebro.respostas.add(resposta);
      await tester.tap(find.byKey(const Key('amigo-microfone')));
      await ateCalar();
    }

    await tester.pumpWidget(RepaintBoundary(
      key: chave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Stack(children: [
          AmigoScreen(cerebro: cerebro, voz: voz, ouvido: ouvido),
          Positioned(
            left: 0,
            right: 0,
            top: 62,
            child: IgnorePointer(
              child: Center(
                child: ValueListenableBuilder<String>(
                  valueListenable: cena,
                  builder: (_, c, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xCC14532D),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$c · demonstração',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    ));

    // Cena 1 — acorda e apresenta-se
    await ateCalar(depois: 700);

    // Cena 2 — o hambúrguer
    cena.value = 'Cena 2 · o hambúrguer';
    await correr(400);
    await clienteDiz('Quero um hambúrguer.', {
      'conversation_id': 'demo',
      'texto': 'Encontrei! O Hambúrguer Clássico da Casa do Burger, com batatas, por oito euros e noventa. '
          'Chega em cerca de vinte e cinco minutos.',
      'emocao': 'alegre',
      'propostas': [
        {
          'proposal_id': 'demo-1',
          'restaurant_name': 'Casa do Burger (demonstração)',
          'is_partner': true,
          'service_type': 'restaurant',
          'items': [
            {'product_id': 'p1', 'name': 'Hambúrguer Clássico com batatas', 'quantity': 1,
             'unit_price': 8.9, 'line_total': 8.9, 'confidence': 'alta'},
          ],
          'subtotal': 8.9,
          'delivery_fee': 2.5,
          'customer_total': 11.4,
        },
      ],
    });
    await clienteDiz('Pode ser, mas sem cebola.', {
      'conversation_id': 'demo',
      'texto': 'Feito, sem cebola. Eu só preparo o carrinho: o pagamento és tu que confirmas.',
      'emocao': 'a_falar',
    });
    await clienteDiz('Confirma.', {
      'conversation_id': 'demo',
      'texto': 'Carrinho pronto! Agora é só carregares em pagar. Bom apetite!',
      'emocao': 'alegre',
    });

    // Cena 3 — triste e confuso
    cena.value = 'Cena 3 · triste e confuso';
    await clienteDiz('E se o pedido se atrasar?', {
      'conversation_id': 'demo',
      'texto': 'Se um pedido se atrasa, fico um bocadinho triste.',
      'emocao': 'triste',
    });
    await clienteDiz('Blim blom blá.', {
      'conversation_id': 'demo',
      'texto': 'E quando não percebo, digo-te logo.',
      'emocao': 'confuso',
    });
    await correr(600);

    File('${saida.path}/faixas.json').writeAsStringSync(jsonEncode({
      'quadros': n,
      'quadro_ms': _quadroMs,
      'faixas': faixas,
    }));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
