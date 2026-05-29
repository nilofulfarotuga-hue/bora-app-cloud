"""Valida campos/documentos de um registo de parceiro (restaurants).

Reutiliza validadores NIF/IBAN de onboard-partner-restaurant (S1).
business_hours JSONB, lat/lng PT, categoria, licença INFARMED (condicional).

Uso CLI: python validate_docs.py --restaurant-id <text-id>
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

from _shared import Ctx, log

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
_spec = importlib.util.spec_from_file_location("rest_validate", _REST / "validate_info.py")
_rv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rv)  # type: ignore

REQUIRED = ["name", "address", "phone", "nif", "iban", "owner_doc_url", "photo_url",
            "hero_image_url", "category", "lat", "lng", "business_hours", "submitted_at"]
VALID_CATEGORIES = {"restaurant", "supermarket", "store", "pharmacy"}
HHMM = re.compile(r"^\d{2}:\d{2}$")
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def _validate_hours(bh) -> list[str]:
    errs = []
    if not isinstance(bh, dict):
        return ["business_hours não é objeto JSON"]
    for day in DAYS:
        if day not in bh:
            errs.append(f"business_hours sem dia '{day}'")
            continue
        slot = bh[day]
        if isinstance(slot, dict) and slot.get("closed") is True:
            continue
        for fld in ("open", "close"):
            v = (slot or {}).get(fld) if isinstance(slot, dict) else None
            if not (isinstance(v, str) and HHMM.match(v)):
                errs.append(f"business_hours.{day}.{fld} inválido (hh:mm): {v}")
    return errs


def column_exists(ctx: Ctx, table: str, column: str) -> bool:
    q = (f"information_schema.columns?table_schema=eq.public&table_name=eq.{table}"
         f"&column_name=eq.{column}&select=column_name")
    r = ctx.rest("GET", q, ctx.service_role_key)
    return r.status_code < 300 and bool(r.json())


def validate_partner(ctx: Ctx, d: dict) -> tuple[list[str], list[str], list[str]]:
    oks, warns, blocks = [], [], []
    for k in REQUIRED:
        v = d.get(k)
        if v is None or (isinstance(v, str) and not v.strip()):
            blocks.append(f"campo obrigatório vazio: {k}")
        else:
            oks.append(f"{k} presente")
    if d.get("nif"):
        ok = _rv.valid_nif(str(d["nif"]))
        (oks if ok else blocks).append(f"NIF {'válido' if ok else 'INVÁLIDO'}: {d['nif']}")
    if d.get("iban"):
        ok = _rv.valid_iban_pt(str(d["iban"]))
        (oks if ok else blocks).append(f"IBAN {'válido' if ok else 'INVÁLIDO (^PT+21)'}: {d['iban']}")
    cat = str(d.get("category", "")).lower()
    (oks if cat in VALID_CATEGORIES else blocks).append(
        f"category {'válida' if cat in VALID_CATEGORIES else 'INVÁLIDA'}: {cat}")
    for e in _validate_hours(d.get("business_hours")):
        blocks.append(e)
    lat, lng = d.get("lat"), d.get("lng")
    if lat is not None and not (36.9 <= float(lat) <= 42.2):
        blocks.append(f"lat fora do continente PT: {lat}")
    if lng is not None and not (-9.6 <= float(lng) <= -6.2):
        blocks.append(f"lng fora do continente PT: {lng}")
    # licença INFARMED — condicional (coluna pode não existir)
    if cat == "pharmacy":
        if column_exists(ctx, "restaurants", "licenca_infarmed"):
            (oks if str(d.get("licenca_infarmed") or "").strip() else blocks).append(
                "licenca_infarmed " + ("presente" if d.get("licenca_infarmed") else "EM FALTA"))
        else:
            warns.append("PENDÊNCIA: coluna licenca_infarmed não existe — validar manualmente "
                         "(considerar migration ou tabela pharmacy_licenses).")
    if d.get("approval_status") and d["approval_status"] != "pending":
        warns.append(f"approval_status atual = {d['approval_status']} (não 'pending').")
    return oks, warns, blocks


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--restaurant-id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    r = ctx.rest("GET", f"restaurants?id=eq.{args.restaurant_id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"restaurante {args.restaurant_id} não encontrado.", "ERROR")
        return 1
    oks, warns, blocks = validate_partner(ctx, rows[0])
    for b in blocks:
        log(f"❌ {b}", "ERROR")
    for w in warns:
        log(f"⚠️ {w}", "WARN")
    log(f"{len(oks)} OK · {len(warns)} avisos · {len(blocks)} bloqueantes")
    return 1 if blocks else 0


if __name__ == "__main__":
    sys.exit(main())
