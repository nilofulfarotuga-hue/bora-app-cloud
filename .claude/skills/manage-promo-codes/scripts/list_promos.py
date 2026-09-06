"""Lista promo_codes (ativos/expirados). READ-ONLY (service_role).

Uso: python list_promos.py [--active-only]
"""
from __future__ import annotations

import argparse
import sys

from _shared import Ctx, log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--active-only", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    q = ("promo_codes?select=code,type,value_cents,value_pct,max_uses,uses_count,"
         "min_order_cents,valid_until,is_active&order=created_at.desc&limit=200")
    if args.active_only:
        q += "&is_active=eq.true"
    r = ctx.rest("GET", q, ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log("Sem promo codes.")
        return 0
    log(f"{len(rows)} promo code(s):")
    for p in rows:
        val = f"{p['value_pct']}%" if p.get("value_pct") else f"€{(p.get('value_cents') or 0)/100:.2f}"
        st = "ativo" if p.get("is_active") else "inativo"
        log(f"  - {p['code']} [{p['type']}] {val} · usos {p.get('uses_count',0)}/{p.get('max_uses','∞')} "
            f"· min €{(p.get('min_order_cents') or 0)/100:.2f} · até {p.get('valid_until','-')} · {st}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
