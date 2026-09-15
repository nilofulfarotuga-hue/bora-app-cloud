"""Sessão 7E-A — pytest fixtures partilhadas.

Adiciona scripts/e2e/ ao sys.path para `from helpers.* import ...` funcionar
sem precisar de instalar como package.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Adicionar scripts/e2e/ ao sys.path (parent do tests/)
_E2E_ROOT = Path(__file__).resolve().parent.parent
if str(_E2E_ROOT) not in sys.path:
    sys.path.insert(0, str(_E2E_ROOT))


@pytest.fixture(scope="session")
def admin_client():
    """Cliente Supabase com service_role para todos os testes da sessão."""
    from helpers.auth import admin_client as _admin_client

    return _admin_client()
