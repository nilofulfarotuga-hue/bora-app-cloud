"""Relatório de payouts semanais somando ledger_entries. READ-ONLY (sem execução).

Uso:
  python payouts.py                 # últimos 7 dias
  python payouts.py --days 14
  python payouts.py --since <ISO> --until <ISO>
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import sys
from collections import defaultdict
from pathlib import Path

from _shared import Ctx, log, REPO_ROOT, rest_paginate

TYPES = ["earning", "commission", "payout", "cash_adjustment"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--since")
    ap.add_argument("--until")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    now = dt.datetime.now(dt.timezone.utc)
    since = args.since or (now - dt.timedelta(days=args.days)).isoformat()
    until = args.until or now.isoformat()
    rows = rest_paginate(
        ctx, f"ledger_entries?select=user_id,user_type,type,amount,order_id,created_at"
             f"&created_at=gte.{since}&created_at=lt.{until}")
    log(f"ledger_entries no período: {len(rows)} ({since} → {until})")
    if not rows:
        log("Nada a reportar.")
        return 0

    # agrega por (user_type, user_id)
    agg: dict = defaultdict(lambda: {t: 0.0 for t in TYPES} | {"net": 0.0})
    for r in rows:
        key = (r.get("user_type") or "?", r.get("user_id") or "?")
        amt = float(r.get("amount") or 0)
        t = r.get("type")
        if t in TYPES:
            agg[key][t] += amt
        agg[key]["net"] += amt

    def section(utype: str):
        items = [(uid, v) for (ut, uid), v in agg.items() if ut == utype]
        if not items:
            return
        log(f"--- {utype.upper()} ({len(items)}) ---")
        for uid, v in sorted(items, key=lambda x: -x[1]["net"])[:50]:
            log(f"  {uid[:18]}: net €{v['net']:.2f} "
                f"(earning {v['earning']:.2f} · commission {v['commission']:.2f} · payout {v['payout']:.2f})")

    section("driver")
    section("restaurant")
    plat = sum(v["net"] for (ut, _), v in agg.items() if ut == "platform")
    log(f"--- PLATAFORMA (informativo): net €{plat:.2f} ---")

    out = REPO_ROOT / ".claude" / "skills" / "run-weekly-payouts" / "_preview"
    out.mkdir(exist_ok=True)
    tag = since[:10] + "_" + until[:10]
    with (out / f"payouts_{tag}.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["user_type", "user_id", "earning", "commission", "payout", "cash_adjustment", "net"])
        for (ut, uid), v in sorted(agg.items()):
            w.writerow([ut, uid, f"{v['earning']:.2f}", f"{v['commission']:.2f}",
                        f"{v['payout']:.2f}", f"{v['cash_adjustment']:.2f}", f"{v['net']:.2f}"])
    log(f"CSV: _preview/payouts_{tag}.csv · READ-ONLY (transferência real = humano/Stripe Connect).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
