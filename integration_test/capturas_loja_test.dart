// Captura de ecrã para a App Store — missão `ios-lancamento` (2026-09-07).
//
// Diferente de `e2e_test.dart` ("Bora E2E Web"): este teste NÃO chama
// `app.main()` nem toca em Supabase/Firebase/Stripe/foreground service/
// Timer.periodic nenhum. Pumpa directamente os 7 widgets estáticos de
// `screens/capturas/captura_screens.dart`, cada um dentro do seu próprio
// `MaterialApp` de teste — por isso o `pumpAndSettle` assenta sempre e o
// binding nunca fica com `_pendingFrame != null`.
//
// Corrido pelo `test_driver/capturas_driver.dart` (`flutter drive`), que grava
// cada `takeScreenshot(...)` como PNG em `artefactos/capturas/<nome>.png`.
//
// Resolução: o simulador já é escolhido pelo workflow como o maior iPhone
// disponível (preferência "Pro Max", ver `.github/workflows/build_ios.yml`,
// passo "Escolher e arrancar um simulador") — que é o 6,9" (1320×2868) que a
// Apple exige nas capturas. Não é preciso forçar `physicalSize` aqui: cada
// ecrã já ocupa o ecrã inteiro do simulador via `MaterialApp` normal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/screens/capturas/captura_screens.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gera as 7 capturas de ecrã para a App Store',
      (WidgetTester tester) async {
    for (final CapturaScreenSpec spec in capturaScreens) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Builder(builder: spec.builder),
        ),
      );
      // Sem rede e sem Timer.periodic nestes ecrãs — um pumpAndSettle curto
      // já é suficiente para assentar animações de entrada do Material.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await binding.takeScreenshot(spec.fileName);
    }
  });
}
