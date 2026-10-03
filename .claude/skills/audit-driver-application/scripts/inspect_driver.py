"""Relatório detalhado (dry-run) de 1 candidatura de estafeta.

Junta validate_docs + check_photos e escreve _preview/driver_<id>.md (PT-BR).
NÃO escreve na DB.

Uso: python inspect_driver.py --driver-id <uuid>   |   --email <email>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from _shared import Ctx, log
import validate_docs
import check_photos


def _fetch(ctx: Ctx, driver_id: str | None, email: str | None) -> dict | None:
    q = f"id=eq.{driver_id}" if driver_id else f"email=eq.{email}"
    r = ctx.rest("GET", f"drivers?{q}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    return rows[0] if rows else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver-id")
    ap.add_argument("--email")
    args = ap.parse_args()
    if not (args.driver_id or args.email):
        log("Indica --driver-id ou --email.", "ERROR")
        return 2

    ctx = Ctx.load()
    ctx.require_knowledge()
    d = _fetch(ctx, args.driver_id, args.email)
    if not d:
        log("Estafeta não encontrado.", "ERROR")
        return 1

    oks, warns, blocks = validate_docs.validate_driver(d)
    photos = check_photos.check_photos(d)
    photos_ok = all(s == 200 for _, s in photos.values() if _ is not None)

    suggestion = "REJEITAR" if blocks else ("APROVAR" if photos_ok else "REVER (fotos)")
    lines = [f"# Auditoria estafeta — {d.get('name','?')} ({d['id']})", "",
             f"- approval_status: **{d.get('approval_status','?')}** · submetido: {d.get('submitted_at','?')}",
             f"- telefone: {d.get('phone','-')} · NIF: {d.get('nif','-')} · IBAN: {d.get('iban','-')}",
             f"- veículo: {d.get('vehicle_type','-')} · matrícula: {d.get('license_plate','-')}",
             f"- morada: {d.get('address','-')} · consentimento: {d.get('consent_accepted_at','-')}", ""]
    lines.append("## ✅ Válidos")
    lines += [f"- {x}" for x in oks] or ["- (nenhum)"]
    lines.append("## ⚠️ Avisos")
    lines += [f"- {x}" for x in warns] or ["- (nenhum)"]
    lines.append("## ❌ Bloqueantes")
    lines += [f"- {x}" for x in blocks] or ["- (nenhum)"]
    lines.append("## 📸 Fotos / documentos")
    for f, (url, status) in photos.items():
        lines.append(f"- {'✅' if status == 200 else '⚠️'} {f}: {status}" + (f" — {url}" if url else ""))
    lines += ["", f"## Sugestão: **{suggestion}**", "",
              "Decidir: `python decide.py --driver-id %s --action approve|reject [--reason-code X] [--reason \"...\"] --commit`" % d["id"]]

    out = Path("_preview"); out.mkdir(exist_ok=True)
    dest = out / f"driver_{d['id']}.md"
    dest.write_text("\n".join(lines), encoding="utf-8")
    log(f"Relatório: {dest} · Sugestão: {suggestion}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
