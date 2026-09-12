"""Atualiza preços do Continente via Product-Show + JSON-LD (3.5s/req).

SÓ continente-guarda. Resolve o preço a partir do URL do produto (campo `source` se for
http, ou CSV --urls product_id,url). Sem URL resolvível → SALTA (nunca inventa preço).
Dry-run por defeito; --commit grava price + last_updated. Escreve _preview/prices_*.csv.

Uso:
  python run_continente_update.py --limit 50            # dry-run amostra
  python run_continente_update.py --commit              # aplica
  python run_continente_update.py --urls urls.csv --commit
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sys
from pathlib import Path

import requests

from _shared import (Ctx, log, rate_sleep, audit_log, rest_paginate,
                     PRICE_SUPPORTED, PRICE_BLOCKED_ROBOTS, DEFAULT_RATE)

STORE = "continente-guarda"
LD_RE = re.compile(r'<script[^>]+application/ld\+json[^>]*>(.*?)</script>', re.S | re.I)


def resolve_price(url: str) -> float | None:
    """GET página + extrai offers.price do JSON-LD @type=Product."""
    try:
        r = requests.get(url, timeout=30, headers={"User-Agent": "Mozilla/5.0 BoraPriceBot"})
        if r.status_code != 200:
            return None
        for blob in LD_RE.findall(r.text):
            try:
                data = json.loads(blob)
            except json.JSONDecodeError:
                continue
            items = data if isinstance(data, list) else [data]
            for it in items:
                if isinstance(it, dict) and "Product" in str(it.get("@type", "")):
                    offers = it.get("offers") or {}
                    if isinstance(offers, list):
                        offers = offers[0] if offers else {}
                    price = offers.get("price")
                    if price is not None:
                        return float(str(price).replace(",", "."))
    except Exception as e:  # noqa: BLE001
        log(f"resolve_price erro ({url[:60]}): {e}", "WARN")
    return None


def load_url_map(path: str | None) -> dict:
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        return {r["product_id"]: r["url"] for r in csv.DictReader(f) if r.get("url")}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--urls", help="CSV product_id,url (opcional)")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--rate", type=float, default=DEFAULT_RATE)
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()
    if STORE not in PRICE_SUPPORTED:
        log("Continente não suportado?! abortar.", "ERROR")
        return 2
    log(f"Bloqueados por robots.txt (não suportados): {sorted(PRICE_BLOCKED_ROBOTS)}", "WARN")

    url_map = load_url_map(args.urls)
    rows = rest_paginate(ctx, f"products?restaurant_id=eq.{STORE}&select=id,name,price,source")
    if args.limit:
        rows = rows[: args.limit]
    log(f"Produtos Continente: {len(rows)} (a resolver preço; rate {args.rate}s)")

    before, after, skipped = [], [], 0
    for p in rows:
        pid = p["id"]
        url = url_map.get(pid) or (p.get("source") if str(p.get("source", "")).startswith("http") else None)
        if not url:
            skipped += 1
            continue
        new_price = resolve_price(url)
        rate_sleep(args.rate)
        if new_price is None or new_price <= 0:
            skipped += 1
            continue
        before.append({"product_id": pid, "name": p.get("name", ""), "price": p.get("price")})
        after.append({"product_id": pid, "name": p.get("name", ""), "price": new_price})

    out = Path("_preview"); out.mkdir(exist_ok=True)
    for fn, data in (("prices_before.csv", before), ("prices_after.csv", after)):
        with (out / fn).open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["product_id", "name", "price"])
            w.writeheader(); w.writerows(data)
    changed = sum(1 for b, a in zip(before, after) if (b["price"] or 0) != a["price"])
    log(f"Resolvidos: {len(after)} · alterados: {changed} · saltados (sem URL/preço): {skipped}")

    if not args.commit:
        log("[DRY-RUN] nada gravado. Vê _preview/prices_*.csv. Use --commit para aplicar.")
        return 0

    ts = dt.datetime.now(dt.timezone.utc).isoformat()
    done = 0
    for a in after:
        resp = ctx.rest("PATCH", f"products?id=eq.{a['product_id']}&restaurant_id=eq.{STORE}",
                        ctx.service_role_key, {"price": a["price"], "last_updated": ts})
        if resp.status_code < 300:
            done += 1
    audit_log(ctx, "market_prices_updated", "market", STORE,
              {"updated": done, "resolved": len(after), "skipped": skipped})
    log(f"✅ {done} preços Continente atualizados. Auditado. (só price+last_updated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
