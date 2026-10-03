// E2E web — fluxo de LOGIN do cliente, corrido no browser (Chrome headless).
// Prova real: screenshots antes/depois + verificação de que o ClientMainScreen
// entra na árvore de widgets após o login demo (cliente@bora.app / 123456).
//
// Ver test_driver/integration_test.dart para o runner e a gravação dos PNG.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bora_app/main.dart' as app;
import 'package:bora_app/screens/role_screen.dart';
import 'package:bora_app/screens/client_login_screen.dart';
import 'package:bora_app/screens/client_main_screen.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cliente faz login pela web e chega ao ClientMainScreen',
      (WidgetTester tester) async {
    app.main();
    // A app arranca no RoleScreen (sem role definido).
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.byType(RoleScreen), findsOneWidget,
        reason: 'esperado arrancar no RoleScreen');
    await binding.takeScreenshot('01_role_screen');

    // Toca "Sou Cliente" → setRole(client) → ClientLoginScreen.
    await tester.tap(find.text('Sou Cliente'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.byType(ClientLoginScreen), findsOneWidget,
        reason: 'esperado o ecrã de login do cliente');
    await binding.takeScreenshot('02_client_login');

    // Em debug os campos vêm pré-preenchidos (cliente@bora.app / 123456).
    // Toca "Entrar".
    await tester.tap(find.text('Entrar'));
    // O login demo é in-memory; damos tempo para o _RootNavigator reconstruir.
    await tester.pumpAndSettle(const Duration(seconds: 8));

    expect(find.byType(ClientMainScreen), findsOneWidget,
        reason: 'login demo devia levar ao ClientMainScreen');
    await binding.takeScreenshot('03_client_home');
  });
}
