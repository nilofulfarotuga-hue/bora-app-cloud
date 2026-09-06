#!/usr/bin/env bash
# Sessão 7E-A — runner cross-platform para os testes E2E.
#
# Uso:
#   ./run_all.sh           # corre seed + smoke
#   ./run_all.sh smoke     # só smoke (não corre seed)
#   ./run_all.sh seed      # só seed
#   ./run_all.sh cleanup   # só cleanup --confirm (CUIDADO)
#
# Funciona em Linux, macOS e Windows (Git Bash, WSL).
set -euo pipefail

cd "$(dirname "$0")"

# venv -------------------------------------------------------------------------
if [ ! -d ".venv" ]; then
  echo "[run_all] criando .venv ..."
  python3 -m venv .venv 2>/dev/null || python -m venv .venv
fi

# activate (Windows ou Unix)
if [ -f ".venv/Scripts/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/Scripts/activate
elif [ -f ".venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
else
  echo "[run_all] ERRO: não consigo activar .venv"
  exit 1
fi

# deps -------------------------------------------------------------------------
pip install -q -r requirements.txt

# action -----------------------------------------------------------------------
ACTION="${1:-all}"

run_seed() {
  echo "[run_all] seed (idempotente) ..."
  python seed.py
}

run_smoke() {
  echo "[run_all] smoke (7E-A boot) ..."
  python -m pytest tests/test_smoke.py -v
}

# 7E-B — suite completa (groups 1, 2, 4, 7). Não usar set -e neste bloco,
# senão o script aborta na 1ª falha de teste.
run_smoke_7eb() {
  echo "[run_all] smoke 7E-B (groups 1, 2, 4, 7) ..."
  set +e
  python -m pytest tests/ -v --tb=short --html=reports/last_run.html --self-contained-html
  PYTEST_EXIT=$?
  set -e
  if [ "$PYTEST_EXIT" -eq 0 ]; then
    echo "✅ Suite 7E-B OK"
  else
    echo "❌ Falhas detectadas em 7E-B (pytest EXIT=$PYTEST_EXIT) — ver BUGS_FOUND.md"
  fi
  echo ""
  echo "════════════════════════════════════════════════"
  echo "Política 7E-B: FAILs não bloqueiam merge."
  echo "Bugs documentados em scripts/e2e/BUGS_FOUND.md"
  echo "Report: reports/last_run.html"
  echo "════════════════════════════════════════════════"
  return 0
}

run_cleanup_confirm() {
  echo "[run_all] cleanup --confirm ..."
  python cleanup.py --confirm
}

case "$ACTION" in
  all)     run_seed; run_smoke_7eb ;;
  seed)    run_seed ;;
  smoke)   run_smoke ;;
  smoke-7eb) run_smoke_7eb ;;
  cleanup) run_cleanup_confirm ;;
  *)       echo "[run_all] acção desconhecida: $ACTION"; exit 2 ;;
esac

echo "[run_all] ✓ completo"
exit 0  # política CEO-AI: FAILs não bloqueiam merge
