// F-OLHO · PROVA DA FASE — defeito plantado de propósito.
//
// A missão exige provar que a Camada 1 apanha SOZINHA uma tela estourada:
// esta fixture tem uma Row larga demais para 320px (botões fora do ecrã).
// O teste confirma que o motor de deteção (FlutterError de overflow) dispara
// — ou seja, se uma tela REAL estourar, a suíte principal falha da mesma forma.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tela DEFEITUOSA de propósito: Row sem Expanded/Flexible com 2 botões de
/// largura fixa 240 → 480px de conteúdo em 320px de ecrã = RenderFlex overflow.
class TelaComDefeitoPlantado extends StatelessWidget {
  const TelaComDefeitoPlantado({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fixture de defeito')),
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Botão largo A'),
            ),
          ),
          SizedBox(
            width: 240,
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Botão largo B'),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('camada 1 apanha sozinha a tela estourada (320x640)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TelaComDefeitoPlantado(),
    ));

    final erro = tester.takeException();
    expect(erro, isNotNull,
        reason: 'O overflow plantado TINHA de ser detetado — se isto falhar, '
            'o motor da Camada 1 deixou de apanhar telas estouradas.');
    expect('$erro', contains('overflowed'),
        reason: 'O erro detetado deve ser o RenderFlex overflow.');
  });
}
