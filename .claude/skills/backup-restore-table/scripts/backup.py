"""Backup read-only de uma tabela → JSON em .claude/.ai/backups/. Sempre seguro.

Uso:
  python backup.py --table platform_settings
  python backup.py --table products --filter "restaurant_id=eq.lidl-guarda" --limit 5000
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import sys
from pathlib import Path

from _shared import Ctx, log, REPO_ROOT, rest_paginate

GZIP_THRESHOLD = 5_000_000  # bytes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", required=True)
    ap.add_argument("--filter", help="filtro PostgREST extra (ex.: 'category=eq.faq')")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    path = f"{args.table}?select=*" + (f"&{args.filter}" if args.filter else "")
    rows = rest_paginate(ctx, path)
    if args.limit:
        rows = rows[: args.limit]
    log(f"{args.table}: {len(rows)} linhas exportadas.")

    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    out_dir = REPO_ROOT / ".claude" / ".ai" / "backups"
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = json.dumps({"table": args.table, "exported_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                          "count": len(rows), "rows": rows}, ensure_ascii=False, indent=2)
    blob = payload.encode("utf-8")
    if len(blob) > GZIP_THRESHOLD:
        dest = out_dir / f"{today}-{args.table}.json.gz"
        dest.write_bytes(gzip.compress(blob))
    else:
        dest = out_dir / f"{today}-{args.table}.json"
        dest.write_text(payload, encoding="utf-8")
    log(f"✅ Backup: {dest} ({len(blob)} bytes). Read-only — nada alterado na DB.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
