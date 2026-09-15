"""Verifica presença e acessibilidade das fotos de um estafeta (HEAD HTTP 200).

URLs verificadas: document_photo_url, vehicle_photo_url, registration_selfie_url,
vehicle_doc_url, photo_url. Importável (check_photos) + CLI.
"""
from __future__ import annotations

import argparse
import sys

import requests

from _shared import Ctx, log

PHOTO_FIELDS = ["registration_selfie_url", "document_photo_url", "vehicle_photo_url",
                "vehicle_doc_url", "photo_url"]


def check_photos(d: dict) -> dict:
    """{campo: (url, status|erro)}. status int (200 OK) ou string de erro."""
    out = {}
    for f in PHOTO_FIELDS:
        url = (d.get(f) or "").strip()
        if not url:
            out[f] = (None, "ausente")
            continue
        try:
            resp = requests.head(url, timeout=15, allow_redirects=True)
            if resp.status_code == 405:  # alguns storages não suportam HEAD
                resp = requests.get(url, timeout=15, stream=True)
            out[f] = (url, resp.status_code)
        except Exception as e:  # noqa: BLE001
            out[f] = (url, f"erro: {e}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver-id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    r = ctx.rest("GET", f"drivers?id=eq.{args.driver_id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"driver {args.driver_id} não encontrado.", "ERROR")
        return 1
    for f, (url, status) in check_photos(rows[0]).items():
        ok = status == 200
        log(f"{'✅' if ok else '⚠️'} {f}: {status}{'' if url else ' (sem URL)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
