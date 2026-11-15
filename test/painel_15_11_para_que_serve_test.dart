// Painel mais didático (15/11/2026, missão painel-admin-15-11): cada tela aberta
// pelo menu mostra em baixo "Para que serve:" com a frase do menu.
import 'dart:io';

import 'package:bora_app/widgets/admin/admin_para_que_serve.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra a frase do menu por baixo da tela', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdminTelaComProposito(
        proposito: 'Lista e estado de todos os entregadores',
        child: Scaffold(body: Text('conteudo da tela')),
      ),
    ));
    expect(find.text('conteudo da tela'), findsOneWidget);
    expect(find.text('Para que serve: Lista e estado de todos os entregadores'),
        findsOneWidget);
    expect(find.byKey(const Key('admin_para_que_serve')), findsOneWidget);
  });

  testWidgets('sem frase não acrescenta nada', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdminTelaComProposito(
        proposito: '   ',
        child: Scaffold(body: Text('conteudo da tela')),
      ),
    ));
    expect(find.byKey(const Key('admin_para_que_serve')), findsNothing);
    expect(find.text('conteudo da tela'), findsOneWidget);
  });

  testWidgets('com o teclado aberto a faixa sai e a tela fica', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
        child: AdminTelaComProposito(
          proposito: 'Lista e estado de todos os entregadores',
          child: Scaffold(body: Text('conteudo da tela')),
        ),
      ),
    ));
    expect(find.byKey(const Key('admin_para_que_serve')), findsNothing);
    expect(find.text('conteudo da tela'), findsOneWidget);
  });

  test('os dois sítios que abrem telas do menu usam a faixa', () {
    for (final caminho in [
      'lib/screens/admin/admin_menu_accordion.dart',
      'lib/screens/admin/admin_menu_sub_screen.dart',
    ]) {
      final fonte = File(caminho).readAsStringSync();
      expect(fonte, contains('AdminTelaComProposito('),
          reason: '$caminho tem de abrir as telas com a frase do menu');
      expect(RegExp(r'builder: \(_\) => (item|it)\.builder\(\)\)')
              .hasMatch(fonte),
          isFalse,
          reason: '$caminho ainda abre uma tela sem a frase');
    }
  });
}
