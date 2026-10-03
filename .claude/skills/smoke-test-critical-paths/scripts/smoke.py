"""Smoke test read-only dos caminhos críticos. ZERO escrita.

- Edge Functions vivas: OPTIONS (preflight) — não executa lógica.
- RPCs críticos presentes: information_schema.routines.
- Tabelas-chave acessíveis: count=exact.
- pg_cron/realtime: info (verificar via MCP/app).

Uso: python smoke.py [--json]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import requests

from _shared import Ctx, log

EDGE_FNS = ["dispatch-engine", "create-payment-intent", "stripe-webhook",
            "create-mbway-payment-intent", "refund", "notify-driver", "notify-partner"]
RPCS = ["is_admin", "pricing_calculate"]
TABLES = ["orders", "drivers", "restaurants", "products", "platform_settings", "support_skills"]


def edge_alive(ctx: Ctx, fn: str) -> bool:
    try:
        r = requests.options(f"{ctx.supabase_url}/functions/v1/{fn}", timeout=15,
                             headers={"Access-Control-Request-Method": "POST",
                                      "Origin": "https://smoke.local"})
        return r.status_code in (200, 204)
    except Exception:  # noqa: BLE001
        return False


def rpc_exists(ctx: Ctx, names: list[str]) -> dict:
    inlist = ",".join(names)
    r = ctx.rest("GET", f"information_schema.routines?routine_schema=eq.public"
                        f"&routine_name=in.({inlist})&select=routine_name", ctx.service_role_key)
    present = {x["routine_name"] for x in (r.json() if r.status_code < 300 else [])}
    return {n: (n in present) for n in names}


def table_ok(ctx: Ctx, t: str) -> bool:
    try:
        r = requests.get(f"{ctx.supabase_url}/rest/v1/{t}?select=*", timeout=20,
                         headers={"Authorization": f"Bearer {ctx.service_role_key}",
                                  "apikey": ctx.anon_key, "Prefer": "count=exact", "Range": "0-0"})
        return r.status_code < 300
    except Exception:  # noqa: BLE001
        return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    results = []
    for fn in EDGE_FNS:
        results.append(("Edge Fn", fn, edge_alive(ctx, fn)))
    for name, ok in rpc_exists(ctx, RPCS).items():
        results.append(("RPC", name, ok))
    for t in TABLES:
        results.append(("Tabela", t, table_ok(ctx, t)))

    crit_fail = [f"{c}:{n}" for c, n, ok in results if not ok]

    def icon(ok):
        return "✅" if ok else "❌"

    if args.json:
        print(json.dumps([{"kind": c, "name": n, "ok": ok} for c, n, ok in results],
                         ensure_ascii=False, indent=2))
    else:
        log("=== Smoke test (read-only) ===")
        for c, n, ok in results:
            log(f"{icon(ok)} [{c}] {n}")
        log("ℹ️ [Realtime] orders_channel + public:drivers — verificar na app.")
        log("ℹ️ [pg_cron] verificar via MCP: SELECT jobname, active FROM cron.job;")
        log(f"Resultado: {'❌ FALHAS: ' + ', '.join(crit_fail) if crit_fail else '✅ tudo vivo'}")

    lines = ["# Smoke test — caminhos críticos", ""]
    lines += [f"- {icon(ok)} **{c}** {n}" for c, n, ok in results]
    lines += ["- ℹ️ Realtime: orders_channel, public:drivers (app)",
              "- ℹ️ pg_cron: verificar via MCP", "",
              f"**Resultado:** {'❌ ' + ', '.join(crit_fail) if crit_fail else '✅ sem falhas'}"]
    out = Path("_preview"); out.mkdir(exist_ok=True)
    (out / "smoke.md").write_text("\n".join(lines), encoding="utf-8")
    return 1 if crit_fail else 0


if __name__ == "__main__":
    sys.exit(main())
