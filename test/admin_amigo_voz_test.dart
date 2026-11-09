// Painel admin — secção "Voz do servidor" do Amigo (pendências 09/11/2026, bloco I).
import 'dart:typed_data';

import 'package:bora_app/screens/admin/admin_amigo_voz_secao.dart';
import 'package:bora_app/services/amigo_voz_servidor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tocador extends AmigoTocador {
  final tocados = <AmigoAudio>[];
  @override
  Future<void> tocar(
    AmigoAudio audio, {
    required void Function(double? duracaoMs) aoComecar,
    required void Function() aoAcabar,
    required void Function(String motivo) aoErro,
  }) async {
    tocados.add(audio);
    aoComecar(1000);
  }

  @override
  Future<void> parar() async {}
}

Map<String, dynamic> _overview({bool ativo = false}) => {
      'hoje': {
        'pedidos': 14,
        'caracteres_pedidos': 2100,
        'pedidos_cache': 6,
        'caracteres_cache': 600,
        'pedidos_gerados': 7,
        'caracteres_gerados': 1500,
        'pedidos_recusados': 1,
        'caracteres_recusados': 0,
        'erros': 0,
      },
      'mes': {
        'caracteres_gerados': 1600,
        'caracteres_cache': 800,
      },
      'gratis_mes': 4000000,
      'pct_gratis_mes': 0.04,
      'pct_teto_hoje': 7.5,
      'clientes_hoje': 3,
      'definicoes': {
        'amigo_voz_servidor_ativo': ativo,
        'amigo_voz_teto_dia': 20000,
        'amigo_voz_teto_utilizador_dia': 3000,
        'amigo_voz_nome': 'pt-PT-Standard-E',
      },
    };

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: filho)),
    );

void main() {
  testWidgets('consumo do dia e do mês, % do grátis, interruptor, teto, limite e voz', (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <Map<String, Object>>[];
    await tester.pumpWidget(_app(AdminAmigoVozSecao(
      carregar: (dias) async => _overview(),
      definir: (m) async => gravados.add(m),
      testar: (f) async => const AmigoAudioResposta.semVoz('sem_chave', definitivo: true),
      tocador: _Tocador(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('1.500 car.'), findsOneWidget, reason: 'gerados hoje');
    expect(find.textContaining('7.5% do teto de 20.000'), findsOneWidget);
    expect(find.text('600 car.'), findsOneWidget, reason: 'da cache hoje');
    expect(find.text('1.600 car.'), findsOneWidget, reason: 'gerados no mês');
    expect(find.textContaining('0.04% do grátis de 4.000.000'), findsOneWidget);
    expect(find.byKey(const Key('admin-amigo-voz-sem-migracao')), findsNothing);

    // interruptor
    await tester.tap(find.byKey(const Key('admin-amigo-voz-ativo')));
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_ativo': true});

    // teto: número fora do limite não grava; dentro grava
    await tester.enterText(find.byKey(const Key('admin-amigo-voz-teto')), '999999');
    await tester.tap(find.byKey(const Key('admin-amigo-voz-teto-salvar')));
    await tester.pumpAndSettle();
    expect(gravados, hasLength(1));
    expect(find.textContaining('entre 0 e 133.000'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('admin-amigo-voz-teto')), '25000');
    await tester.tap(find.byKey(const Key('admin-amigo-voz-teto-salvar')));
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_teto_dia': 25000});

    await tester.enterText(find.byKey(const Key('admin-amigo-voz-teto-cliente')), '2000');
    await tester.tap(find.byKey(const Key('admin-amigo-voz-teto-cliente-salvar')));
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_teto_utilizador_dia': 2000});

    // voz (só pt-PT na lista)
    await tester.tap(find.byKey(const Key('admin-amigo-voz-nome')));
    await tester.pumpAndSettle();
    expect(find.textContaining('pt-BR'), findsNothing);
    await tester.tap(find.textContaining('WaveNet E').last);
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_voz': 'pt-PT-Wavenet-E'});

    // testar sem chave: explica o motivo
    await tester.tap(find.byKey(const Key('admin-amigo-voz-testar')));
    await tester.pumpAndSettle();
    expect(find.textContaining('GOOGLE_TTS_API_KEY'), findsWidgets);
    expect(find.byKey(const Key('admin-amigo-voz-resultado')), findsOneWidget);
  });

  testWidgets('testar com a voz ligada: toca o áudio que veio do servidor', (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tocador = _Tocador();
    await tester.pumpWidget(_app(AdminAmigoVozSecao(
      carregar: (dias) async => _overview(ativo: true),
      definir: (m) async {},
      testar: (f) async => AmigoAudioResposta.audio(
          AmigoAudio(bytes: Uint8List(2048), base64: 'AAAA', origem: 'google')),
      tocador: tocador,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-amigo-voz-testar')));
    await tester.pumpAndSettle();
    expect(tocador.tocados, hasLength(1));
    expect(find.textContaining('gerado na Google, 2.0 KB'), findsOneWidget);
  });

  testWidgets('migração por aplicar: aviso e nada se grava', (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <Map<String, Object>>[];
    await tester.pumpWidget(_app(AdminAmigoVozSecao(
      carregar: (dias) async => throw Exception('function admin_amigo_voz_overview does not exist'),
      definir: (m) async => gravados.add(m),
      tocador: _Tocador(),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-amigo-voz-sem-migracao')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-amigo-voz-ativo')));
    await tester.pumpAndSettle();
    expect(gravados, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('motivos explicados em PT-BR', () {
    expect(adminAmigoVozMotivo('teto'), contains('teto'));
    expect(adminAmigoVozMotivo('erro_base'), contains('migração'));
    expect(adminAmigoVozMotivo(null), contains('sem ligação'));
  });
}
