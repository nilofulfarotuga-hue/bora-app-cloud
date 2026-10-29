import 'package:bora_app/screens/admin/admin_receitas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Painel admin da Receita do Dia — definições e pré-visualização do aviso
/// (missão final-app-2026-10-29, bloco 7 C2).
void main() {
  Widget cartao({
    bool ligada = true,
    bool aviso = true,
    bool alargado = true,
    int hora = 10,
    bool salvando = false,
    int? destinatarios = 13,
    String? titulo = 'Receita do dia',
    String? corpo =
        'Hoje: Bifanas com batata frita. Os ingredientes vão para o carrinho num toque.',
    ValueChanged<bool>? onLigada,
    ValueChanged<bool>? onAviso,
    ValueChanged<bool>? onAlargado,
    ValueChanged<int>? onHora,
    VoidCallback? onSalvar,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminReceitaAvisoCard(
              ligada: ligada,
              aviso: aviso,
              alargado: alargado,
              hora: hora,
              salvando: salvando,
              destinatarios: destinatarios,
              avisoTitulo: titulo,
              avisoCorpo: corpo,
              onLigada: onLigada ?? (_) {},
              onAviso: onAviso ?? (_) {},
              onAlargado: onAlargado ?? (_) {},
              onHora: onHora ?? (_) {},
              onSalvar: onSalvar ?? () {},
            ),
          ),
        ),
      );

  testWidgets('pré-visualiza o texto exato do servidor e quantas pessoas recebem',
      (tester) async {
    await tester.pumpWidget(cartao());
    expect(find.text('Pré-visualização do aviso de hoje'), findsOneWidget);
    expect(find.text('Receita do dia'), findsOneWidget);
    expect(
        find.text(
            'Hoje: Bifanas com batata frita. Os ingredientes vão para o carrinho num toque.'),
        findsOneWidget);
    expect(find.byKey(const Key('receita_admin_destinatarios')), findsOneWidget);
    expect(find.textContaining('Chega a 13 pessoas às 10:00'), findsOneWidget);
  });

  testWidgets('uma só pessoa fica no singular', (tester) async {
    await tester.pumpWidget(cartao(destinatarios: 1, hora: 9));
    expect(find.textContaining('Chega a 1 pessoa às 09:00'), findsOneWidget);
  });

  testWidgets('sem receita ativa diz que o aviso não sai', (tester) async {
    await tester.pumpWidget(cartao(corpo: null, titulo: null));
    expect(find.text('Não há receita ativa para hoje: o aviso não sai.'),
        findsOneWidget);
  });

  testWidgets('aviso desligado: não sai a ninguém', (tester) async {
    await tester.pumpWidget(cartao(aviso: false));
    expect(find.text('O aviso está desligado: não sai a ninguém.'), findsOneWidget);
    // Sem aviso o interruptor de alargar fica bloqueado.
    final alargar = tester.widget<SwitchListTile>(
        find.byKey(const Key('receita_admin_alargado')));
    expect(alargar.onChanged, isNull);
  });

  testWidgets('o texto do aviso explica quem recebe conforme o interruptor',
      (tester) async {
    await tester.pumpWidget(cartao(alargado: true));
    expect(find.textContaining('sequência de check-in ativa'), findsWidgets);
    await tester.pumpWidget(cartao(alargado: false));
    expect(find.text('Só chega a quem pediu o aviso no ecrã da receita (opt-in).'),
        findsOneWidget);
  });

  testWidgets('mexer nos interruptores, na hora e no Salvar chama o painel',
      (tester) async {
    bool? alargou;
    bool? avisou;
    int? hora;
    var salvou = 0;
    await tester.pumpWidget(cartao(
      onAlargado: (v) => alargou = v,
      onAviso: (v) => avisou = v,
      onHora: (v) => hora = v,
      onSalvar: () => salvou++,
    ));

    await tester.tap(find.byKey(const Key('receita_admin_alargado')));
    await tester.pump();
    expect(alargou, isFalse);

    await tester.tap(find.byKey(const Key('receita_admin_aviso')));
    await tester.pump();
    expect(avisou, isFalse);

    await tester.tap(find.byKey(const Key('receita_admin_hora')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11:00').last);
    await tester.pumpAndSettle();
    expect(hora, 11);

    await tester.tap(find.byKey(const Key('receita_admin_salvar')));
    expect(salvou, 1);
  });

  testWidgets('a guardar, o botão fica bloqueado', (tester) async {
    await tester.pumpWidget(cartao(salvando: true));
    final b = tester.widget<FilledButton>(find.byKey(const Key('receita_admin_salvar')));
    expect(b.onPressed, isNull);
    expect(find.text('Salvando…'), findsOneWidget);
  });
}
