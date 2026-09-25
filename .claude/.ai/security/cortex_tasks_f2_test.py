#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""F2 — validacao estrutural da migration cortex_tasks (sem DB).

Le o SQL e verifica os elementos obrigatorios do padrao cortex_*
(RLS sem policies, SECURITY DEFINER, _admin_op_guard, log_admin_action,
idempotente if-not-exists, DOWN documental) e que NAO toca dinheiro
(nenhuma pista de $ hint, nenhuma tabela/edge function protegida).
Read-only. Exit 0 = ok, 2 = bloquante.
"""
from __future__ import annotations
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = Path(__file__).resolve().parents[3]
F = ROOT / "supabase" / "migrations" / "20260809120000_PROPOSTA_cortex_tasks_f2.sql"

# Pistas de dinheiro (espelho de zonas_diff.py MONEY_SQL_HINTS) — nao devem
# aparecer NEM como nome de tabela/coluna NEM como funcao nesta migration.
MONEY_HINTS = ["pricing_", "create_order", "settlement", "payout", "refund",
               "wallet_", "enforce_financial", "finalize_", "commission",
               "service_fee", "bora_tokens"]
# "token" sozinho e demasiado largo (gen_random_uuid etc.) — nao incluir.

REQUIRED = [
    ("create table if not exists public.cortex_tasks", "create table idempotente"),
    ("enable row level security", "RLS enabled"),
    ("security definer", "RPCs SECURITY DEFINER"),
    ("_admin_op_guard", "admin guard"),
    ("log_admin_action", "auditoria admin"),
    ("for update of public.cortex_tasks skip locked", "claim atomica SKIP LOCKED"),
    ("cortex_enqueue", "RPC enqueue"),
    ("cortex_claim_next", "RPC claim_next"),
    ("cortex_finish", "RPC finish"),
    ("cortex_archive", "RPC archive (admin)"),
    ("cortex_list_tasks", "RPC list (admin)"),
    ("cortex_queue_stats", "RPC stats (admin)"),
    ("grant execute on function public.cortex_enqueue", "grant enqueue"),
    ("grant execute on function public.cortex_claim_next", "grant claim"),
    ("grant execute on function public.cortex_finish", "grant finish"),
    ("check (status in", "CHECK status enum"),
    ("check (zona in", "CHECK zona enum"),
    ("check (authority_level in", "CHECK authority_level"),
    ("DOWN (documental", "seccao DOWN documental"),
]

def main() -> int:
    if not F.exists():
        print(f"FAIL: migration nao encontrada: {F}")
        return 2
    sql = F.read_text(encoding="utf-8")
    low = sql.lower()

    pass_n = fail_n = 0
    print("=== F2 validacao estrutural: cortex_tasks ===")

    for needle, label in REQUIRED:
        if needle.lower() in low:
            pass_n += 1
            print(f"  PASS  {label}")
        else:
            fail_n += 1
            print(f"  FAIL  {label}  (nao encontrei: {needle!r})")

    # Pistas de dinheiro: so na seccao ativa (excluir comentarios DOWN).
    # Estrategia: remover linhas comentadas (--) e a seccao DOWN, depois
    # procurar hints no codigo ativo.
    active_lines = []
    in_down = False
    for line in sql.splitlines():
        s = line.strip()
        if s.lower().startswith("-- down (documental"):
            in_down = True
        if in_down:
            continue
        if s.startswith("--"):
            continue
        active_lines.append(line)
    active = "\n".join(active_lines).lower()

    money_hits = [h for h in MONEY_HINTS if h in active]
    if money_hits:
        fail_n += 1
        print(f"  FAIL  pistas de dinheiro no codigo ativo: {money_hits}")
    else:
        pass_n += 1
        print("  PASS  zero pistas de dinheiro no codigo ativo")

    # Nenhuma referencia a tabelas/edge functions protegidas (zone $).
    PROTECTED = ["pricing_service", "order_store", "errand_execution_sheet",
                 "dispatch-engine", "stripe-webhook", "finalize-order-from-intent",
                 "create-payment-intent", "create-mbway-payment-intent",
                 "reprocess-refund", "charge-extra", "/refund/"]
    prot_hits = [p for p in PROTECTED if p in low]
    if prot_hits:
        fail_n += 1
        print(f"  FAIL  referencia a zona protegida: {prot_hits}")
    else:
        pass_n += 1
        print("  PASS  sem referencia a zonas protegidas ($ codigo)")

    # DOWN nao deve conter DROP de tabelas $ alheias
    down = sql[sql.lower().find("-- down (documental"):]
    bad_drop = any(t in down.lower() for t in
                   ["drop table if exists public.orders", "drop table if exists public.wallets",
                    "drop table if exists public.bora_tokens", "drop table if exists public.ledger"])
    if bad_drop:
        fail_n += 1
        print("  FAIL  DOWN tenta DROPar tabela $ alheia")
    else:
        pass_n += 1
        print("  PASS  DOWN so menciona cortex_tasks (reversao propria)")

    print(f"=== Result: {pass_n} pass, {fail_n} fail ===")
    return 2 if fail_n else 0

if __name__ == "__main__":
    sys.exit(main())