"""Faz merge de duplicados: mantém o mais completo, soft-delete dos restantes.

Dry-run por defeito (plano + backup). --commit aplica soft-delete (is_available=false +
needs_review=true). NUNCA hard delete. Backup CSV antes.

Uso:
  python merge_duplicates.py --store continente-guarda            # dry-run
  python merge_duplicates.py --store continente-guarda --commit
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

from _shared import Ctx, log, require_market, rest_paginate, audit_log

FIELDS = ["id", "name", "search_normalized", "price", "photo_url", "needs_photo",
          "needs_review", "description", "is_available"]


def score(p: dict) -> int:
    s = 0
    try:
        if p.get("price") not in (None, "") and float(p["price"]) > 0:
            s += 3
    except (TypeError, ValueError):
        pass
    if p.get("needs_photo") is False or (p.get("photo_url") or "").strip():
        s += 2
    if p.get("needs_review") is False:
        s += 2
    if (p.get("description") or "").strip():
        s += 1
    if p.get("is_available") is True:
        s += 1
    return s


def pick_winner(group: list[dict]) -> dict:
    # maior score; empate → id mais antigo (lexicográfico estável)
    return sorted(group, key=lambda p: (-score(p), str(p.get("id"))))[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    require_market(args.store)

    rows = rest_paginate(
        ctx, f"products?restaurant_id=eq.{args.store}&select={','.join(FIELDS)}")
    groups = defaultdict(list)
    for r in rows:
        k = (r.get("search_normalized") or "").strip().lower()
        if k:
            groups[k].append(r)
    dups = {k: v for k, v in groups.items() if len(v) > 1}
    if not dups:
        log(f"Sem duplicados em '{args.store}'. Nada a fazer.")
        return 0

    out = Path("_preview"); out.mkdir(exist_ok=True)
    # backup completo dos grupos
    with (out / f"backup_{args.store}.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["group"] + FIELDS)
        w.writeheader()
        for k, v in dups.items():
            for r in v:
                w.writerow({"group": k, **{x: r.get(x) for x in FIELDS}})

    plan, losers = [], []
    for k, v in dups.items():
        win = pick_winner(v)
        for p in v:
            if p["id"] != win["id"]:
                losers.append(p["id"])
                plan.append({"group": k, "winner_id": win["id"], "winner_score": score(win),
                             "loser_id": p["id"], "loser_score": score(p), "name": p.get("name", "")})
    with (out / "dedupe_plan.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["group", "winner_id", "winner_score",
                                          "loser_id", "loser_score", "name"])
        w.writeheader(); w.writerows(plan)
    log(f"'{args.store}': {len(dups)} grupos · {len(losers)} a soft-delete. "
        f"Plano: _preview/dedupe_plan.csv · Backup: _preview/backup_{args.store}.csv")

    if not args.commit:
        log("[DRY-RUN] nada escrito. Use --commit para soft-delete (is_available=false).")
        return 0

    done = 0
    for pid in losers:
        resp = ctx.rest("PATCH", f"products?id=eq.{pid}&restaurant_id=eq.{args.store}",
                        ctx.service_role_key, {"is_available": False, "needs_review": True})
        if resp.status_code < 300:
            done += 1
        else:
            log(f"soft-delete falhou {pid}: {resp.status_code}", "WARN")
    audit_log(ctx, "market_products_deduped", "market", args.store,
              {"groups": len(dups), "soft_deleted": done, "method": "is_available=false"})
    log(f"✅ {done} duplicado(s) soft-deleted em '{args.store}'. Auditado. (sem hard delete)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
