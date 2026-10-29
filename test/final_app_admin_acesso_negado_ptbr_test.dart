// Auditoria final-app 29/10/2026 (bloco 7.4): quem abre /#/admin sem ser
// administrador via "O seu email não está na lista de admins." — português de
// Portugal e a palavra "admins". O painel é em PT-BR ("Seu e-mail...").
import 'package:bora_app/screens/admin/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sem ser administrador: acesso negado em PT-BR', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminAcessoNegado()));
    await tester.pump();

    expect(find.text('Painel Admin'), findsOneWidget);
    expect(find.textContaining('Acesso negado.'), findsOneWidget);
    expect(
        find.textContaining('Seu e-mail não está na lista de administradores'),
        findsOneWidget);
    // O português de Portugal e o "admins" saíram.
    expect(find.textContaining('O seu email'), findsNothing);
    expect(find.textContaining('lista de admins'), findsNothing);
  });
}
