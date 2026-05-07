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
  echo "[run_all] smoke ..."
  python -m pytest tests/test_smoke.py -v
}

run_cleanup_confirm() {
  echo "[run_all] cleanup --confirm ..."
  python cleanup.py --confirm
}

case "$ACTION" in
  all)     run_seed; run_smoke ;;
  seed)    run_seed ;;
  smoke)   run_smoke ;;
  cleanup) run_cleanup_confirm ;;
  *)       echo "[run_all] acção desconhecida: $ACTION"; exit 2 ;;
esac

echo "[run_all] ✓ completo"
