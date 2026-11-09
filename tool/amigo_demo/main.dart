// O AMIGO — demonstração para provas no aparelho (missão m11-amigo-rosto, 09/11/2026).
//
// Não entra na app: corre-se à parte, sem servidor e sem contas,
//   flutter run --profile -t tool/amigo_demo/main.dart        (Android/iPhone)
//   flutter run -d chrome -t tool/amigo_demo/main.dart        (navegador)
// para provar no aparelho o que não depende do servidor: o rosto a 60
// imagens/s, a voz pt-PT DO PRÓPRIO APARELHO (flutter_tts) e a boca
// acertada pelos eventos de palavra. O "cérebro" é um guião com dados de
// demonstração. Escreve no registo (logcat / consola):
//   [AmigoDemo] voz=...            a voz pt-PT escolhida (ou "nenhuma")
//   [AmigoVoz] palavra@N desvio X  o atraso da boca em cada palavra
//   [AmigoDemo] desempenho {...}   imagens/s e tempos de cada imagem
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/screens/client/assistant/amigo_screen.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:bora_app/services/amigo_voz_servidor.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class _CerebroDemo extends AmigoCerebro {
  var _n = 0;

  @override
  Future<AssistantReply?> abrir({double? lat, double? lng, bool apartamento = false}) async =>
      AssistantReply.fromJson({
        'texto': 'Olá, eu sou o Amigo! Estou aqui para o que precisares: comida, mercado, Favores e muito mais.',
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
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final m = mensagem.toLowerCase();
    _n++;
    final deixa = {
      'id': 'demo-$_n',
      'tipo': _n.isOdd ? 'promocao' : 'parceiro_novo',
      'texto': _n.isOdd
          ? 'Já viste? Hoje há uma promoção no teu restaurante preferido.'
          : 'Novidade na Bora: chegou um parceiro novo à Guarda. Queres espreitar?',
      'acao': {'tipo': 'abrir_checkin'},
    };
    if (m.contains('hamb')) {
      return AssistantReply.fromJson({
        'texto': 'Encontrei! O hambúrguer clássico com batatas chega em cerca de vinte e cinco minutos.',
        'emocao': 'alegre',
        'propostas': [
          {
            'proposal_id': 'demo',
            'restaurant_name': 'Casa do Burger (demonstração)',
            'service_type': 'restaurant',
            'items': [
              {'product_id': 'p', 'name': 'Hambúrguer clássico com batatas', 'quantity': 1,
               'unit_price': 8.9, 'line_total': 8.9, 'confidence': 'alta'},
            ],
            'subtotal': 8.9,
            'delivery_fee': 2.5,
            'customer_total': 11.4,
          },
        ],
      });
    }
    if (m.contains('atras') || m.contains('fechad')) {
      return AssistantReply.fromJson({
        'texto': 'Se um pedido se atrasa, fico um bocadinho triste. Mas aviso-te logo.',
        'emocao': 'triste',
      });
    }
    if (m.length < 4) {
      return AssistantReply.fromJson({'texto': 'Hum, não percebi. Dizes outra vez?', 'emocao': 'confuso'});
    }
    return AssistantReply.fromJson({
      'texto': 'Está um dia bonito na Guarda. Queres que te sugira um jantar?',
      'emocao': 'a_falar',
      'deixa': deixa,
    });
  }

  @override
  Future<(String?, List<AssistantReply>)> conversaRecente() async =>
      (null, const <AssistantReply>[]);
  @override
  Future<void> guardarConversa(String? id) async {}
  @override
  Future<void> evento(String tipo, {int? duracaoS}) async => debugPrint('[AmigoDemo] evento $tipo');
}

final _tempos = <FrameTiming>[];
DateTime? _inicio;

void _medir(List<FrameTiming> t) {
  _inicio ??= DateTime.now();
  _tempos.addAll(t);
  if (DateTime.now().difference(_inicio!).inSeconds >= 20 && _tempos.length > 60) {
    final total = _tempos.map((f) => f.totalSpan.inMicroseconds / 1000).toList()..sort();
    final build = _tempos.map((f) => f.buildDuration.inMicroseconds / 1000).toList()..sort();
    final raster = _tempos.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()..sort();
    double p(List<double> l, double q) => l[math.min(l.length - 1, (l.length * q).floor())];
    final segundos = DateTime.now().difference(_inicio!).inMilliseconds / 1000;
    debugPrint('[AmigoDemo] desempenho ${jsonEncode({
      'segundos': segundos,
      'imagens': _tempos.length,
      'imagens_por_segundo': (_tempos.length / segundos).toStringAsFixed(1),
      'imagem_ms_mediana': p(total, .5).toStringAsFixed(1),
      'imagem_ms_p95': p(total, .95).toStringAsFixed(1),
      'build_ms_p95': p(build, .95).toStringAsFixed(2),
      'raster_ms_p95': p(raster, .95).toStringAsFixed(2),
      'imagens_lentas_mais_16ms': total.where((x) => x > 16.7).length,
    })}');
    _tempos.clear();
    _inicio = DateTime.now();
  }
}

