"""Auditoria read-only de prontidão para lançamento.

Agrega contagens via PostgREST (Prefer: count=exact) e classifica ✅/⚠️/❌.
Não escreve em nenhuma tabela.

Uso: python checklist.py [--json]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

import requests

from _shared import Ctx, log

CRITICAL_SETTINGS = ["delivery_base_fee_cents", "driver_base_fee_cents", "max_cash_amount_cents",
                     "dispatch_offer_timeout_seconds", "partner_visible_commission_pct",
                     "token_value_cents_x100", "non_partner_markup_pct"]


def count(ctx: Ctx, path: str) -> int:
    """Total de linhas via Content-Range (Range 0-0 → não traz dados)."""
    url = f"{ctx.supabase_url}/rest/v1/{path}"
    r = requests.get(url, timeout=60, headers={
        "Authorization": f"Bearer {ctx.service_role_key}", "apikey": ctx.anon_key,
        "Prefer": "count=exact", "Range-Unit": "items", "Range": "0-0"})
    cr = r.headers.get("Content-Range", "")  # ex.: 0-0/1234  ou  */0
    if "/" in cr:
        tot = cr.split("/")[-1]
        return int(tot) if tot.isdigit() else 0
    try:
        return len(r.json())
    except Exception:  # noqa: BLE001
        return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    week_ago = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=7)).isoformat()
    results = []  # (categoria, métrica, valor, nível)

    drivers_pending = count(ctx, "drivers?approval_status=eq.pending&select=id")
    results.append(("Estafetas", "candidaturas pendentes", drivers_pending,
                    "warn" if drivers_pending else "ok"))

    partners_pending = count(ctx, "restaurants?approval_status=eq.pending&select=id")
    results.append(("Parceiros", "candidaturas pendentes", partners_pending,
                    "warn" if partners_pending else "ok"))

    no_price = count(ctx, "products?or=(price.is.null,price.eq.0)&select=id")
    results.append(("Catálogo", "produtos sem preço (null/0)", no_price,
                    "fail" if no_price else "ok"))

    no_image = count(ctx, "products?or=(photo_url.is.null,photo_url.eq.)&select=id")
    results.append(("Catálogo", "produtos sem imagem", no_image,
                    "warn" if no_image else "ok"))

    # settings críticos
    r = ctx.rest("GET", "platform_settings?select=key,value&key=in.(%s)" % ",".join(CRITICAL_SETTINGS),
                 ctx.service_role_key)
    present = {x["key"]: x["value"] for x in (r.json() if r.status_code < 300 else [])}
    missing = [k for k in CRITICAL_SETTINGS if k not in present or present[k] is None]
    results.append(("Config", "settings críticos presentes",
                    f"{len(CRITICAL_SETTINGS) - len(missing)}/{len(CRITICAL_SETTINGS)}",
                    "fail" if missing else "ok"))

    audit_recent = count(ctx, f"admin_audit_log?created_at=gte.{week_ago}&select=id")
    results.append(("Auditoria", "eventos admin (7 dias)", audit_recent, "info"))

    results.append(("Edge Fns", "baseline 44 (S2) — verificar via MCP list_edge_functions",
                    "N/A via REST", "info"))

    icon = {"ok": "✅", "warn": "⚠️", "fail": "❌", "info": "ℹ️"}
    has_fail = any(lvl == "fail" for *_, lvl in results)

    if args.json:
        print(json.dumps([{"categoria": c, "metrica": m, "valor": v, "nivel": lvl}
                          for c, m, v, lvl in results], ensure_ascii=False, indent=2))
    else:
        log("=== Pré-Launch Checklist ===")
        for c, m, v, lvl in results:
            log(f"{icon[lvl]} [{c}] {m}: {v}")
        if missing:
            log(f"   settings em falta: {missing}", "WARN")
        log(f"Resultado global: {'❌ há bloqueantes' if has_fail else '✅ sem bloqueantes'}")

    lines = ["# Pré-Launch Checklist", "",
             f"_Gerado: {dt.datetime.now(dt.timezone.utc).isoformat()}_", ""]
    for c, m, v, lvl in results:
        lines.append(f"- {icon[lvl]} **{c}** — {m}: `{v}`")
    if missing:
        lines += ["", f"> settings críticos em falta: {missing}"]
    lines += ["", f"**Global:** {'❌ há bloqueantes' if has_fail else '✅ sem bloqueantes'}"]
    out = Path("_preview"); out.mkdir(exist_ok=True)
    (out / "checklist.md").write_text("\n".join(lines), encoding="utf-8")

    return 1 if has_fail else 0


if __name__ == "__main__":
    sys.exit(main())
