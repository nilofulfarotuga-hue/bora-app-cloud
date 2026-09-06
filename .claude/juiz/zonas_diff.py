#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JUIZ — CAMADA 2, checagem (3): ZONA PROTEGIDA TOCADA? (determinístico)
======================================================================

Cruza o git diff do branch com os caminhos da Trava (Fase 1, ver
`.claude/.ai/knowledge/permanente/semantica/zonas-protegidas.md` e `.claude/HOOKS.md`).
A Trava JÁ bloqueia a edição em tempo real; esta checagem é o Juiz a CONFERIR o diff
final — rede de segurança caso algo tenha entrado por um caminho que a Trava não cobre
(ex.: ficheiro novo, rename, edição fora de hook).

Determinístico (git diff + glob). Exit: 0 = nenhuma zona tocada · 2 = zona protegida no diff.
É SINAL — a decisão de dinheiro continua a exigir "vai" do Danilo (🔴 Lista Vermelha).

Uso: python .claude/juiz/zonas_diff.py [--base REF] [--head REF] [--json]
"""
from __future__ import annotations
import argparse
import fnmatch
import json
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

# Espelha zonas-protegidas.md. Se a Trava mudar, atualizar aqui (via Bibliotecário).
PROTECTED_GLOBS = [
    "lib/services/pricing_service.dart",
    "lib/stores/order_store.dart",
    "lib/widgets/errand_execution_sheet.dart",
    "supabase/functions/dispatch-engine/*",
    "supabase/functions/stripe-webhook/*",
    "supabase/functions/finalize-order-from-intent/*",
    "supabase/functions/create-payment-intent/*",
    "supabase/functions/create-mbway-payment-intent/*",
    "supabase/functions/refund/*",
    "supabase/functions/reprocess-refund/*",
    "supabase/functions/charge-extra/*",
    ".claude/hooks/*",
    ".claude/settings.json",
    ".claude/settings.local.json",
]

# Pistas de dinheiro em migrations/SQL (DDL financeira). Sinaliza p/ olho humano.
MONEY_SQL_HINTS = ["pricing_", "create_order", "settlement", "payout", "refund",
                   "wallet_", "token", "enforce_financial", "finalize_", "commission",
                   "service_fee", "bora_tokens"]


def run_git(args: list[str]) -> str:
    out = subprocess.run(["git"] + args, capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    return out.stdout


def changed_paths(base: str, head: str | None) -> list[str]:
    args = ["diff", "--name-only", "-M", base]
    if head is not None:
        args.append(head)
    return [p for p in run_git(args).splitlines() if p.strip()]


def matches_protected(path: str) -> str | None:
    for g in PROTECTED_GLOBS:
        if fnmatch.fnmatch(path, g) or path == g:
            return g
    return None


def default_base() -> str:
    return run_git(["merge-base", "main", "HEAD"]).strip() or "HEAD"


def analyse(base: str, head: str | None) -> dict:
    paths = changed_paths(base, head)
    hits = []
    for p in paths:
        g = matches_protected(p)
        if g:
            hits.append({"file": p, "rule": g, "kind": "protected_code"})
    # migrations SQL com pistas de dinheiro
    money_sql = []
    for p in paths:
        if p.endswith(".sql") and ("migration" in p or "supabase" in p):
            low = p.lower()
            hint = next((h for h in MONEY_SQL_HINTS if h in low), None)
            if hint:
                money_sql.append({"file": p, "hint": hint})
    verdict = "PROTECTED_TOUCHED" if hits else ("REVIEW_SQL" if money_sql else "CLEAN")
    return {
        "verdict": verdict,
        "base": base, "head": head or "WORKING_TREE",
        "protected_hits": hits,
        "money_sql": money_sql,
        "exit": 2 if hits else 0,
    }


def render_human(r: dict) -> str:
    icon = "✅" if r["verdict"] == "CLEAN" else "❌" if r["protected_hits"] else "⚠️"
    out = [f"  JUIZ · CAMADA 2 (3) ZONAS PROTEGIDAS  →  {icon} {r['verdict']}"]
    if not r["protected_hits"] and not r["money_sql"]:
        out.append("  Nenhuma zona protegida no diff.")
    for h in r["protected_hits"]:
        out.append(f"  ❌ ZONA PROTEGIDA TOCADA: {h['file']}  (regra: {h['rule']})")
    for m in r["money_sql"]:
        out.append(f"  ⚠️ SQL com pista de dinheiro: {m['file']}  (termo: {m['hint']}) — 🔴 espera 'vai'.")
    if r["protected_hits"]:
        out.append("  VEREDITO: REJEITA — diff toca zona da Trava. Para e reporta ao Danilo.")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=None)
    ap.add_argument("--head", default=None)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    r = analyse(a.base or default_base(), a.head)
    print(json.dumps(r, ensure_ascii=False, indent=2) if a.json else render_human(r))
    return r["exit"]


if __name__ == "__main__":
    sys.exit(main())
