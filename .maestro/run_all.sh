#!/bin/bash
# Bora App — runner E2E completo (24 flows + 5 sub-flows).
# Uso: ./.maestro/run_all.sh [filtro]
#   sem argumentos       → corre TUDO sequencialmente
#   ./run_all.sh cliente → só flows/cliente/*.yaml
#   ./run_all.sh parceiro/05_*.yaml → wildcards aceites

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v maestro >/dev/null 2>&1; then
  echo "❌ Maestro CLI não encontrado no PATH."
  echo "   Instalar: curl -Ls https://get.maestro.mobile.dev | bash"
  echo "   Ver README.md para alternativas Windows."
  exit 1
fi

filter="${1:-}"
if [[ -n "$filter" ]]; then
  files=$(find flows -type f -name "*.yaml" -path "*${filter}*" | sort)
else
  files=$(find flows -type f -name "*.yaml" | sort)
fi

total=$(echo "$files" | wc -l)
ok=0; fail=0; failed_list=""

echo "🚀 Bora App — E2E ($total flows)"
echo "----"

while IFS= read -r flow; do
  echo ""
  echo "→ $flow"
  if maestro test "$flow"; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    failed_list="$failed_list\n  - $flow"
  fi
done <<< "$files"

echo ""
echo "----"
echo "✅ OK:    $ok / $total"
echo "❌ FAIL:  $fail / $total"
if [[ "$fail" -gt 0 ]]; then
  echo -e "Falhas:$failed_list"
  exit 1
fi
