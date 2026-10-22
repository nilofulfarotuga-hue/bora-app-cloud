"""Conta de TESTE do parceiro (demo-parceiro@bora.app, loja invisivel).

  python conta_teste.py entrar        -> confirma que entra (so mostra estado e papel)
  python conta_teste.py sair-global   -> revoga TODAS as sessoes desta conta de teste
                                         (a do browser incluida), como faz o servidor
                                         quando a sessao cai. Nunca em conta real.
"""
import json
import sys
import urllib.error
import urllib.request

URL = "https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1"
CHAVE = "sb_publishable_ylfhSuS2D_JoKmtFY-x6-A_DlOgHhVP"
EMAIL = "demo-parceiro@bora.app"
SENHA = "BoraDemo2026!"
assert EMAIL.startswith("demo-"), "so contas de teste"


def pedir(caminho, corpo=None, token=None):
    h = {"apikey": CHAVE, "Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        URL + caminho,
        data=json.dumps(corpo or {}).encode(),
        headers=h,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            bruto = r.read().decode()
            return r.status, (json.loads(bruto) if bruto else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def entrar():
    st, j = pedir("/token?grant_type=password", {"email": EMAIL, "password": SENHA})
    papel = (j.get("user") or {}).get("user_metadata", {}).get("bora_role")
    print("entrar:", st, "papel:", papel, "erro:", j.get("error_code") or j.get("msg"))
    return j.get("access_token") if st == 200 else None


if __name__ == "__main__":
    acao = sys.argv[1] if len(sys.argv) > 1 else "entrar"
    tok = entrar()
    if acao == "sair-global" and tok:
        st, j = pedir("/logout?scope=global", token=tok)
        print("sair-global:", st, j or "")
