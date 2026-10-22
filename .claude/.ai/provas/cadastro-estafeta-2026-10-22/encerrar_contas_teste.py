"""Encerra as 2 contas de TESTE da missão pelo caminho oficial da app
(Edge `delete-account`, chamada pelo próprio utilizador): anonimiza a linha
do estafeta, apaga as fotos do bucket e bloqueia a conta para sempre.
Só estas duas contas — nunca dados reais. A senha vem de um ficheiro fora do repo.
Uso: python -I encerrar_contas_teste.py <raiz_repo> <ficheiro_senha> <saida.json>
"""
import json
import pathlib
import sys
import urllib.error
import urllib.request

raiz = pathlib.Path(sys.argv[1])
senha = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
defs = json.loads((raiz / ".dart_defines").read_text(encoding="utf-8-sig"))
URL = defs["SUPABASE_URL"].rstrip("/")
KEY = defs["SUPABASE_ANON_KEY"]
CONTAS = ["teste-estafeta-2210@boraguarda.com", "teste-estafeta-2210b@boraguarda.com"]


def pedido(caminho, corpo, token=None):
    h = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(URL + caminho, data=json.dumps(corpo).encode(), headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


res = {}
for email in CONTAS:
    assert email.startswith("teste-estafeta-2210") and email.endswith("@boraguarda.com")
    s, ses = pedido("/auth/v1/token?grant_type=password", {"email": email, "password": senha})
    if s != 200:
        res[email] = {"login": s}
        continue
    s2, b = pedido("/functions/v1/delete-account",
                   {"confirm": True, "motivo": "conta de TESTE da missao cadastro-estafeta-fotos-22-10"},
                   ses["access_token"])
    res[email] = {"login": s, "delete_account_http": s2, "ok": b.get("ok"), "papeis": b.get("papeis"),
                  "drivers": (b.get("prova") or {}).get("drivers"),
                  "storage": (b.get("prova") or {}).get("storage"),
                  "auth": (b.get("prova") or {}).get("auth_users"),
                  "erro": b.get("error"), "bloqueios": b.get("blocked")}
pathlib.Path(sys.argv[3]).write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
print(json.dumps(res, ensure_ascii=False, indent=1))
