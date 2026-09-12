"""Lista reservas por restaurante/data/estado. READ-ONLY.

Uso:
  python list_reservations.py --restaurant <id> [--status confirmed] [--date 2026-05-30]
"""
from __future__ import annotations

import argparse
import sys

from _shared import Ctx, log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--restaurant")
    ap.add_argument("--status")
    ap.add_argument("--date", help="YYYY-MM-DD (filtra reserved_for nesse dia)")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    q = ("reservations?select=id,restaurant_id,client_name,people,reserved_for,status,"
         "prepayment_cents,is_walk_in,arrived_at&order=reserved_for.asc&limit=200")
    if args.restaurant:
        q += f"&restaurant_id=eq.{args.restaurant}"
    if args.status:
        q += f"&status=eq.{args.status}"
    if args.date:
        q += f"&reserved_for=gte.{args.date}T00:00:00&reserved_for=lt.{args.date}T23:59:59"
    r = ctx.rest("GET", q, ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log("Sem reservas para os filtros dados.")
        return 0
    log(f"{len(rows)} reserva(s):")
    for v in rows:
        log(f"  - {v['id']} | {v.get('client_name','?')} | {v.get('people')}p | {v.get('reserved_for')} "
            f"| {v.get('status')} | prépag {(v.get('prepayment_cents') or 0)/100:.2f}€"
            + (" | chegou" if v.get("arrived_at") else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
