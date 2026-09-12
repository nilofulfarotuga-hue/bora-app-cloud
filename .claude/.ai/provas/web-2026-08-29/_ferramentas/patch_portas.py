"""O botao de voltar na porta do parceiro, e as portas bem marcadas."""
import io
import os

os.chdir(r"C:\Users\danil\Desktop\projetosflutter\_wt-prod")


def edita(caminho, pares, imports=None, ancora=None):
    s = io.open(caminho, encoding="utf-8").read()
    for velho, novo in pares:
        assert velho in s, f"{caminho}: nao encontrei\n{velho[:150]}"
        s = s.replace(velho, novo, 1)
    if imports:
        assert ancora in s, f"{caminho}: ancora"
        s = s.replace(ancora, ancora + "\n" + imports, 1)
    io.open(caminho, "w", encoding="utf-8", newline="\n").write(s)
    print("ok", caminho)


# ── 1. A porta do parceiro passa a ter volta, como as outras duas ─────────
edita(
    r"lib\screens\partner_login_screen.dart",
    [(
        """              const SizedBox(height: Spacing.md),
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _createAccount,
                  child: const Text(
                    'Não tens conta? Criar conta de parceiro',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],""",
        """              const SizedBox(height: Spacing.md),
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _createAccount,
                  child: const Text(
                    'Não tens conta? Criar conta de parceiro',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // AS TRÊS PORTAS IGUAIS (2026-08-29). O cliente e o estafeta
              // tinham este botão; o parceiro não, e quem lá caísse por engano
              // ficava sem saída à vista. Um cliente real caiu nas três portas
              // na mesma noite.
              Center(
                child: TextButton(
                  onPressed: _isProcessing ? null : _voltarAosPerfis,
                  child: const Text('← Voltar à escolha de perfil'),
                ),
              ),
            ],""",
    ), (
        """  void _createAccount() {""",
        """  void _voltarAosPerfis() {
    context.read<SessionStore>().clearRole();
  }

  void _createAccount() {""",
    )],
)

# ── 2. As portas dizem a quem se destinam ─────────────────────────────────
s = io.open(r"lib\screens\role_screen.dart", encoding="utf-8").read()
for velho, novo in [
    ("'Sou Cliente'", "'Sou Cliente'"),
]:
    pass
print("   role_screen: ver a seguir")
