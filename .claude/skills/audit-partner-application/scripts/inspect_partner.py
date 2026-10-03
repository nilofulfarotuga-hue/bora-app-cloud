"""Relatório detalhado (dry-run) de 1 candidatura de parceiro.

Junta validate_docs + check_assets → _preview/partner_<id>.md (PT-BR). NÃO escreve DB.

Uso: python inspect_partner.py --restaurant-id <text-id>  |  --email <email>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from _shared import Ctx, log
import validate_docs
import check_assets


def _fetch(ctx: Ctx, rid: str | None, email: str | None) -> dict | None:
    q = f"id=eq.{rid}" if rid else f"email=eq.{email}"
    r = ctx.rest("GET", f"restaurants?{q}&select=*", ctx.service_role_key)
    rows = r.json() if r.status_code < 300 else []
    return rows[0] if rows else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--restaurant-id")
    ap.add_argument("--email")
    args = ap.parse_args()
    if not (args.restaurant_id or args.email):
        log("Indica --restaurant-id ou --email.", "ERROR")
        return 2

    ctx = Ctx.load()
    ctx.require_knowledge()
    d = _fetch(ctx, args.restaurant_id, args.email)
    if not d:
        log("Parceiro não encontrado.", "ERROR")
        return 1

    oks, warns, blocks = validate_docs.validate_partner(ctx, d)
    assets = check_assets.check_assets(d)
    assets_ok = all(s == 200 for _, s in assets.values() if _ is not None)
    suggestion = "REJEITAR" if blocks else ("APROVAR" if assets_ok else "REVER (assets)")

    lines = [f"# Auditoria parceiro — {d.get('name','?')} ({d['id']})", "",
             f"- categoria: **{d.get('category','?')}** · approval_status: **{d.get('approval_status','?')}**",
             f"- morada: {d.get('address','-')} · lat/lng: {d.get('lat')},{d.get('lng')}",
             f"- telefone: {d.get('phone','-')} · NIF: {d.get('nif','-')} · IBAN: {d.get('iban','-')}",
             f"- submetido: {d.get('submitted_at','-')}", ""]
    lines.append("## ✅ Válidos")
    lines += [f"- {x}" for x in oks] or ["- (nenhum)"]
    lines.append("## ⚠️ Avisos")
    lines += [f"- {x}" for x in warns] or ["- (nenhum)"]
    lines.append("## ❌ Bloqueantes")
    lines += [f"- {x}" for x in blocks] or ["- (nenhum)"]
    lines.append("## 🖼️ Assets")
    for f, (url, status) in assets.items():
        lines.append(f"- {'✅' if status == 200 else '⚠️'} {f}: {status}" + (f" — {url}" if url else ""))
    lines += ["", f"## Sugestão: **{suggestion}**", "",
              "Decidir: `python decide.py --restaurant-id %s --action approve|reject [--reason-code X] [--reason \"...\"] --commit`" % d["id"]]

    out = Path("_preview"); out.mkdir(exist_ok=True)
    dest = out / f"partner_{d['id']}.md"
    dest.write_text("\n".join(lines), encoding="utf-8")
    log(f"Relatório: {dest} · Sugestão: {suggestion}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
