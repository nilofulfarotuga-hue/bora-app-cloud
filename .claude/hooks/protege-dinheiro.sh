#!/usr/bin/env bash
# ============================================================================
# TRAVA BORA — protege-dinheiro.sh
# ----------------------------------------------------------------------------
# Hook PreToolUse (matcher: Edit|Write|MultiEdit).
# Bloqueia (exit 2) qualquer tentativa de EDITAR/CRIAR ficheiros de código de
# DINHEIRO ou a própria trava. Não altera nada — só lê o stdin e decide.
#
# Contrato: exit 2 + mensagem no stderr => o Claude Code BLOQUEIA a ferramenta.
# Fail-safe: se o parse do file_path falhar, varre o payload cru (não passa
#            silenciosamente uma edição a ficheiro protegido).
#
# A camada dura e inbypassável é o permissions.deny em .claude/settings.json;
# este hook é a camada de mensagem clara + defesa em profundidade.
# ============================================================================
set +e

payload=$(cat)

# Extrai tool_input.file_path (fail-safe para o payload cru)
fp=$(printf '%s' "$payload" | python -c "import sys,json
try:
    print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except Exception:
    print('')" 2>/dev/null)
[ -z "$fp" ] && fp="$payload"

# Normaliza: backslashes -> /, colapsa // repetidas
norm=$(printf '%s' "$fp" | tr '\\' '/' | tr -s '/')

deny() {
  echo "🔒 TRAVA BORA — edição BLOQUEADA: $1" >&2
  echo "Este ficheiro é código de DINHEIRO (ou a própria trava) e está protegido." >&2
  echo "Para alterar: o Danilo edita à mão, fora do agente. Ver .claude/HOOKS.md." >&2
  exit 2
}

has() { printf '%s' "$norm" | grep -Eiq "$1"; }

# --- Ficheiros de dinheiro protegidos -------------------------------------
has '(^|/)lib/services/pricing_service\.dart'            && deny "pricing_service.dart (cálculo de preços)"
has '(^|/)lib/stores/order_store\.dart'                 && deny "order_store.dart (finalizePurchase)"
has '(^|/)lib/widgets/errand_execution_sheet\.dart'     && deny "errand_execution_sheet.dart (_finalizePurchase)"
has '(^|/)supabase/functions/dispatch-engine/'          && deny "edge function dispatch-engine"
has '(^|/)supabase/functions/stripe-webhook/'           && deny "edge function stripe-webhook"
has '(^|/)supabase/functions/finalize-order-from-intent/' && deny "edge function finalize-order-from-intent"
has '(^|/)supabase/functions/create-payment-intent/'    && deny "edge function create-payment-intent"
has '(^|/)supabase/functions/create-mbway-payment-intent/' && deny "edge function create-mbway-payment-intent"
has '(^|/)supabase/functions/refund/'                   && deny "edge function refund"
has '(^|/)supabase/functions/reprocess-refund/'         && deny "edge function reprocess-refund"
has '(^|/)supabase/functions/charge-extra/'             && deny "edge function charge-extra"

# --- Auto-proteção: a trava protege a própria trava -----------------------
has '(^|/)\.claude/hooks/'                              && deny ".claude/hooks/** (a própria trava)"
has '(^|/)\.claude/settings\.json'                      && deny ".claude/settings.json (config da trava)"
has '(^|/)\.claude/settings\.local\.json'               && deny ".claude/settings.local.json (config da trava)"

# --- Guardiões multiagente (F1 — RED_MODEL §2: workers não se automodifiquem) ---
has '(^|/)\.claude/agents/critic\.md'                   && deny "agents/critic.md (guardião multiagente)"
has '(^|/)\.claude/agents/consensus\.md'                && deny "agents/consensus.md (guardião multiagente)"
has '(^|/)\.claude/\.ai/cortex-mcp/router\.mjs'          && deny ".ai/cortex-mcp/router.mjs (router multiagente)"

# Nada bateu -> deixa passar
exit 0
