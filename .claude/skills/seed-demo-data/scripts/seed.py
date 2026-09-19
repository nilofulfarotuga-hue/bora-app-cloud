"""Cria dados de demonstração (clientes DEMO_ + pedidos cash is_test_order=true).

Dry-run por defeito. --commit grava. NUNCA Stripe (só cash). Tudo reversível por DEMO_.

Uso:
  python seed.py --clients 3 --orders 5            # dry-run
  python seed.py --clients 3 --orders 5 --commit
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys

from _shared import Ctx, log, audit_log, DEMO_PREFIX, DEMO_EMAIL_DOMAIN


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clients", type=int, default=3)
    ap.add_argument("--orders", type=int, default=5)
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    now = dt.datetime.now(dt.timezone.utc).isoformat()

    clients = [{"name": f"{DEMO_PREFIX}Cliente {i}", "email": f"demo_{i}@{DEMO_EMAIL_DOMAIN}",
                "phone": f"9{i:08d}", "role": "client"} for i in range(1, args.clients + 1)]
    orders = [{"status": "created", "customer_name": f"{DEMO_PREFIX}Cliente {((i % max(args.clients,1)) + 1)}",
               "payment_method": "cash", "is_test_order": True, "service_type": "restaurant",
               "subtotal": 10 + i, "created_at": now} for i in range(1, args.orders + 1)]

    log(f"Plano: {len(clients)} clientes DEMO_ + {len(orders)} pedidos (cash, is_test_order=true).")
    if not args.commit:
        for c in clients[:3]:
            log(f"  cliente: {c['name']} <{c['email']}>")
        for o in orders[:3]:
            log(f"  pedido: {o['customer_name']} cash subtotal={o['subtotal']}")
        log("[DRY-RUN] nada gravado. Use --commit. (Stripe nunca é tocado.)")
        return 0

    rc = ctx.rest("POST", "users", ctx.service_role_key, clients)
    nc = len(rc.json()) if rc.status_code < 300 else 0
    log(f"users DEMO_ criados: {nc} ({rc.status_code})")
    ro = ctx.rest("POST", "orders", ctx.service_role_key, orders)
    no = len(ro.json()) if ro.status_code < 300 else 0
    log(f"orders DEMO_ criados: {no} ({ro.status_code})")
    if rc.status_code >= 300 or ro.status_code >= 300:
        log("Algum INSERT falhou — correr cleanup.py --commit para reverter.", "WARN")
    audit_log(ctx, "demo_data_seeded", "system", "seed-demo-data",
              {"clients": nc, "orders": no, "payment": "cash"})
    log(f"✅ Seed: {nc} clientes + {no} pedidos DEMO_. Reverter: cleanup.py --commit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
