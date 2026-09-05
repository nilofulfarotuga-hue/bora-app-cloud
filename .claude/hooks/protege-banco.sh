#!/usr/bin/env bash
# ============================================================================
# TRAVA BORA — protege-banco.sh
# ----------------------------------------------------------------------------
# Hook PreToolUse (matcher: Bash | mcp__*[Ss]upabase*  — execute_sql /
# apply_migration / deploy_edge_function).
# Bloqueia (exit 2):
#   • DDL (CREATE OR REPLACE / DROP / ALTER) sobre FUNÇÕES/TRIGGERS de dinheiro
#   • DROP / TRUNCATE de TABELAS financeiras
#   • ALTER ... DISABLE ROW LEVEL SECURITY em tabelas financeiras
#   • deploy / redeploy de EDGE FUNCTIONS protegidas
#   • supabase db reset (destrói a base)
#   • git push --force / -f  e  git reset --hard
# DEIXA PASSAR: SELECT, migrations normais, git push normal, git reset --soft.
#
# Não executa nem altera nada. Só lê stdin e decide. Contrato: exit 2 = bloqueia.
# As regras de SQL só se aplicam em CONTEXTO SQL (MCP Supabase ou psql no Bash),
# para não bloquear mensagens de commit que contenham palavras como "drop".
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
T_OK=1
[ -z "$T" ] && { T="$payload"; T_OK=0; }   # fail-safe (JSON ilegivel)

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
FINTABLE='orders|wallets|ledger|ledger_entries|bora_tokens|wallet_transactions|tvde_driver_balances|driver_balances|order_financials|order_financial_transactions|driver_weekly_settlements|partner_weekly_settlements|appointment_payouts|partner_reservation_payouts|pending_charges|cortex_tasks|cortex_task_messages|cortex_task_consensus_meta|llm_call_log|agent_events|worktree_registry'
PROTSLUG='stripe-webhook|dispatch-engine|finalize-order-from-intent|create-payment-intent|create-mbway-payment-intent|reprocess-refund|charge-extra|(^|[^-])refund'

# ---- 1) Git destrutivo (SEMPRE) ------------------------------------------
has 'git[[:space:]]+reset[[:space:]]+--hard' && deny "git reset --hard"
# BUG 7 (2026-09-05, sessao fila-ganho-05-09) -- FALSO POSITIVO MEDIDO 2x NO DIA.
# A versao anterior era:
#   if has 'git[[:space:]]+push'; then
#     has '(--force|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$))' && deny ...
#   fi
# Procurava a invocacao num sitio da linha e a bandeira noutro sitio da MESMA
# linha, sem ligar uma coisa a outra -- e o has() compara sem distinguir
# maiusculas. Resultado: um `git commit -q -F -` (mensagem por stdin) encadeado
# com um envio NORMAL para o ramo de trabalho ficava bloqueado, porque o -F da
# mensagem era lido como a bandeira curta. E um relatorio que CITASSE esta
# propria mensagem de bloqueio tambem ficava bloqueado.
#
# Agora quem decide e o _push_forcado.py, ao lado deste ficheiro: liga a
# bandeira ao subcomando, so olha para o mesmo segmento de comando, e ignora
# TEXTO (aspas, e corpos de heredoc que nao sejam entregues a uma shell).
#
# A PROTECCAO NAO AFROUXA -- 20 casos de teste em _push_forcado_testes.py:
# bandeira longa, com lease, curta (mesmo colada, tipo -qf), refspec com +, e
# heredoc entregue a bash continuam todos a bloquear; passou ate a apanhar uma
# invocacao precedida de `timeout 5 ...`, que a versao antiga so apanhava por
# acaso.
PUSHCHK="$(dirname "$0")/_push_forcado.py"
if [ "$T_OK" = "1" ] && [ -f "$PUSHCHK" ]; then
  printf '%s' "$T" | python "$PUSHCHK" && deny "git push forcado (bandeira de forca ou refspec com +)"
else
  # Payload ilegivel ou detector ausente -> volta a rede grosseira, fail-closed.
  if has 'git[[:space:]]+push'; then
    has '(--force|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$))' && deny "git push forcado (modo grosseiro: payload ilegivel ou detector ausente)"
  fi
fi

# ---- 2) supabase db reset (SEMPRE) ---------------------------------------
has 'supabase[[:space:]]+db[[:space:]]+reset' && deny "supabase db reset (destrói a base)"

# ---- 3) Deploy de edge function protegida --------------------------------
if printf '%s' "$TOOLNAME" | grep -Eiq 'deploy_edge_function' || has 'supabase[[:space:]]+functions[[:space:]]+deploy'; then
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
