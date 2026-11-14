// Auditoria final-app 29/10/2026 (bloco 7.4): quem abre /#/admin sem ser
// administrador via "O seu email não está na lista de admins." — português de
// Portugal e a palavra "admins". O painel é em PT-BR.
//
// fechar-app-15-11 (Bloco 6, 14/11/2026): a frase "Seu e-mail não está na
// lista de administradores" também saiu — a app não tem lista de e-mails, o
// portão olha para o perfil de administrador da conta. A mensagem passa a
// dizer com que conta a pessoa entrou e o que fazer, sem mostrar o e-mail da
// conta de administrador a quem não é administrador.
import 'package:bora_app/screens/admin/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sem ser administrador: acesso negado em PT-BR, com a conta',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AdminAcessoNegado(emailAtual: 'loja@exemplo.pt')));
    await tester.pump();

    expect(find.text('Painel Admin'), findsOneWidget);
    expect(find.textContaining('Acesso negado.'), findsOneWidget);
    // Diz com que conta entrou e o que fazer.
    expect(find.textContaining('Você entrou com loja@exemplo.pt'),
        findsOneWidget);
    expect(find.textContaining('não tem perfil de administrador'),
        findsOneWidget);
    expect(find.textContaining('entre com a conta de administrador do Bora'),
        findsOneWidget);
    // A frase enganadora da "lista" saiu, e o português de Portugal também.
    expect(find.textContaining('lista de administradores'), findsNothing);
    expect(find.textContaining('O seu email'), findsNothing);
    expect(find.textContaining('lista de admins'), findsNothing);
  });

  testWidgets('sem sessão nenhuma: manda entrar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminAcessoNegado()));
    await tester.pump();

    expect(find.textContaining('Acesso negado.'), findsOneWidget);
    expect(find.textContaining('ainda não entrou em nenhuma conta'),
        findsOneWidget);
    expect(find.textContaining('Você entrou com'), findsNothing);
  });

  test('a mensagem nunca mostra o e-mail de um administrador', () {
    // Só entra na frase o e-mail de quem tem a sessão aberta.
    final texto = AdminAcessoNegado.mensagem('alguem@exemplo.pt');
    expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').allMatches(texto).length, 1);
    expect(texto, contains('alguem@exemplo.pt'));
    expect(AdminAcessoNegado.mensagem('   '),
        AdminAcessoNegado.mensagem(null));
  });
}
