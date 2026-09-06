"""Aplica os candidatos de foto (_preview/photo_matches.csv ou --csv externo).

Dry-run por defeito (valida HEAD 200, relatório). --commit grava photo_url+image_source+
needs_photo=false. NUNCA toca preço.

Uso:
  python apply_photos.py --store continente-guarda                 # dry-run
  python apply_photos.py --store continente-guarda --commit
  python apply_photos.py --store continente-guarda --csv fotos.csv --commit   # CSV externo (product_id,photo_url)
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import Ctx, log, require_market, head_ok, rate_sleep, audit_log, DEFAULT_RATE


def load_rows(csv_path: Path) -> list[dict]:
    with csv_path.open(encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--csv", help="CSV externo product_id,photo_url (default _preview/photo_matches.csv)")
    ap.add_argument("--rate", type=float, default=DEFAULT_RATE)
    ap.add_argument("--no-head", action="store_true", help="saltar validação HEAD (donor já validado)")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    require_market(args.store)

    csv_path = Path(args.csv) if args.csv else Path("_preview") / "photo_matches.csv"
    if not csv_path.exists():
        log(f"CSV não encontrado: {csv_path}. Corre match_photos.py primeiro.", "ERROR")
        return 1
    rows = load_rows(csv_path)
    if not rows:
        log("CSV vazio — nada a aplicar.")
        return 0

    valid, invalid = [], 0
    for r in rows:
        pid = (r.get("product_id") or "").strip()
        url = (r.get("candidate_url") or r.get("photo_url") or "").strip()
        src = (r.get("source") or "external_csv").strip()
        if not (pid and url):
            invalid += 1
            continue
        if not args.no_head:
            ok = head_ok(url)
            rate_sleep(args.rate)
            if not ok:
                log(f"⚠️ HEAD!=200, ignorado: {pid} {url}", "WARN")
                invalid += 1
                continue
        valid.append((pid, url, src))

    log(f"{len(valid)} válidos · {invalid} inválidos/saltados.")
    if not args.commit:
        log("[DRY-RUN] nada escrito. Use --commit para gravar photo_url.")
        return 0

    done = 0
    for pid, url, src in valid:
        # Salvaguarda: confirma que o produto é da loja indicada (não toca preço).
        patch = {"photo_url": url, "image_source": src, "needs_photo": False}
        resp = ctx.rest("PATCH", f"products?id=eq.{pid}&restaurant_id=eq.{args.store}",
                        ctx.service_role_key, patch)
        if resp.status_code >= 300:
            log(f"UPDATE falhou {pid}: {resp.status_code} {resp.text[:120]}", "WARN")
            continue
        done += 1
    audit_log(ctx, "market_photos_synced", "market", args.store,
              {"applied": done, "candidates": len(valid), "csv": str(csv_path)})
    log(f"✅ {done} foto(s) aplicadas em '{args.store}'. Auditado. (preço intocado)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
