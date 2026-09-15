"""O ecra de escolha deixa de deitar a sessao fora, e as portas dizem a quem
se destinam."""
import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")
p = r"lib\screens\role_screen.dart"
s = io.open(p, encoding="utf-8").read()

VELHO = """              // ── Buttons ───────────────────────────────────────────────
              BoraPrimaryButton(
                label: 'Sou Cliente',
                icon: Icons.person_outline,
                color: AppColors.primary,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  // L3 — troca de papel, não "Sair": preserva biometria.
                  authStore.logout(wipeBiometrics: false);
                  await sessionStore.setRole(UserRole.client);
                },
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Sou Estafeta',
                icon: Icons.delivery_dining,
                color: AppColors.accent,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  // L3 — troca de papel, não "Sair": preserva biometria.
                  authStore.logout(wipeBiometrics: false);
                  await sessionStore.setRole(UserRole.driver);
                },
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Sou Parceiro',
                icon: Icons.storefront_outlined,
                color: AppColors.info,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  // L3 — troca de papel, não "Sair": preserva biometria.
                  authStore.logout(wipeBiometrics: false);
                  await sessionStore.setRole(UserRole.partner);
                },
              ),
"""

NOVO = """              // ── As três portas ────────────────────────────────────────
              //
              // UMA CONTA, TODOS OS PERFIS (2026-08-29). Até aqui, cada um
              // destes botões fazia `logout()` — **mesmo com sessão aberta**.
              // Quem já estava dentro e queria só mudar de perfil era posto
              // fora e obrigado a escrever a palavra-passe outra vez. Era a
              // segunda causa da mesma queixa: a primeira era o login de
              // cliente expulsar quem também é estafeta.
              //
              // Agora, com sessão aberta, troca-se o perfil por dentro
              // (`activateRole`, que reaproveita o mesmo JWT). Só quem não
              // tem sessão é que vai parar ao ecrã de entrar.
              _PortaDoPerfil(
                rotulo: 'Sou Cliente',
                paraQuem: 'Pedir comida, compras e serviços',
                icone: Icons.person_outline,
                cor: AppColors.primary,
                papel: UserRole.client,
              ),
              const SizedBox(height: Spacing.md),
              _PortaDoPerfil(
                rotulo: 'Sou Estafeta',
                paraQuem: 'Entregar, fazer corridas, limpezas ou lavagens',
                icone: Icons.delivery_dining,
                cor: AppColors.accent,
                papel: UserRole.driver,
              ),
              const SizedBox(height: Spacing.md),
              _PortaDoPerfil(
                rotulo: 'Sou Parceiro',
                paraQuem: 'Tenho restaurante, loja ou salão no Bora',
                icone: Icons.storefront_outlined,
                cor: AppColors.info,
                papel: UserRole.partner,
              ),
"""
assert VELHO in s, "nao encontrei os tres botoes"
s = s.replace(VELHO, NOVO, 1)

WIDGET = '''

/// Uma das três portas do arranque.
///
/// Diz **a quem se destina** por baixo do nome — um cliente real caiu nas três
/// numa noite só, porque "Sou Estafeta" e "Sou Parceiro" não explicavam nada.
class _PortaDoPerfil extends StatelessWidget {
  const _PortaDoPerfil({
    required this.rotulo,
    required this.paraQuem,
    required this.icone,
    required this.cor,
    required this.papel,
  });

  final String rotulo;
  final String paraQuem;
  final IconData icone;
  final Color cor;
  final UserRole papel;

  Future<void> _entrar(BuildContext context) async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    // Com sessão aberta, troca-se por dentro: a mesma conta serve todos os
    // perfis e o JWT actual já vale para todos.
    if (Supabase.instance.client.auth.currentUser != null) {
      final ok = await activateRole(context, papel);
      if (ok) return;
      // Não tem esse perfil (ou faltam-lhe os dados neste aparelho): cai para
      // o ecrã de entrar desse perfil, que explica o que falta.
    }

    // L3 — troca de papel, não "Sair": preserva biometria.
    authStore.logout(wipeBiometrics: false);
    await sessionStore.setRole(papel);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoraPrimaryButton(
          label: rotulo,
          icon: icone,
          color: cor,
          onPressed: () => _entrar(context),
        ),
        const SizedBox(height: 4),
        Text(
          paraQuem,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
'''
s = s.rstrip("\n") + "\n" + WIDGET

# imports
for imp, anc in [
    ("import 'package:supabase_flutter/supabase_flutter.dart';",
     "import 'package:provider/provider.dart';"),
    ("import '../services/role_switch_helper.dart';",
     "import '../stores/session_store.dart';"),
]:
    if imp not in s:
        assert anc in s, "ancora " + anc
        s = s.replace(anc, anc + "\n" + imp, 1)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("role_screen corrigido")
