// ADENDO 4 — item 9: o que ficou consertado na auditoria de design.
//
//   • esqueleto de lista a pulsar em vez de um círculo a rodar
//   • texto de 16 px (ou mais) em tudo o que é NOVO no delivery do cliente
//   • verde escuro na barra do pedido (contraste do texto branco)
//   • botões e chips novos com pelo menos 44 px de altura
import 'dart:io';
import 'dart:math' as math;

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/widgets/bora/lista_estado.dart';
import 'package:bora_app/widgets/bora/skeleton_lista.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contraste(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final claro = la > lb ? la : lb;
  final escuro = la > lb ? lb : la;
  return (claro + 0.05) / (escuro + 0.05);
}

void main() {
  testWidgets('o esqueleto desenha cartões e pára com "reduzir animações"',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SkeletonLista(linhas: 4))));
    expect(find.byKey(const Key('skeleton_lista')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.pump(const Duration(milliseconds: 300));
    final o1 = t.widget<Opacity>(find.byKey(const Key('skeleton_lista'))).opacity;
    await t.pump(const Duration(milliseconds: 500));
    final o2 = t.widget<Opacity>(find.byKey(const Key('skeleton_lista'))).opacity;
    expect(o1, isNot(o2), reason: 'a pulsar');
    await t.pumpWidget(const SizedBox.shrink());

    await t.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: SkeletonLista())),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final p1 = t.widget<Opacity>(find.byKey(const Key('skeleton_lista'))).opacity;
    await t.pump(const Duration(milliseconds: 500));
    final p2 = t.widget<Opacity>(find.byKey(const Key('skeleton_lista'))).opacity;
    expect(p1, p2, reason: 'parado quando o sistema pede menos animação');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ListaACarregar (restaurantes, lojas, notificações) é esqueleto',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ListaACarregar())));
    expect(find.byType(SkeletonLista), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  test('o verde escuro da barra dá contraste AA ao texto branco; o verde da marca não',
      () {
    expect(_contraste(Colors.white, AppColors.primaryDark), greaterThan(4.5));
    expect(_contraste(Colors.white, AppColors.primary), lessThan(4.5),
        reason: 'é por isto que a barra não usa #16A34A');
  });

  test('widgets novos do cliente: nenhum texto abaixo de 16 px', () {
    const ficheiros = [
      'lib/widgets/barra_pedido_ativo.dart',
      'lib/widgets/talheres_troco_cards.dart',
      'lib/widgets/juntar_mais_tira.dart',
      'lib/widgets/filtros_rapidos_lojas.dart',
      'lib/widgets/foto_prova_entrega.dart',
      'lib/widgets/home/meus_habituais.dart',
    ];
    for (final f in ficheiros) {
      final src = File(f).readAsStringSync();
      final pequenos = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)')
          .allMatches(src)
          .map((m) => double.parse(m.group(1)!))
          .where((n) => n < 16)
          .toList();
      expect(pequenos, isEmpty, reason: '$f tem letra abaixo de 16 px: $pequenos');
    }
  });

  test('a barra do pedido usa o verde escuro do tema', () {
    final src = File('lib/widgets/barra_pedido_ativo.dart').readAsStringSync();
    expect(src, contains('color: AppColors.primaryDark'));
  });
}
