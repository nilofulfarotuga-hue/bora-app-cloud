"""Valida documentos/campos de um registo de estafeta.

Reutiliza os validadores NIF/IBAN/telefone de onboard-partner-restaurant (S1).
Devolve (oks, warns, blocks): listas de strings.

Uso CLI: python validate_docs.py --driver-id <uuid>   (faz fetch e valida)
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

from _shared import Ctx, log

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
_spec = importlib.util.spec_from_file_location("rest_validate", _REST / "validate_info.py")
_rv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rv)  # type: ignore

REQUIRED = ["name", "phone", "nif", "iban", "document_number", "document_photo_url",
            "vehicle_photo_url", "registration_selfie_url", "address",
            "consent_accepted_at", "submitted_at"]


def validate_driver(d: dict) -> tuple[list[str], list[str], list[str]]:
    oks, warns, blocks = [], [], []
    for k in REQUIRED:
        if not str(d.get(k) or "").strip():
            blocks.append(f"campo obrigatório vazio: {k}")
        else:
            oks.append(f"{k} presente")
    if d.get("nif"):
        (oks if _rv.valid_nif(str(d["nif"])) else blocks).append(
            f"NIF {'válido' if _rv.valid_nif(str(d['nif'])) else 'INVÁLIDO'}: {d['nif']}")
    if d.get("iban"):
        ok = _rv.valid_iban_pt(str(d["iban"]))
        (oks if ok else blocks).append(f"IBAN {'válido' if ok else 'INVÁLIDO (^PT+21)'}: {d['iban']}")
    if d.get("phone"):
        ok = bool(_rv.PHONE_PT_RE.match(str(d["phone"]).replace(" ", "")))
        (oks if ok else blocks).append(f"telefone {'válido' if ok else 'INVÁLIDO'}: {d['phone']}")
    # Idade: nº de CC não codifica data de nascimento → não verificável aqui.
    warns.append("idade NÃO verificável pelo nº de CC — confirmar manualmente (≥18).")
    if d.get("approval_status") and d["approval_status"] != "pending":
        warns.append(f"approval_status atual = {d['approval_status']} (não 'pending').")
    return oks, warns, blocks


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver-id", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()
    r = ctx.rest("GET", f"drivers?id=eq.{args.driver_id}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    if not rows:
        log(f"driver {args.driver_id} não encontrado.", "ERROR")
        return 1
    oks, warns, blocks = validate_driver(rows[0])
    for b in blocks:
        log(f"❌ {b}", "ERROR")
    for w in warns:
        log(f"⚠️ {w}", "WARN")
    log(f"{len(oks)} OK · {len(warns)} avisos · {len(blocks)} bloqueantes")
    return 1 if blocks else 0


if __name__ == "__main__":
    sys.exit(main())
