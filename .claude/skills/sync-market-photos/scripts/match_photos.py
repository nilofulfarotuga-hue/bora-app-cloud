"""Propõe fotos para produtos needs_photo=true de uma loja, reutilizando fotos de um
donor (default mercadona-guarda) por search_normalized. Escreve _preview/photo_matches.csv.

DB-interno: sem scraping, sem preço. Não escreve em products.

Uso: python match_photos.py --store continente-guarda [--donor mercadona-guarda] [--limit N]
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import Ctx, log, require_market, rest_paginate


def build_donor_index(ctx: Ctx, donor: str) -> dict:
    rows = rest_paginate(
        ctx, f"products?restaurant_id=eq.{donor}&needs_photo=eq.false&photo_url=not.is.null"
             f"&select=search_normalized,photo_url")
    idx = {}
    for r in rows:
        k = (r.get("search_normalized") or "").strip().lower()
        if k and k not in idx and r.get("photo_url"):
            idx[k] = r["photo_url"]
    return idx


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--donor", default="mercadona-guarda")
    ap.add_argument("--limit", type=int, default=0, help="0 = todos")
    args = ap.parse_args()

    ctx = Ctx.load()
    ctx.require_knowledge()
    require_market(args.store)
    require_market(args.donor)

    log(f"A construir índice donor '{args.donor}'…")
    donor = build_donor_index(ctx, args.donor)
    log(f"Donor: {len(donor)} fotos indexadas por search_normalized.")

    targets = rest_paginate(
        ctx, f"products?restaurant_id=eq.{args.store}&needs_photo=eq.true"
             f"&select=id,name,search_normalized")
    if args.limit:
        targets = targets[: args.limit]
    log(f"Alvos em '{args.store}' com needs_photo=true: {len(targets)}")

    matched, unmatched = [], 0
    for t in targets:
        k = (t.get("search_normalized") or "").strip().lower()
        url = donor.get(k)
        if url:
            matched.append({"product_id": t["id"], "name": t.get("name", ""),
                            "candidate_url": url, "source": f"reuse:{args.donor}"})
        else:
            unmatched += 1

    out = Path("_preview"); out.mkdir(exist_ok=True)
    dest = out / "photo_matches.csv"
    with dest.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["product_id", "name", "candidate_url", "source"])
        w.writeheader()
        w.writerows(matched)
    log(f"{len(matched)} candidatos · {unmatched} sem match. CSV: {dest}")
    log("Próximo: apply_photos.py --store %s  (dry-run; --commit p/ gravar)" % args.store)
    return 0


if __name__ == "__main__":
    sys.exit(main())
