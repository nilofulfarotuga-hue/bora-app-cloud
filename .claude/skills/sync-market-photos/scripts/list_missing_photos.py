"""Lista contagem de produtos com needs_photo=true por loja de mercado.

Uso: python list_missing_photos.py
"""
from __future__ import annotations

import sys

import requests

from _shared import Ctx, log, MARKET_STORES


def count(ctx: Ctx, path: str) -> int:
    url = f"{ctx.supabase_url}/rest/v1/{path}"
    r = requests.get(url, timeout=60, headers={
        "Authorization": f"Bearer {ctx.service_role_key}", "apikey": ctx.anon_key,
        "Prefer": "count=exact", "Range-Unit": "items", "Range": "0-0"})
    cr = r.headers.get("Content-Range", "")
    return int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1].isdigit() else 0


def main() -> int:
    ctx = Ctx.load()
    ctx.require_knowledge()
    total = 0
    log("needs_photo=true por loja de mercado:")
    for store in MARKET_STORES:
        n = count(ctx, f"products?restaurant_id=eq.{store}&needs_photo=eq.true&select=id")
        total += n
        if n:
            log(f"  - {store}: {n}")
    log(f"Total mercados: {total}. Próximo: match_photos.py --store <loja>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
