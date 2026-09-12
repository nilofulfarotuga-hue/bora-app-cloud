#!/usr/bin/env bash
set +e
cd "$(dirname "$0")/../../.."
pass=0; fail=0
t() {
  local desc="$1"; local tool="$2"; local fp="$3"; local expected="$4"
  local payload; payload=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$fp")
  local out code; out=$(printf '%s' "$payload" | bash .claude/hooks/protege-dinheiro.sh 2>&1); code=$?
  if [ "$expected" = "DENY" ] && [ "$code" = "2" ]; then pass=$((pass+1)); echo "PASS [deny]  $desc (exit=$code)"
  elif [ "$expected" = "PASS" ] && [ "$code" = "0" ]; then pass=$((pass+1)); echo "PASS [allow] $desc (exit=$code)"
  else fail=$((fail+1)); echo "FAIL [want=$expected got=$code] $desc -- $out"; fi
}
echo "=== F1.6 Testes da Trava: protege-dinheiro.sh (Edit/Write/MultiEdit) ==="
t "Edit pricing_service.dart"        "Edit"    "lib/services/pricing_service.dart"           DENY
t "Write order_store.dart"          "Write"   "lib/stores/order_store.dart"                 DENY
t "MultiEdit errand_execution_sheet" "MultiEdit" "lib/widgets/errand_execution_sheet.dart"   DENY
t "Edit dispatch-engine/index.ts"   "Edit"    "supabase/functions/dispatch-engine/index.ts" DENY
t "Write stripe-webhook/index.ts"   "Write"   "supabase/functions/stripe-webhook/index.ts" DENY
t "Edit refund"                     "Edit"    "supabase/functions/refund/index.ts"          DENY
t "Edit charge-extra"               "Edit"    "supabase/functions/charge-extra/index.ts"    DENY
t "Edit .claude/hooks/x.sh"         "Edit"    ".claude/hooks/auto-rules-sync-notify.sh"      DENY
t "Edit .claude/settings.json"      "Edit"    ".claude/settings.json"                       DENY
t "Edit .claude/settings.local.json" "Edit"   ".claude/settings.local.json"                 DENY
t "Write agents/critic.md"          "Write"   ".claude/agents/critic.md"                     DENY
t "Write agents/consensus.md"       "Write"   ".claude/agents/consensus.md"                 DENY
t "Write router.mjs"                "Write"   ".claude/.ai/cortex-mcp/router.mjs"            DENY
t "Edit lib/screens/home.dart"      "Edit"    "lib/screens/client/home_screen.dart"         PASS
t "Write supabase/functions/user-notifications" "Write" "supabase/functions/user-notifications/index.ts" PASS
t "Edit RED_MODEL.md"               "Edit"    ".claude/.ai/security/RED_MODEL.md"            PASS
echo "=== Result: $pass pass, $fail fail ==="
exit $fail
