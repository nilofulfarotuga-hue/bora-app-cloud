import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, itens 1 e 2] Guardas do visitante sem conta.
///
/// Cicatrizes:
///  - desde 01/09 a app tentava entrar como guest@bora.com com uma palavra-passe
///    escrita no código (repo público); o servidor tinha-a mudado e cada
///    arranque dava 400 + 422 na consola. A palavra-passe NUNCA mais volta ao
///    código: a sessão vem da Edge `sessao-convidado`.
///  - "Finalizar pedido" sem conta não fazia nada (botão mudo):
///    `garantirContactoDoCliente` devolvia false sem abrir nada.
void main() {
  String ler(String p) =>
      File(p).readAsStringSync().replaceAll(String.fromCharCode(13), '');

  test('auth_store não tem palavra-passe do convidado nem signUp do convidado', () {
    final s = ler('lib/auth/auth_store.dart');
    expect(s.contains('_guestPassword'), isFalse);
    expect(RegExp(r"password:\s*'123456'").hasMatch(s), isFalse);
    expect(s.contains("functions.invoke('sessao-convidado')"), isTrue);
    // Só pede a sessão quando o painel a liga (guardas do banco aplicadas).
    expect(s.contains("'sessao_convidado_ativa'"), isTrue);
  });

  test('"Finalizar" sem conta abre "Entrar ou criar conta" e volta ao carrinho', () {
    final s = ler('lib/screens/complete_profile_screen.dart');
    final corpo = s.substring(s.indexOf('Future<bool> garantirContactoDoCliente'));
    expect(corpo.contains('ClientLoginScreen(voltarAoChamador: true)'), isTrue);
    expect(corpo.contains('if (client == null) return false;\n  if (contacto'),
        isFalse,
        reason: 'sem conta não pode voltar a devolver false sem abrir nada');

    final login = ler('lib/screens/client_login_screen.dart');
    expect(login.contains("'Entrar ou criar conta'.tr"), isTrue);
    expect(login.contains('Navigator.of(context).pop(true)'), isTrue);
    final registo = ler('lib/screens/register_client_screen.dart');
    expect(registo.contains('if (widget.voltarAoChamador) {\n      Navigator.of(context).pop(true);'),
        isTrue);
  });

  test('"Sou Cliente" abre a página inicial como visitante', () {
    expect(ler('lib/main.dart').contains('if (auth.isVisitante) return const ClientMainScreen();'),
        isTrue);
    expect(ler('lib/screens/role_screen.dart').contains('entrarComoVisitante()'), isTrue);
  });

  test('migração: o convidado só vê (gatilho + políticas + interruptores)', () {
    final m = ler('supabase/migrations/20261026090000_convidado_so_ve.sql');
    for (final t in ['tvde_rides', 'appointments', 'reservations', 'client_addresses']) {
      expect(m.contains("'$t'"), isTrue, reason: t);
    }
    expect(m.contains('as restrictive for all to authenticated'), isTrue);
    expect(m.contains("('sessao_convidado_ativa', 'false'::jsonb"), isTrue,
        reason: 'nasce desligada até a guarda dos pedidos estar aplicada');
    expect(m.contains("('visitantes_sem_conta', 'true'::jsonb"), isTrue);
  });

  test('Edge sessao-convidado não escreve a palavra-passe em lado nenhum', () {
    final f = ler('supabase/functions/sessao-convidado/index.ts');
    expect(f.contains('console.log'), isFalse);
    expect(f.contains('password: senha'), isTrue);
    expect(RegExp(r'password:\s*[' "'" r'"]').hasMatch(f), isFalse);
  });
}
