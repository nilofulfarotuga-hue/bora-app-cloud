"""Upload classified results to products_classify_staging via supabase-py."""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

from supabase import create_client

sys.path.insert(0, str(Path(__file__).parent))
import classify as C  # noqa: E402

URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
ANON = os.environ.get("SUPABASE_ANON_KEY") or (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0."
    "-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
)

HERE = Path(__file__).parent
INP = HERE / "all_products.json"
BATCH = 500


def log(m: str) -> None:
    print(m, file=sys.stderr, flush=True)


def main() -> None:
    products = json.loads(INP.read_text(encoding="utf-8"))
    log(f"[load] {len(products)} products")

    resolved = C.classify_products(products, force=True)
    log(f"[classify] {len(resolved)} results")

    rows = [
        {
            "id": str(p["id"]),
            "section": r.section,
            "conf": round(r.confidence, 2),
            "nr": r.needs_review,
        }
        for p, r in resolved
    ]

    sb = create_client(URL, ANON)

    # Wipe staging
    try:
        sb.table("products_classify_staging").delete().neq("id", "__none__").execute()
        log("[wipe] staging cleared")
    except Exception as e:
        log(f"[wipe] warn: {e}")

    total = 0
    t0 = time.time()
    for i in range(0, len(rows), BATCH):
        chunk = rows[i:i + BATCH]
        for retry in range(3):
            try:
                sb.table("products_classify_staging").insert(chunk).execute()
                total += len(chunk)
                break
            except Exception as e:
                log(f"[insert retry {retry}] i={i}: {e}")
                time.sleep(2)
        if i % 5000 == 0:
            dt = time.time() - t0
            log(f"[insert] {total}/{len(rows)}  ({total/max(dt,0.1):.0f}/s)")
    dt = time.time() - t0
    log(f"[done] {total} inserted in {dt:.1f}s ({total/max(dt,0.1):.0f}/s)")
    print(json.dumps({"uploaded": total, "duration_s": round(dt, 1)}))


if __name__ == "__main__":
    main()
