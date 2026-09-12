"""Conta destinatários de um segmento (tokens ativos). READ-ONLY.

Uso: python preview_audience.py --segment {all|clients|drivers|partners}
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log

TABLE = {"clients": "client_push_tokens", "drivers": "driver_push_tokens",
         "partners": "partner_push_tokens"}


def count_active(ctx: Ctx, table: str) -> int:
    r = requests.get(f"{ctx.supabase_url}/rest/v1/{table}?active=eq.true&select=fcm_token",
                     timeout=30, headers={"Authorization": f"Bearer {ctx.service_role_key}",
                     "apikey": ctx.anon_key, "Prefer": "count=exact", "Range": "0-0"})
    cr = r.headers.get("Content-Range", "")
    return int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1].isdigit() else 0


def audience(ctx: Ctx, segment: str) -> int:
    if segment == "all":
        return sum(count_active(ctx, t) for t in TABLE.values())
    if segment in TABLE:
        return count_active(ctx, TABLE[segment])
    log(f"Segmento inválido: {segment} (usar all/clients/drivers/partners)", "ERROR")
    return -1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--segment", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    n = audience(ctx, args.segment)
    if n < 0:
        return 2
    log(f"Segmento '{args.segment}': {n} destinatário(s) com token ativo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
