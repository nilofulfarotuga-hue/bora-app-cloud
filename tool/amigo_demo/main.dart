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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_medir);
  final voz = AmigoVoz();
  unawaited(voz.preparar().then((_) => debugPrint('[AmigoDemo] voz=${voz.nomeVoz ?? 'nenhuma (só legenda)'} '
      'plataforma=${kIsWeb ? 'web' : defaultTargetPlatform.name}')));
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: Builder(
      builder: (context) => AmigoScreen(
        cerebro: _CerebroDemo(),
        voz: voz,
        aoVerConversa: () => ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Na app abre a conversa escrita.'))),
      ),
    ),
  ));
}
