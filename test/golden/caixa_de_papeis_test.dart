import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/papeis_de_trabalho.dart';
import 'package:bora_app/widgets/caixa_de_papeis.dart';

import 'fabrica_de_fotos.dart';

/// A caixa "O que queres aceitar?" com os QUATRO trabalhos.
///
/// Até 2026-08-28 esta caixa era um rádio de duas opções fixas e o Danilo, com
/// quatro papéis, via duas linhas. As entregas nem sequer eram trabalho
/// próprio — estavam coladas ao papel de motorista, e por isso quem anda de
/// bicicleta não se podia inscrever sem ser motorista de TVDE.
void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  testWidgets('os quatro interruptores, como o Danilo os vê', (tester) async {
    await fotografaTela(
      tester,
      nome: 'caixa_de_papeis_quatro',
      tamanho: ('telemovel', const Size(390, 844)),
      tela: Scaffold(
        backgroundColor: Colors.white,
        body: CaixaDePapeis(
          iniciais: const [
            PapelDeTrabalho(papel: 'driver', aceita: true),
            PapelDeTrabalho(papel: 'delivery', aceita: true),
            PapelDeTrabalho(papel: 'cleaner', aceita: true),
            PapelDeTrabalho(papel: 'washer', aceita: true),
          ],
        ),
      ),
    );

    // Os quatro têm de estar escritos, com nome de gente.
    expect(find.text('Corridas de passageiros'), findsOneWidget);
    expect(find.text('Entregas'), findsOneWidget);
    expect(find.text('Limpeza'), findsOneWidget);
    expect(find.text('Lavagem de carros'), findsOneWidget);

    // E têm de ser quatro interruptores, não um rádio de escolha única.
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    expect(find.byType(RadioListTile<String>), findsNothing,
        reason: 'o rádio das duas opções fixas não pode voltar');
  });

  testWidgets('com um desligado, o desenho mantém-se legível', (tester) async {
    await fotografaTela(
      tester,
      nome: 'caixa_de_papeis_um_desligado',
      tamanho: ('telemovel', const Size(390, 844)),
      tela: Scaffold(
        backgroundColor: Colors.white,
        body: CaixaDePapeis(
          iniciais: const [
            PapelDeTrabalho(papel: 'driver', aceita: true),
            PapelDeTrabalho(papel: 'delivery', aceita: false),
            PapelDeTrabalho(papel: 'cleaner', aceita: true),
            PapelDeTrabalho(papel: 'washer', aceita: true),
          ],
        ),
      ),
    );
    expect(find.byType(SwitchListTile), findsNWidgets(4));
  });
}
