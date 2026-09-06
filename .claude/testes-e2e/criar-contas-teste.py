# -*- coding: utf-8 -*-
"""
Cria as contas de teste E2E via Auth Admin API (idempotente).
Segredos: lê backend/.env; NUNCA imprime chaves. Só imprime uid/estado.
Contas: teste-cliente@bora.app (client) · teste-estafeta@bora.app (driver) · teste-parceiro@bora.app (partner)
"""
import json
import re
import secrets
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent

env = {}
for line in (REPO / "backend" / ".env").read_text(encoding="utf-8", errors="replace").splitlines():
    m = re.match(r"^\s*([A-Z_]+)\s*=\s*[\"']?([^\"'#]+)", line)
    if m:
        env[m.group(1)] = m.group(2).strip()
URL, KEY = env["SUPABASE_URL"].rstrip("/"), env["SUPABASE_SERVICE_ROLE_KEY"]

envfile = BASE / ".env"
local = {}
if envfile.exists():
    for line in envfile.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z0-9_]+)=(.*)$", line)
        if m:
            local[m.group(1)] = m.group(2)
local.setdefault("SUPABASE_URL", URL)
local.setdefault("SUPABASE_SERVICE_ROLE_KEY", KEY)


def req(method, path, body=None):
    r = urllib.request.Request(f"{URL}{path}", method=method,
                               headers={"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
                               data=json.dumps(body).encode() if body else None)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def garante_user(email, role, pw_var):
    pw = local.get(pw_var) or ("BoraE2E-" + secrets.token_urlsafe(9))
    local[pw_var] = pw
    st, out = req("POST", "/auth/v1/admin/users",
                  {"email": email, "password": pw, "email_confirm": True,
                   "user_metadata": {"bora_role": role, "name": f"TESTE E2E {role} (nao usar)"}})
    if st in (200, 201):
        print(f"{email}: CRIADO uid={out.get('id')}")
        return out.get("id")
    # já existe → procurar uid e SINCRONIZAR a password com o .env (senão dessincroniza)
    st2, users = req("GET", f"/auth/v1/admin/users?page=1&per_page=100")
    for u in (users.get("users") or []):
        if u.get("email") == email:
            st3, _ = req("PUT", f"/auth/v1/admin/users/{u['id']}", {"password": pw})
            print(f"{email}: JA-EXISTIA uid={u['id']} (password sincronizada: {st3 == 200})")
            return u["id"]
    print(f"{email}: ERRO {st} {json.dumps(out)[:200]}")
    return None


uid_c = garante_user("teste-cliente@bora.app", "client", "E2E_CLIENT_PASSWORD")
uid_d = garante_user("teste-estafeta@bora.app", "driver", "E2E_DRIVER_PASSWORD")
uid_p = garante_user("teste-parceiro@bora.app", "partner", "E2E_PARTNER_PASSWORD")

envfile.write_text("".join(f"{k}={v}\n" for k, v in local.items()), encoding="utf-8")
print("credenciais em .claude/testes-e2e/.env (gitignorado)")
print(json.dumps({"client_uid": uid_c, "driver_uid": uid_d, "partner_uid": uid_p}))
