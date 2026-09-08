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

/// Quantos segundos REAIS cada ecrã fica no ar depois da captura.
///
/// PORQUE ISTO EXISTE: o `xcrun simctl recordVideo` do workflow grava o ecrã
/// do simulador durante toda a corrida. Sem esta pausa, o arnês desenha os 7
/// ecrãs, fotografa e passa à frente num instante — medido na gravação da
/// corrida 34167538478: **19,5 minutos de filme e a app visível num único
/// momento de 5 segundos**. Não havia nada para cortar.
///
/// Com 10 segundos por ecrã, os 7 ecrãs dão ~70 s de imagem real da app, que
/// é a matéria-prima do vídeo de 60–120 s das notas ao revisor da Apple.
/// Custa ~1 minuto a uma corrida que já leva ~20; vale a troca.
const int _segundosPorEcra =
    int.fromEnvironment('SEGUNDOS_POR_ECRA', defaultValue: 10);

/// Mantém o ecrã desenhado durante [segundos] de tempo REAL.
///
/// `pumpAndSettle` não serve: devolve assim que as animações assentam e o
/// gravador fica com um piscar. Aqui alterna `pump` (produz frame) com um
/// `Future.delayed` dentro de `runAsync` (deixa o relógio real andar), para o
/// vídeo apanhar o ecrã parado e legível.
Future<void> _segurarEcra(WidgetTester tester, int segundos) async {
  const passo = Duration(milliseconds: 250);
  for (int i = 0; i < segundos * 4; i++) {
    await tester.pump(passo);
    await tester.runAsync(() => Future<void>.delayed(passo));
  }
}

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

      // A captura já está feita; o que se segue é só para o gravador de vídeo.
      await _segurarEcra(tester, _segundosPorEcra);
    }
  });
}
