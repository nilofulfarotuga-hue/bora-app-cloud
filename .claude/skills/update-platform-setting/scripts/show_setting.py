"""Mostra uma chave de platform_settings + chaves relacionadas (mesmo prefixo/categoria).

Uso: python show_setting.py --key reservation_prepayment_cents
"""
from __future__ import annotations

import argparse
import sys

from _shared import Ctx, log, is_blindada


def fetch(ctx: Ctx, key: str):
    r = ctx.rest("GET", f"platform_settings?key=eq.{key}&select=key,value,description,category",
                 ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    return rows[0] if rows else None


def related(ctx: Ctx, key: str, category):
    prefix = key.split("_")[0]
    q = f"platform_settings?key=like.{prefix}_*&select=key,value&order=key.asc"
    r = ctx.rest("GET", q, ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if category:
        rc = ctx.rest("GET", f"platform_settings?category=eq.{category}&select=key,value&order=key.asc",
                      ctx.service_role_key)
        if rc.status_code < 300:
            seen = {x["key"] for x in rows}
            rows += [x for x in rc.json() if x["key"] not in seen]
    return [x for x in rows if x["key"] != key]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    s = fetch(ctx, args.key)
    if not s:
        log(f"Chave '{args.key}' não existe em platform_settings.", "ERROR")
        return 1
    log(f"{s['key']} = {s['value']}  (categoria: {s.get('category')})")
    if s.get("description"):
        log(f"  descrição: {s['description']}")
    if is_blindada(args.key):
        log("  🔒 BLINDADA — alterar exige --i-know-what-im-doing.", "WARN")
    rel = related(ctx, args.key, s.get("category"))
    if rel:
        log(f"Chaves relacionadas ({len(rel)}):")
        for x in rel[:25]:
            log(f"  - {x['key']} = {x['value']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
