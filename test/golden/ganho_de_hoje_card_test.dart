import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/widgets/ganho_de_hoje_card.dart';

import 'fabrica_de_fotos.dart';

/// O cartão "Ganhos de hoje" que os quatro ecrãs de casa partilham.
///
/// A cicatriz: a 2026-09-05 o Danilo estava na rua e o cartão do ecrã do
/// motorista dizia €4,00 num dia que tinha €9,32 — só contava a corrida de
/// passageiros das 12:14 e deixava de fora a entrega das 14:22. Este teste
/// fixa o número que o cartão mostra, para o total do dia não voltar a
/// encolher sem ninguém dar por isso.
void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  testWidgets('mostra o total do dia inteiro, não só uma das partes',
      (tester) async {
    await fotografaTela(
      tester,
      nome: 'ganho_de_hoje_dia_completo',
      tamanho: ('telemovel', const Size(390, 844)),
      tela: const Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: GanhoDeHojeCard(valorInicialCents: 932),
          ),
        ),
      ),
    );

    expect(find.text('Ganhos de hoje'), findsOneWidget);
    // Em euros e com vírgula, como em Portugal.
    expect(find.text('€9,32'), findsOneWidget);
    // O erro que levou a isto: mostrar só a parte das corridas.
    expect(find.text('€4,00'), findsNothing);
  });

  testWidgets('sem valor ainda lido mostra traço, nunca zero', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GanhoDeHojeCard()),
    ));
    await tester.pump();

    // Zero seria uma mentira sobre o dia de quem trabalhou.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('€0,00'), findsNothing);
  });
}
