#!/usr/bin/env bash
# ============================================================================
# TRAVA BORA — protege-banco.sh  [CÓPIA PROPOSTA — FIX python-ausente]
# ----------------------------------------------------------------------------
# ÚNICA mudança vs. .claude/hooks/protege-banco.sh (bloco 3, deteção de deploy):
#   ANTES:  if printf '%s' "$TOOLNAME" | grep -Eiq 'deploy_edge_function' || ...
#   DEPOIS: if raw 'deploy_edge_function' || ...
# Motivo: TOOLNAME é construído via `python`; quando o `python` não está no PATH
# do bash do hook, TOOLNAME fica vazio e a regra de deploy de edge function
# protegida (stripe-webhook/dispatch-engine/...) FALHAVA-ABERTO (deixava passar).
# `raw` lê o payload cru (independente de python) e resolve a falha.
# Tudo o resto é idêntico ao original.
# ============================================================================
set +e

payload=$(cat)

# Junta tool_name + campos de texto relevantes (command/query/name/sql/entrypoint)
T=$(printf '%s' "$payload" | python -c "import sys,json
try:
    d=json.load(sys.stdin); ti=d.get('tool_input',{}); parts=[d.get('tool_name','')]
    for k in ('command','query','name','sql','entrypoint'):
        v=ti.get(k)
        if isinstance(v,str): parts.append(v)
    print('\n'.join(parts))
except Exception:
    print('')" 2>/dev/null)
[ -z "$T" ] && T="$payload"   # fail-safe

TOOLNAME=$(printf '%s' "$payload" | python -c "import sys,json
try: print(json.load(sys.stdin).get('tool_name',''))
except Exception: print('')" 2>/dev/null)

has() { printf '%s' "$T" | grep -Eiq "$1"; }
raw() { printf '%s' "$payload" | grep -Eiq "$1"; }

deny() {
  echo "🔒 TRAVA BORA — operação BLOQUEADA: $1" >&2
  echo "Mexe em dinheiro (funções/tabelas/edge functions financeiras) ou é destrutiva." >&2
  echo "Desativar só à mão pelo Danilo, fora do agente. Ver .claude/HOOKS.md." >&2
  exit 2
}

MONEYFN='enforce_financial_immutability|create_order|apply_order_financial_split|quote_order_pricing|pricing_calculate|pricing_calculate_errand|compute_refund_split|_enforce_refund_cap|wallet_credit_refund_split|wallet_credit_refund_full|wallet_debit_for_order|wallet_debit_cancel_fee|wallet_credit_generic|wallet_apply_post_delivery_adjustment|add_tokens|consume_tokens|mark_token_failed|fn_award_tokens_on_delivery|trg_award_tokens_on_delivery|driver_convert_tokens|client_redeem_promo_tokens|finalize_errand_purchase|finalize_storeshopping_purchase|finalize_storeshopping_purchase_v2|compute_partner_weekly_settlement|compute_driver_settlement|compute_provider_weekly_payout|create_payout|auto_payout_pending'
FINTABLE='orders|wallets|ledger|ledger_entries|bora_tokens|wallet_transactions|tvde_driver_balances|driver_balances|order_financials|order_financial_transactions|driver_weekly_settlements|partner_weekly_settlements|appointment_payouts|partner_reservation_payouts|pending_charges'
PROTSLUG='stripe-webhook|dispatch-engine|finalize-order-from-intent|create-payment-intent|create-mbway-payment-intent|reprocess-refund|charge-extra|(^|[^-])refund'

# ---- 1) Git destrutivo (SEMPRE) ------------------------------------------
has 'git[[:space:]]+reset[[:space:]]+--hard' && deny "git reset --hard"
if has 'git[[:space:]]+push'; then
  has '(--force|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$))' && deny "git push --force / -f"
fi

# ---- 2) supabase db reset (SEMPRE) ---------------------------------------
has 'supabase[[:space:]]+db[[:space:]]+reset' && deny "supabase db reset (destrói a base)"

# ---- 3) Deploy de edge function protegida --------------------------------
# FIX: usa `raw` (payload cru) em vez de $TOOLNAME (que depende de python).
if raw 'deploy_edge_function' || has 'supabase[[:space:]]+functions[[:space:]]+deploy'; then
  has "($PROTSLUG)" && deny "deploy/redeploy de edge function protegida"
fi

# ---- Contexto SQL? (só então aplicam-se as regras DDL) --------------------
IS_SQL_CTX=0
raw '(execute_sql|apply_migration|__[Ss]upabase|"[Ss]upabase|/[Ss]upabase)' && IS_SQL_CTX=1
has 'psql|supabase[[:space:]]+db|PGPASSWORD|postgres://|pg_dump|pg_restore' && IS_SQL_CTX=1

if [ "$IS_SQL_CTX" = "1" ]; then
  # 4) DDL sobre função/trigger de dinheiro
  if has '\b(create[[:space:]]+or[[:space:]]+replace|drop|alter)\b' && has "\b($MONEYFN)\b"; then
    deny "DDL (CREATE OR REPLACE/DROP/ALTER) sobre função/trigger de dinheiro"
  fi
  # 5) DROP/TRUNCATE de tabela financeira
  if has '\b(drop|truncate)\b' && has "\b($FINTABLE)\b"; then
    deny "DROP/TRUNCATE de tabela financeira"
  fi
  # 6) DISABLE RLS em tabela financeira
  if has 'disable[[:space:]]+row[[:space:]]+level[[:space:]]+security' && has "\b($FINTABLE)\b"; then
    deny "ALTER ... DISABLE ROW LEVEL SECURITY em tabela financeira"
  fi
fi

# Nada bateu -> deixa passar (SELECT, migration normal, git push normal, etc.)
exit 0
