"""Remove TODOS os dados de demonstração (marcador DEMO_). Dry-run default.

Apaga: orders is_test_order=true com customer_name DEMO_*; users email demo_*@bora.test.
Nunca toca dados reais (só o que tem o marcador).

Uso:
  python cleanup.py             # dry-run (conta)
  python cleanup.py --commit    # remove
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log, audit_log, DEMO_PREFIX, DEMO_EMAIL_DOMAIN


def count(ctx: Ctx, path: str) -> int:
    r = requests.get(f"{ctx.supabase_url}/rest/v1/{path}", timeout=30,
                     headers={"Authorization": f"Bearer {ctx.service_role_key}",
                              "apikey": ctx.anon_key, "Prefer": "count=exact", "Range": "0-0"})
    cr = r.headers.get("Content-Range", "")
    return int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1].isdigit() else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    orders_q = f"orders?is_test_order=eq.true&customer_name=like.{DEMO_PREFIX}*"
    users_q = f"users?email=like.demo_*@{DEMO_EMAIL_DOMAIN}"
    n_orders = count(ctx, orders_q + "&select=id")
    n_users = count(ctx, users_q + "&select=id")
    log(f"A remover (marcador DEMO_): {n_orders} pedidos + {n_users} clientes.")

    if not args.commit:
        log("[DRY-RUN] nada removido. Use --commit. (Só apaga o que tem marcador DEMO_.)")
        return 0

    ro = ctx.rest("DELETE", orders_q, ctx.service_role_key)
    ru = ctx.rest("DELETE", users_q, ctx.service_role_key)
    log(f"orders removidos: {ro.status_code} · users removidos: {ru.status_code}")
    audit_log(ctx, "demo_data_cleaned", "system", "seed-demo-data",
              {"orders": n_orders, "users": n_users})
    log("✅ Demo data removida. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
