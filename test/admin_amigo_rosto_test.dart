// Painel admin — secção "Rosto do Amigo" (missão m11-amigo-rosto, 09/11/2026).
import 'dart:async';

import 'package:bora_app/screens/admin/admin_amigo_rosto_secao.dart';
import 'package:bora_app/services/amigo_voz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Voz extends AmigoMotorVoz {
  final ditas = <String>[];
  @override
  Future<String?> preparar(double velocidade) async => 'Voz de teste (pt-PT)';
  @override
  Future<void> falar(String texto) async {
    ditas.add(texto);
    scheduleMicrotask(() => aoComecar?.call());
    Timer(const Duration(milliseconds: 500), () => aoAcabar?.call());
  }

  @override
  Future<void> parar() async {}
}

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: filho)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pré-visualização, expressões, voz, variante, interruptores e números', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <String, Object>{};
    final motor = _Voz();
    await tester.pumpWidget(_app(AdminAmigoRostoSecao(
      voz: AmigoVoz(motor: motor),
      carregar: (dias) async => {
        'aberturas': 12,
        'clientes': 7,
        'mensagens_voz': 9,
        'mensagens_escrita': 3,
        'pct_voz': 75,
        'tempo_medio_s': 84,
        'tempo_total_min': 16.8,
        'por_plataforma': [
          {'plataforma': 'android', 'n': 8},
          {'plataforma': 'web', 'n': 4},
        ],
        'interruptores': {
          'amigo_rosto_ativo': true,
          'amigo_rosto_variante': 'rosto_camisa',
          'amigo_voz_ligada_por_defeito': true,
          'amigo_voz_velocidade': 1.0,
          'amigo_mosaico_categorias': true,
        },
      },
      gravar: (k, v) async => gravados[k] = v,
    )));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('12'), findsOneWidget);
    expect(find.text('75% voz'), findsOneWidget);
    expect(find.text('84 s'), findsOneWidget);
    expect(find.text('android: 8 · web: 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-amigo-emocao-triste')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Amigo, triste'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-amigo-ouvir')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(motor.ditas.single, contains('Amigo'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Só o rosto'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(gravados['amigo_rosto_variante'], 'rosto');

    await tester.tap(find.text('Rosto ligado (amigo_rosto_ativo)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(gravados['amigo_rosto_ativo'], false);

    await tester.tap(find.text('Mosaico "Amigo" nas categorias (amigo_mosaico_categorias)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(gravados['amigo_mosaico_categorias'], false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('sem a migração no servidor: avisa e não deixa gravar, mas mostra o rosto',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <String, Object>{};
    await tester.pumpWidget(_app(AdminAmigoRostoSecao(
      voz: AmigoVoz(motor: _Voz()),
      carregar: (_) async => throw Exception('function admin_amigo_rosto_overview does not exist'),
      gravar: (k, v) async => gravados[k] = v,
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('20261109060000_amigo_rosto por aplicar'), findsOneWidget);
    expect(find.byKey(const Key('admin-amigo-previa')), findsOneWidget);
    await tester.tap(find.text('Rosto ligado (amigo_rosto_ativo)'));
    await tester.pump();
    expect(gravados, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
