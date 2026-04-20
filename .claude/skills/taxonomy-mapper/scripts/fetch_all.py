"""Fetch ALL 43.121 products from Supabase via anon key, page-by-page."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from supabase import create_client

URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
ANON = os.environ.get("SUPABASE_ANON_KEY") or (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0."
    "-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
)
OUT = Path(__file__).parent / "all_products.json"
PAGE = 1000


def log(m: str) -> None:
    print(m, file=sys.stderr, flush=True)


def main() -> None:
    sb = create_client(URL, ANON)
    collected: list[dict] = []
    offset = 0
    while True:
        resp = (
            sb.table("products")
            .select("id,name,category_root")
            .order("id")
            .range(offset, offset + PAGE - 1)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            break
        collected.extend(rows)
        log(f"[page] offset={offset} +{len(rows)} total={len(collected)}")
        if len(rows) < PAGE:
            break
        offset += PAGE
    # Normalise
    out = [
        {
            "id": r["id"],
            "name": r.get("name", "") or "",
            "category_root": r.get("category_root", ""),
            "taxonomy_section": None,
            "taxonomy_confidence": 0,
        }
        for r in collected
    ]
    OUT.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    log(f"[done] wrote {len(out)} -> {OUT}")
    print(json.dumps({"count": len(out)}))


if __name__ == "__main__":
    main()
