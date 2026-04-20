"""Fetch 1000 stratified products from Supabase via anon key.

Stratification strategy:
- 6 markets (prefixes: auc-, lidl-, inter-, cnt-, pd-, UUID/prod_)
- Ambiguous roots (Frescos, Gastronomia, Regional, Casa, Outros): 50-100 products
- Top popular roots proportionally (Mercearia, Bebidas, Congelados, etc.)
- Total target: ~1000 unique products
"""
from __future__ import annotations

import json
import os
import random
import sys
from pathlib import Path

from supabase import create_client

URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
ANON = os.environ.get("SUPABASE_ANON_KEY") or (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0."
    "-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
)

OUT = Path(__file__).parent / "sample_1000.json"

# Target distribution (≈1000 total)
# Popular roots - proportional to real DB volume
POPULAR_ROOTS = {
    "Mercearia": 150,
    "Bebidas": 120,
    "Congelados": 90,
    "Laticínios": 80,
    "Padaria": 70,
    "Higiene": 50,
    "Limpeza": 40,
    "Fruta": 40,
    "Legumes": 40,
    "Talho": 40,
    "Peixe": 30,
    "Bebé": 30,
    "Farmácia Básica": 20,
    "Bio": 20,
    "Carne": 30,
    "Higiene e Beleza": 20,
}

# Ambiguous roots - need disambiguation
AMBIGUOUS_ROOTS = {
    "Frescos": 40,
    "Gastronomia": 20,
    "Regional": 20,
    "Casa": 20,
    "Outros": 20,
    "Chupetas e Acessórios": 15,
    "Desporto e Viagem": 15,
    "Festa": 10,
}

MARKETS = {
    "auc-": 180,      # Auchan
    "lidl-": 180,     # Lidl
    "inter-": 150,    # Intermarché
    "cnt-": 150,      # Continente
    "pd-": 100,       # Pingo Doce
    "prod_": 80,      # generic prod_
    # UUID balance fills remaining
}


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def fetch_by_root(sb, root: str, limit: int) -> list[dict]:
    """Fetch up to `limit` products for a given category_root.

    PostgREST cannot do ORDER BY random(), so fetch up to 3x and sample.
    """
    fetch_n = min(limit * 5, 2000)
    try:
        resp = (
            sb.table("products")
            .select("id,name,category_root")
            .eq("category_root", root)
            .limit(fetch_n)
            .execute()
        )
        rows = resp.data or []
        if len(rows) <= limit:
            return rows
        return random.sample(rows, limit)
    except Exception as e:
        log(f"[WARN] fetch root={root}: {e}")
        return []


def fetch_by_prefix(sb, prefix: str, limit: int, exclude_ids: set[str]) -> list[dict]:
    """Fetch products whose id starts with `prefix`."""
    fetch_n = min(limit * 4, 2000)
    try:
        resp = (
            sb.table("products")
            .select("id,name,category_root")
            .like("id", f"{prefix}%")
            .limit(fetch_n)
            .execute()
        )
        rows = [r for r in (resp.data or []) if r["id"] not in exclude_ids]
        if len(rows) <= limit:
            return rows
        return random.sample(rows, limit)
    except Exception as e:
        log(f"[WARN] fetch prefix={prefix}: {e}")
        return []


def main() -> None:
    random.seed(42)
    sb = create_client(URL, ANON)

    collected: dict[str, dict] = {}  # id -> row

    # Phase 1: popular roots
    log("[phase1] popular roots")
    for root, n in POPULAR_ROOTS.items():
        rows = fetch_by_root(sb, root, n)
        for r in rows:
            collected[r["id"]] = r
        log(f"  {root}: +{len(rows)} (total={len(collected)})")

    # Phase 2: ambiguous roots
    log("[phase2] ambiguous roots")
    for root, n in AMBIGUOUS_ROOTS.items():
        rows = fetch_by_root(sb, root, n)
        for r in rows:
            collected[r["id"]] = r
        log(f"  {root}: +{len(rows)} (total={len(collected)})")

    # Phase 3: market prefix balancing
    log("[phase3] market prefixes")
    for prefix, target in MARKETS.items():
        existing = sum(1 for r in collected.values() if r["id"].startswith(prefix))
        need = max(0, target - existing)
        if need == 0:
            continue
        rows = fetch_by_prefix(sb, prefix, need, set(collected.keys()))
        for r in rows:
            collected[r["id"]] = r
        log(f"  {prefix}: +{len(rows)} (total={len(collected)})")

    # Phase 4: trim or pad to 1000
    items = list(collected.values())
    if len(items) > 1000:
        items = random.sample(items, 1000)
    elif len(items) < 1000:
        need = 1000 - len(items)
        log(f"[phase4] padding +{need}")
        resp = (
            sb.table("products")
            .select("id,name,category_root")
            .limit(3000)
            .execute()
        )
        pool = [r for r in (resp.data or []) if r["id"] not in collected]
        random.shuffle(pool)
        items.extend(pool[:need])

    # Normalise to classify.py shape
    out = [
        {
            "id": r["id"],
            "name": r.get("name", ""),
            "category_root": r.get("category_root", ""),
            "taxonomy_section": None,
            "taxonomy_confidence": 0,
        }
        for r in items
    ]

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    log(f"[done] wrote {len(out)} -> {OUT}")
    print(json.dumps({"count": len(out), "file": str(OUT)}))


if __name__ == "__main__":
    main()
