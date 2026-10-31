// Peso variável (31/10/2026) — prova VISUAL da folha "Quanto custou na
// etiqueta da balança?" que o estafeta abre ao tocar no preço de um produto
// ao quilo na lista de compras. Três larguras, com o teclado aberto (é como o
// estafeta a vê na loja) e no estado de recusa do servidor (fora do limite).
// O harness falha sozinho em qualquer estouro; os PNG ficam em _fotos/.
import 'dart:io';

import 'package:bora_app/services/peso_variavel_estafeta_service.dart';
import 'package:bora_app/widgets/peso_variavel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

class _Folha extends StatelessWidget {
  const _Folha();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: PesoVariavelSheet(
            nomeLinha: 'Melancia Poucas Sementes Continente × 1',
            estimadoCaixaCents: 714,
            enviar: (_) async => PesoVariavelResultado.erro('fora_do_limite',
                minimoCents: 500, maximoCents: 928),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
    gravaVersaoHarness();
  });

  for (final tam in kTamanhos) {
    testWidgets('folha da balança cabe com o teclado (${tam.$1})',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'estafeta_peso_folha',
        tela: const _Folha(),
        tamanho: tam,
        teclado: true,
        interagir: (t) async {
          await t.enterText(find.byKey(const Key('peso_campo')), '9,06');
        },
      );
      expect(
          File('test/golden/_fotos/estafeta_peso_folha_${tam.$1}_teclado.png')
              .existsSync(),
          isTrue);
    });

    testWidgets('folha da balança com a recusa do servidor (${tam.$1})',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'estafeta_peso_folha_recusa',
        tela: const _Folha(),
        tamanho: tam,
        interagir: (t) async {
          await t.enterText(find.byKey(const Key('peso_campo')), '15');
          await t.tap(find.byKey(const Key('peso_confirmar')));
          await t.pump();
        },
      );
      expect(find.textContaining('Pesa outra vez'), findsOneWidget);
    });
  }
}
