"""Restore (UPSERT) de uma tabela a partir de um backup JSON. Dry-run default.

Tabelas financeiras exigem --i-know-what-im-doing + --reason. UPSERT (não apaga ausentes).

Uso:
  python restore.py --file backup.json --table platform_settings              # dry-run
  python restore.py --file backup.json --table platform_settings --commit
  python restore.py --file b.json --table bora_tokens --i-know-what-im-doing --reason "..." --commit
"""
from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

import requests

from _shared import Ctx, log, audit_log, FINANCIAL_TABLES


def load_backup(path: Path) -> list[dict]:
    raw = gzip.decompress(path.read_bytes()) if path.suffix == ".gz" else path.read_bytes()
    data = json.loads(raw.decode("utf-8"))
    return data.get("rows", data) if isinstance(data, dict) else data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--table", required=True)
    ap.add_argument("--i-know-what-im-doing", dest="iknow", action="store_true")
    ap.add_argument("--reason")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    if args.table in FINANCIAL_TABLES and not (args.iknow and args.reason):
        log(f"🔒 '{args.table}' é financeira. Restore exige --i-know-what-im-doing + --reason.", "ERROR")
        return 1

    p = Path(args.file)
    if not p.exists():
        log(f"Ficheiro não encontrado: {p}", "ERROR")
        return 1
    rows = load_backup(p)
    log(f"Backup: {len(rows)} linhas para '{args.table}'.")
    if rows:
        log(f"Amostra: {json.dumps(rows[0], ensure_ascii=False)[:160]}")

    if not args.commit:
        log("[DRY-RUN] nada escrito. UPSERT não apaga linhas ausentes. Use --commit.")
        return 0

    # UPSERT via PostgREST merge-duplicates
    url = f"{ctx.supabase_url}/rest/v1/{args.table}"
    done = 0
    for i in range(0, len(rows), 500):
        batch = rows[i:i + 500]
        r = requests.post(url, timeout=120, json=batch, headers={
            "Authorization": f"Bearer {ctx.service_role_key}", "apikey": ctx.anon_key,
            "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates,return=minimal"})
        if r.status_code < 300:
            done += len(batch)
        else:
            log(f"UPSERT batch {i} falhou: {r.status_code} {r.text[:160]}", "ERROR")
            break
    audit_log(ctx, "table_restored", "table", args.table,
              {"rows": done, "file": str(p), "financial": args.table in FINANCIAL_TABLES,
               "reason": args.reason})
    log(f"✅ Restore '{args.table}': {done}/{len(rows)} linhas (UPSERT). Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
