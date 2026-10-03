# -*- coding: utf-8 -*-
"""
Diário E2E — dá OLHOS EM TEMPO REAL ao Claude.ai sobre o que o teste faz.

Cada passo importante do runner/loop escreve UMA linha na tabela Supabase
`e2e_log` (id, created_at, fluxo, passo, estado, detalhe, device, run_id).
O Claude.ai faz `SELECT ... FROM e2e_log ORDER BY created_at DESC` a qualquer
momento e vê ao vivo — sem depender de ninguém contar.

Regras:
- Observabilidade PURA: tabela não-financeira, não-produção.
- Best-effort: um INSERT que falhe NUNCA pode partir o teste (swallow + timeout curto).
- Sem credenciais DB → no-op silencioso (o teste corre na mesma).
"""
import json
import os
import re
import time
import urllib.request
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent


def _load_env() -> dict:
    """SUPABASE_URL/KEY de .env local, fallback backend/.env (só leitura de valores)."""
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

# run_id: agrupa todos os eventos desta execução do processo (data-hora + pid).
RUN_ID = os.environ.get("E2E_RUN_ID") or (
    datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}")

# device por defeito (o runner passa o serial real; o loop usa 'vps'/host).
_DEFAULT_DEVICE = os.environ.get("E2E_LOG_DEVICE", "")

_avisou_sem_db = False


def ativo() -> bool:
    return bool(_DB["url"] and _DB["key"])


def registar(fluxo: str, passo: str, estado: str, detalhe: str = "",
             device: str = "") -> None:
    """INSERT best-effort de 1 evento em e2e_log. Nunca lança."""
    global _avisou_sem_db
    if not ativo():
        if not _avisou_sem_db:
            print("[e2e_diario] sem SUPABASE_URL/KEY — diário desligado (teste corre na mesma)")
            _avisou_sem_db = True
        return
    payload = {
        "fluxo": (fluxo or "")[:200],
        "passo": (passo or "")[:400],
        "estado": (estado or "")[:40],
        "detalhe": (detalhe or "")[:4000],
        "device": (device or _DEFAULT_DEVICE or "")[:120],
        "run_id": RUN_ID,
    }
    try:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{_DB['url']}/rest/v1/e2e_log",
            data=data, method="POST",
            headers={
                "apikey": _DB["key"],
                "Authorization": f"Bearer {_DB['key']}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            })
        urllib.request.urlopen(req, timeout=8).read()
    except Exception as e:
        # Observabilidade nunca pode afundar o teste: só avisa uma vez por tipo.
        print(f"[e2e_diario] INSERT falhou (não-fatal): {str(e)[:120]}")


if __name__ == "__main__":
    # smoke: escreve 3 linhas de teste e confirma que ativou.
    print(f"ativo={ativo()} run_id={RUN_ID}")
    registar("smoke-diario", "arranque do smoke", "iniciou", "teste do e2e_diario", "cli")
    time.sleep(0.3)
    registar("smoke-diario", "meio", "passou", "linha do meio", "cli")
    time.sleep(0.3)
    registar("smoke-diario", "fim", "passou", "última linha", "cli")
    print("3 linhas enviadas (se ativo).")
