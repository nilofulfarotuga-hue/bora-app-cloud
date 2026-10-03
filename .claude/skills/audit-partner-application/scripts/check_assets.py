"""Verifica acessibilidade dos assets de um parceiro (HEAD HTTP 200).

Campos: photo_url (logo), hero_image_url (capa), owner_doc_url, activity_doc_url.
Importável (check_assets) + CLI.
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log

ASSET_FIELDS = ["photo_url", "hero_image_url", "owner_doc_url", "activity_doc_url"]


def check_assets(d: dict) -> dict:
    out = {}
    for f in ASSET_FIELDS:
        url = (d.get(f) or "").strip()
        if not url:
            out[f] = (None, "ausente")
            continue
        try:
            resp = requests.head(url, timeout=15, allow_redirects=True)
            if resp.status_code == 405:
                resp = requests.get(url, timeout=15, stream=True)
            out[f] = (url, resp.status_code)
        except Exception as e:  # noqa: BLE001
            out[f] = (url, f"erro: {e}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--restaurant-id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    r = ctx.rest("GET", f"restaurants?id=eq.{args.restaurant_id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"restaurante {args.restaurant_id} não encontrado.", "ERROR")
        return 1
    for f, (url, status) in check_assets(rows[0]).items():
        log(f"{'✅' if status == 200 else '⚠️'} {f}: {status}{'' if url else ' (sem URL)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
