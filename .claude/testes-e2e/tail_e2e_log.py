# -*- coding: utf-8 -*-
"""Monitor de consola — mostra as ultimas 15 linhas de e2e_log, atualiza a cada 5s.
Leitura pura (SELECT via REST), nunca escreve. Usa as mesmas credenciais do e2e_diario.py.
"""
import json
import os
import re
import time
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent


def _load_env() -> dict:
    env = {}
    for f in [BASE / ".env", REPO / "backend" / ".env"]:
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?([^\"'#]+)", line)
                if m:
                    env.setdefault(m.group(1), m.group(2).strip())
    url = env.get("SUPABASE_URL") or env.get("SUPABASE_PROJECT_URL")
    key = (env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY")
           or env.get("SUPABASE_KEY") or env.get("SUPABASE_ANON_KEY"))
    return {"url": url, "key": key}


_DB = _load_env()


def fetch():
    if not (_DB["url"] and _DB["key"]):
        return None
    req = urllib.request.Request(
        f"{_DB['url']}/rest/v1/e2e_log?select=created_at,fluxo,passo,estado,device"
        f"&order=created_at.desc&limit=15",
        headers={"apikey": _DB["key"], "Authorization": f"Bearer {_DB['key']}"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read().decode())


def main():
    while True:
        os.system("cls" if os.name == "nt" else "clear")
        print("=== Bora e2e_log — ultimas 15 (atualiza a cada 5s) ===\n")
        try:
            rows = fetch()
            if rows is None:
                print("(sem SUPABASE_URL/KEY em .env — monitor sem dados)")
            elif not rows:
                print("(sem linhas ainda)")
            else:
                print(f"{'hora':8} | {'fluxo':22} | {'passo':38} | estado")
                print("-" * 90)
                for row in rows:
                    hora = (row.get("created_at") or "")[11:19]
                    fluxo = (row.get("fluxo") or "")[:22]
                    passo = (row.get("passo") or "")[:38]
                    estado = row.get("estado") or ""
                    print(f"{hora:8} | {fluxo:22} | {passo:38} | {estado}")
        except Exception as e:
            print(f"[erro a consultar e2e_log] {e}")
        time.sleep(5)


if __name__ == "__main__":
    main()
