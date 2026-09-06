// F-OLHO · Camada 1 — suíte inicial de telas principais.
//
// Cada tela é renderizada em memória nos 3 tamanhos. Overflow = o teste FALHA
// sozinho (regra de ouro). Fotos versionadas em test/golden/_fotos/.
//
// Variante TECLADO: só faz sentido em telas COM campos de texto (o teclado
// nunca abre nas outras). A máquina do teclado é exercitada pela fixture
// `_TelaComInput` abaixo; telas reais com input entram na lista `telasComInput`
// à medida que forem seguras de montar sem Supabase.
//
// COBERTURA v1 (telas sem Supabase no arranque). Crescer aqui é barato:
// adicionar 1 linha por tela segura, ou um Fake de store como nos testes
// existentes (ver test/my_cards_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bora_app/screens/driver_pending_screen.dart';
import 'package:bora_app/screens/driver_rejected_screen.dart';
import 'package:bora_app/screens/role_screen.dart';

import 'fabrica_de_fotos.dart';

/// Fixture COM input — prova que a variante teclado (viewInsets simulado)
/// funciona: campo + botão dentro de scroll, nunca estoura com teclado aberto.
class _TelaComInput extends StatelessWidget {
  const _TelaComInput();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fixture input')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 320),
            const TextField(
              decoration: InputDecoration(labelText: 'Escreve aqui'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await carregaFonteInter();
    await carregaFontesSdk();
    gravaVersaoHarness();
  });

  final telas = <String, Widget Function()>{
    'role': () => const RoleScreen(),
    'driver_pending': () => const DriverPendingScreen(),
    'driver_rejected': () => const DriverRejectedScreen(),
    'driver_rejected_motivo': () =>
        const DriverRejectedScreen(reason: 'Documento ilegível — reenviar.'),
  };

  final telasComInput = <String, Widget Function()>{
    'fixture_input': () => const _TelaComInput(),
  };

  for (final entry in telas.entries) {
    for (final tamanho in kTamanhos) {
      testWidgets('${entry.key} — ${tamanho.$1} sem estouro', (tester) async {
        await fotografaTela(
          tester,
          nome: entry.key,
          tela: entry.value(),
          tamanho: tamanho,
        );
      });
    }
  }

  for (final entry in telasComInput.entries) {
    testWidgets('${entry.key} — pequeno com teclado', (tester) async {
      await fotografaTela(
        tester,
        nome: entry.key,
        tela: entry.value(),
        tamanho: kTamanhos.first,
        teclado: true,
      );
    });
  }
}
