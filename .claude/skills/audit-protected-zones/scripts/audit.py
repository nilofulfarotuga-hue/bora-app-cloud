"""Audita zonas protegidas (read-only) vs baseline. Correr antes de cada build.

Checks: sha256 de ficheiros-chave Flutter, triggers críticos (bora_tokens, financial_lock),
Edge Fns de pagamento vivas (OPTIONS). Compara com _baseline/protected_zones.json.

Uso:
  python audit.py --save-baseline    # grava baseline atual
  python audit.py                     # compara → ✅/⚠️/❌
  python audit.py --json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import requests

from _shared import Ctx, log, REPO_ROOT

KEY_FILES = [
    "lib/services/pricing_service.dart",
    "lib/config/app_theme.dart",
    "lib/config/app_colors.dart",
    "lib/dispatch/driver_capacity_service.dart",
    "lib/main.dart",
]
CRITICAL_TRIGGERS = ["trg_award_tokens_on_delivery", "orders_financial_lock"]
PAYMENT_FNS = ["create-payment-intent", "stripe-webhook", "refund"]
BASELINE = Path("_baseline") / "protected_zones.json"


def file_hashes() -> dict:
    out = {}
    for rel in KEY_FILES:
        p = REPO_ROOT / rel
        out[rel] = hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
    return out


def triggers_present(ctx: Ctx) -> dict:
    inlist = ",".join(CRITICAL_TRIGGERS)
    r = ctx.rest("GET", f"information_schema.triggers?trigger_name=in.({inlist})"
                        f"&select=trigger_name", ctx.service_role_key)
    present = {x["trigger_name"] for x in (r.json() if r.status_code < 300 else [])}
    return {t: (t in present) for t in CRITICAL_TRIGGERS}


def edge_alive(ctx: Ctx, fn: str) -> bool:
    try:
        r = requests.options(f"{ctx.supabase_url}/functions/v1/{fn}", timeout=15,
                             headers={"Access-Control-Request-Method": "POST", "Origin": "https://audit.local"})
        return r.status_code in (200, 204)
    except Exception:  # noqa: BLE001
        return False


def snapshot(ctx: Ctx) -> dict:
    return {"files": file_hashes(),
            "triggers": triggers_present(ctx),
            "payment_fns": {fn: edge_alive(ctx, fn) for fn in PAYMENT_FNS}}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--save-baseline", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    cur = snapshot(ctx)

    if args.save_baseline:
        BASELINE.parent.mkdir(exist_ok=True)
        BASELINE.write_text(json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"Baseline gravado: {BASELINE}")
        return 0

    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else None
    findings = []  # (nivel, msg)

    for rel, h in cur["files"].items():
        if h is None:
            findings.append(("fail", f"ficheiro-chave AUSENTE: {rel}"))
        elif base and base["files"].get(rel) and base["files"][rel] != h:
            findings.append(("fail", f"ALTERADO vs baseline: {rel}"))
        else:
            findings.append(("ok", f"intacto: {rel}"))
    for t, ok in cur["triggers"].items():
        findings.append(("ok" if ok else "fail", f"trigger {t}: {'presente' if ok else 'EM FALTA'}"))
    for fn, ok in cur["payment_fns"].items():
        findings.append(("ok" if ok else "fail", f"Edge Fn {fn}: {'viva' if ok else 'NÃO RESPONDE'}"))
    if not base:
        findings.append(("warn", "sem baseline — corre --save-baseline para fixar o estado bom."))
    findings.append(("info", "Edge Functions count (44): verificar via MCP list_edge_functions."))

    icon = {"ok": "✅", "warn": "⚠️", "fail": "❌", "info": "ℹ️"}
    has_fail = any(lvl == "fail" for lvl, _ in findings)

    if args.json:
        print(json.dumps([{"nivel": l, "msg": m} for l, m in findings], ensure_ascii=False, indent=2))
    else:
        log("=== Auditoria de zonas protegidas ===")
        for lvl, m in findings:
            log(f"{icon[lvl]} {m}")
        log(f"Resultado: {'❌ DRIFT detetado' if has_fail else '✅ zonas intactas'}")

    out = Path("_preview"); out.mkdir(exist_ok=True)
    (out / "protected_zones_audit.md").write_text(
        "# Auditoria de zonas protegidas\n\n" + "\n".join(f"- {icon[l]} {m}" for l, m in findings)
        + f"\n\n**Resultado:** {'❌ DRIFT' if has_fail else '✅ intactas'}\n", encoding="utf-8")
    return 1 if has_fail else 0


if __name__ == "__main__":
    sys.exit(main())
