# -*- coding: utf-8 -*-
"""
Limpeza pós-ciclo E2E (idempotente, conservadora):
1. Marca is_test_order=true nos pedidos do estafeta/contas de teste (BI/admin filtram).
2. Põe o estafeta de teste OFFLINE (nunca fica online fora de um teste).
NUNCA apaga linhas (ledger é append-only; histórico fica, marcado como teste).
"""
import json
import re
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent
env = {}
for f in [BASE / ".env", BASE.parent.parent / "backend" / ".env"]:
    if f.exists():
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*([A-Z_]+)\s*=\s*[\"']?([^\"'#]+)", line)
            if m:
                env.setdefault(m.group(1), m.group(2).strip())
URL = env["SUPABASE_URL"].rstrip("/")
KEY = env.get("SUPABASE_SERVICE_ROLE_KEY") or env["SERVICE_ROLE_KEY"]
DRIVER_UID = "2120ca68-c777-4106-bc52-2c1399ec385c"  # teste-estafeta@bora.app


def patch(tabela, filtro, body):
    r = urllib.request.Request(f"{URL}/rest/v1/{tabela}?{filtro}", method="PATCH",
                               headers={"apikey": KEY, "Authorization": f"Bearer {KEY}",
                                        "Content-Type": "application/json", "Prefer": "return=representation"},
                               data=json.dumps(body).encode())
    with urllib.request.urlopen(r, timeout=30) as resp:
        return json.loads(resp.read().decode() or "[]")


n1 = patch("orders", f"assigned_driver_id=eq.{DRIVER_UID}&is_test_order=eq.false", {"is_test_order": True})
n2 = patch("orders", "customer_name=ilike.*TESTE%20E2E*&is_test_order=eq.false", {"is_test_order": True})
n3 = patch("drivers", f"id=eq.{DRIVER_UID}", {"is_online": False})
print(f"pedidos marcados teste: {len(n1) + len(n2)} · estafeta de teste offline: {bool(n3)}")
