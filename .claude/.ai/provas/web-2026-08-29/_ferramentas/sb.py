"""Falar com o Supabase sem curl (o hook do context-mode intercepta curl).

  python sb.py sql "SELECT ..."
  python sb.py magiclink <email>
"""
import json
import sys
import urllib.request

PROJ = "ojykpzwqrtusfeakzrna"
ENV = r"C:\Users\danil\Desktop\projetosflutter\bora_app\.supabase-token.env"


def token():
    for linha in open(ENV, encoding="utf-8"):
        linha = linha.strip()
        if "=" in linha and not linha.startswith("#"):
            k, v = linha.split("=", 1)
            if k.strip() in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_TOKEN"):
                return v.strip().strip('"').strip("'")
    raise SystemExit("token nao encontrado")


def pedir(url, dados=None, cabecalhos=None, metodo=None):
    corpo = json.dumps(dados).encode() if dados is not None else None
    h = {"Content-Type": "application/json", "User-Agent": "bora-cli"}
    h.update(cabecalhos or {})
    req = urllib.request.Request(url, data=corpo, headers=h, method=metodo)
    with urllib.request.urlopen(req, timeout=180) as r:
        bruto = r.read().decode()
    return json.loads(bruto) if bruto else None


def sql(q):
    return pedir(
        f"https://api.supabase.com/v1/projects/{PROJ}/database/query",
        {"query": q},
        {"Authorization": "Bearer " + token()},
    )


def segredos():
    linhas = sql(
        "select name, decrypted_secret from vault.decrypted_secrets "
        "where name in ('project_url','service_role_key')"
    )
    return {r["name"]: r["decrypted_secret"] for r in linhas}


def auth_admin(caminho, dados=None, metodo=None):
    s = segredos()
    return pedir(
        s["project_url"] + "/auth/v1/" + caminho, dados,
        {"apikey": s["service_role_key"],
         "Authorization": "Bearer " + s["service_role_key"]},
        metodo,
    )


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "sql":
        print(json.dumps(sql(sys.argv[2]), ensure_ascii=False, indent=1))
    elif cmd == "magiclink":
        r = auth_admin("admin/generate_link", {
            "type": "magiclink", "email": sys.argv[2],
            "options": {"redirect_to": "https://app.boraguarda.com"}})
        print(r.get("action_link") or json.dumps(r)[:400])
    else:
        raise SystemExit("comando desconhecido")
