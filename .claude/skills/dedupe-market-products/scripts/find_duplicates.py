"""Agrupa produtos de uma loja por search_normalized e lista grupos com >1 (duplicados).

Escreve _preview/duplicates.csv (todas as linhas dos grupos duplicados). Não muta nada.

Uso: python find_duplicates.py --store continente-guarda
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

from _shared import Ctx, log, require_market, rest_paginate

FIELDS = ["id", "name", "search_normalized", "price", "photo_url", "needs_photo",
          "needs_review", "description", "is_available"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
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
    total_extra = sum(len(v) - 1 for v in dups.values())

    out = Path("_preview"); out.mkdir(exist_ok=True)
    dest = out / "duplicates.csv"
    with dest.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["group"] + FIELDS)
        w.writeheader()
        for k, v in dups.items():
            for r in v:
                w.writerow({"group": k, **{x: r.get(x) for x in FIELDS}})
    log(f"'{args.store}': {len(rows)} produtos · {len(dups)} grupos duplicados · "
        f"{total_extra} extra(s) candidatos a soft-delete.")
    log(f"CSV: {dest} · Próximo: merge_duplicates.py --store {args.store}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