/// As 5 frases da prova da boca (as mesmas do B4 do Dipsy).
const _cincoFrases = [
  'Olá, eu sou o Amigo.',
  'O teu hambúrguer chega em vinte e cinco minutos.',
  'Uau, isso é mesmo uma boa notícia!',
  'Eu nunca mexo no teu dinheiro sem tu mandares.',
  'Diz-me o código de quatro números que aparece no pedido.',
];

Map<String, Object> _resumo(List<double> l) {
  if (l.isEmpty) return {'n': 0};
  final s = [...l]..sort();
  final media = s.reduce((a, b) => a + b) / s.length;
  return {
    'n': s.length,
    'media_ms': media.toStringAsFixed(1),
    'p95_ms': s[math.min(s.length - 1, (s.length * .95).floor())].toStringAsFixed(1),
    'max_ms': s.last.toStringAsFixed(1),
  };
}

/// Prova da boca: diz as 5 frases seguidas e escreve os números no registo.
Future<void> _provaCincoFrases(AmigoVoz voz) async {
  while (voz.estado.value != AmigoVozEstado.calado) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  final antes = voz.atrasosEventoBoca.length;
  for (final f in _cincoFrases) {
    final e0 = voz.eventosDePalavra;
    final d0 = voz.desvios.length;
    final a0 = voz.atrasosEventoBoca.length;
    final t0 = DateTime.now();
    await voz.falar(f);
    debugPrint('[AmigoDemo] frase ${jsonEncode({
      'frase': f,
      'duracao_ms': DateTime.now().difference(t0).inMilliseconds,
      'eventos_de_palavra': voz.eventosDePalavra - e0,
      'atraso_evento_boca': _resumo(voz.atrasosEventoBoca.sublist(a0)),
      'desvio_estimativa': _resumo(voz.desvios.sublist(d0).map((x) => x.abs()).toList()),
    })}');
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  debugPrint('[AmigoDemo] boca-resumo ${jsonEncode({
    'voz': voz.nomeVoz ?? 'nenhuma (só legenda)',
    'eventos_de_palavra': voz.eventosDePalavra,
    'atraso_evento_boca': _resumo(voz.atrasosEventoBoca.sublist(antes)),
    'desvio_estimativa': _resumo(voz.desvios.map((x) => x.abs()).toList()),
  })}');
}

/// Pendências 09/11 (bloco I): a Edge amigo-voz FALSA para a prova no WebKit
/// (`?voz_servidor=falso`). Devolve um tom em WAV com a duração da frase; na
/// app é a Edge a sério (MP3 da Google, pt-PT).
class _ServidorDemo implements AmigoVozServidorCliente {
  int pedidos = 0;

  @override
  Future<AmigoAudioResposta> pedir(String texto, {double velocidade = 1}) async {
    pedidos++;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ms = (texto.length * 65).clamp(800, 8000);
    final n = 8000 * ms ~/ 1000; // 8 kHz, 8 bits, mono
    final b = ByteData(44 + n);
    void txt(int o, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    txt(0, 'RIFF');
    b.setUint32(4, 36 + n, Endian.little);
    txt(8, 'WAVE');
    txt(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, 8000, Endian.little);
    b.setUint32(28, 8000, Endian.little);
    b.setUint16(32, 1, Endian.little);
    b.setUint16(34, 8, Endian.little);
    txt(36, 'data');
    b.setUint32(40, n, Endian.little);
    for (var i = 0; i < n; i++) {
      b.setUint8(44 + i, (128 + 20 * math.sin(2 * math.pi * 220 * i / 8000)).round());
    }
    final bytes = b.buffer.asUint8List();
    debugPrint('[AmigoDemo] servidor falso: pedido $pedidos (${texto.length} caracteres, $ms ms)');
    return AmigoAudioResposta.audio(
        AmigoAudio(bytes: bytes, base64: base64Encode(bytes), origem: 'demo', mime: 'audio/wav'));
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_medir);
  final servidorFalso = Uri.base.queryParameters['voz_servidor'] == 'falso';
  final voz = servidorFalso
      ? AmigoVoz(
          motor: AmigoMotorVozComServidor(
            servidor: _ServidorDemo(),
            servidorLigado: () async => true,
          ),
        )
      : AmigoVoz();
  unawaited(voz.preparar().then((_) => debugPrint('[AmigoDemo] voz=${voz.nomeVoz ?? 'nenhuma (só legenda)'} '
      'plataforma=${kIsWeb ? 'web' : defaultTargetPlatform.name}')));
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    // Os navegadores só deixam falar depois de um toque: o botão "Começar"
    // abre o ecrã do Amigo e, depois da saudação, corre a prova das 5 frases.
    home: Builder(
      builder: (context) => Scaffold(
        backgroundColor: const Color(0xFFF0FDF4),
        body: Center(
          child: FilledButton(
            key: const Key('amigo-demo-comecar'),
            style: FilledButton.styleFrom(minimumSize: const Size(260, 72)),
            onPressed: () {
              unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (ctx) => AmigoScreen(
                  cerebro: _CerebroDemo(),
                  voz: voz,
                  aoVerConversa: () => ScaffoldMessenger.of(ctx)
                      .showSnackBar(const SnackBar(content: Text('Na app abre a conversa escrita.'))),
                ),
              )));
              unawaited(Future<void>.delayed(const Duration(seconds: 2), () => _provaCincoFrases(voz)));
            },
            child: const Text('Começar a prova do Amigo', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    ),
  ));
}
