"""Lista candidaturas de estafeta pendentes (drivers.approval_status='pending').

Uso: python list_pending.py
"""
from __future__ import annotations

import sys

from _shared import Ctx, log


def main() -> int:
    ctx = Ctx.load()
    ctx.require_knowledge()
    sel = "id,name,phone,nif,approval_status,submitted_at"
    r = ctx.rest("GET",
                 f"drivers?approval_status=eq.pending&select={sel}&order=submitted_at.asc",
                 ctx.service_role_key)
    if r.status_code >= 300:
        log(f"erro ao listar: {r.status_code} {r.text[:160]}", "ERROR")
        return 1
    rows = r.json()
    if not rows:
        log("Sem candidaturas de estafeta pendentes.")
        return 0
    log(f"{len(rows)} candidatura(s) pendente(s):")
    for d in rows:
        log(f"  - {d['id']} | {d.get('name','?')} | {d.get('phone','?')} | submetido {d.get('submitted_at','?')}")
    log("Inspecionar: python inspect_driver.py --driver-id <uuid>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
