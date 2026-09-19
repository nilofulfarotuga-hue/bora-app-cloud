"""As portas: pedido pendente nao bloqueia, e o parceiro tambem tem volta."""
import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")


def edita(caminho, pares, imports=None, ancora=None):
    s = io.open(caminho, encoding="utf-8").read()
    for velho, novo in pares:
        assert velho in s, f"{caminho}: nao encontrei\n{velho[:140]}"
        s = s.replace(velho, novo, 1)
    if imports:
        assert ancora in s, f"{caminho}: ancora de import"
        s = s.replace(ancora, ancora + "\n" + imports, 1)
    io.open(caminho, "w", encoding="utf-8", newline="\n").write(s)
    print("ok", caminho)


# ── 1. CANDIDATURA EM ANALISE nao prende ninguem ───────────────────────────
edita(
    r"lib\screens\driver_pending_screen.dart",
    [(
        """              const SizedBox(height: Spacing.huge),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    context.read<AuthStore>().logout();
                    context.read<SessionStore>().clearRole();
                  },""",
        """              const SizedBox(height: Spacing.lg),
              // PEDIDO PENDENTE NAO BLOQUEIA (2026-08-29). Este ecra so fala
              // do perfil de estafeta. Enquanto a candidatura e revista, a
              // pessoa continua a poder usar a app como cliente — e antes
              // daqui so tinha o botao "Sair", o que a mandava embora da app
              // inteira por causa de um perfil so.
              const Text(
                'Entretanto podes usar a app normalmente para fazer os teus '
                'pedidos. A analise continua na mesma.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  onPressed: () async {
                    // Sem palavra-passe outra vez: a sessao ja e a mesma para
                    // todos os perfis.
                    final ok = await activateRole(context, UserRole.client);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Nao foi possivel abrir o teu perfil de cliente. '
                              'Tenta de novo.')));
                    }
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Usar a app como cliente'),
                ),
              ),
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    context.read<AuthStore>().logout();
                    context.read<SessionStore>().clearRole();
                  },""",
    )],
    imports="import '../services/role_switch_helper.dart';",
    ancora="import '../config/app_spacing.dart';",
)

# ── 2. O ecra de aprovacao pendente do PARCEIRO, o mesmo ───────────────────
p = r"lib\screens\pending_approval_screen.dart"
s = io.open(p, encoding="utf-8").read()
print("   pending_approval tem 'Sair'?", "'Sair'" in s or "Sair" in s)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
