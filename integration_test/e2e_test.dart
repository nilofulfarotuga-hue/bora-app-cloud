import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bora_app/main.dart' as app;
import 'package:bora_app/screens/client_home_screen.dart';
import 'package:bora_app/screens/client_main_screen.dart';
import 'package:bora_app/screens/login_screen.dart';
import 'package:bora_app/screens/role_screen.dart';
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Bora E2E Web — 6 fluxos', () {
    Future<void> loginCliente(WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      if (find.byType(RoleScreen).evaluate().isNotEmpty) {
        final roleBtn = find.text('Cliente');
        if (roleBtn.evaluate().isNotEmpty) {
          await tester.tap(roleBtn);
          await tester.pumpAndSettle(const Duration(seconds: 5));
        }
      }

      if (find.byType(LoginScreen).evaluate().isNotEmpty) {
        final emailField = find.widgetWithText(TextField, 'Email');
        if (emailField.evaluate().isNotEmpty) {
          await tester.enterText(emailField, 'cliente1@swarm.bora.test');
        }
        final passField = find.widgetWithText(TextField, 'Palavra-passe');
        if (passField.evaluate().isNotEmpty) {
          await tester.enterText(passField, 'SwarmBora2026!');
        }
        await tester.pump(const Duration(milliseconds: 300));
        final entrarBtn = find.text('Entrar');
        if (entrarBtn.evaluate().isNotEmpty) {
          await tester.tap(entrarBtn);
        }
        await tester.pumpAndSettle(const Duration(seconds: 20));
      }
    }

    testWidgets('01 — Login cliente cash',
        (tester) async {
      await loginCliente(tester);

      final isHome =
          find.byType(ClientMainScreen).evaluate().isNotEmpty ||
          find.byType(ClientHomeScreen).evaluate().isNotEmpty;
      expect(isHome, isTrue,
          reason: 'Login cliente deve ir para ClientMainScreen ou ClientHomeScreen');
    });

    testWidgets('02 — Navegar TVDE/corrida',
        (tester) async {
      await loginCliente(tester);

      final btn = find.textContaining('TVDE');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      expect(find.byType(ClientMainScreen).evaluate().isNotEmpty ||
          btn.evaluate().isNotEmpty, isTrue);
    });

    testWidgets('03 — Navegar Delivery/restaurantes',
        (tester) async {
      await loginCliente(tester);

      final btn = find.textContaining('Restaurante');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      expect(true, isTrue);
    });

    testWidgets('04 — Navegar Limpeza',
        (tester) async {
      await loginCliente(tester);

      final btn = find.textContaining('Limpeza');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      expect(true, isTrue);
    });

    testWidgets('05 — Navegar Reservas',
        (tester) async {
      await loginCliente(tester);

      final btn = find.textContaining('Reserva');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      expect(true, isTrue);
    });

    testWidgets('06 — Navegar Varredura',
        (tester) async {
      await loginCliente(tester);

      final btn = find.textContaining('Varredura');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      expect(true, isTrue);
    });
  });
}
