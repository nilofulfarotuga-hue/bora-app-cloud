"""Sessão 7E-A — Smoke B9 (3 testes independentes de seed).

Aprovado pelo Danilo: estes 3 testes NÃO dependem de fixtures (seed.py).
Confirmam que o boot do framework funciona antes de qualquer fluxo de domínio.

Se algum destes falha → boot do framework está partido, abortar antes
de avançar para 7E-B.
"""

from __future__ import annotations

import os


def test_env_vars_loaded():
    """Confirma que SUPABASE_URL e SERVICE_ROLE_KEY são lidos de scripts/rag/.env."""
    from helpers.auth import load_env

    load_env()
    assert os.environ.get("SUPABASE_URL"), "SUPABASE_URL ausente em scripts/rag/.env"
    assert os.environ.get("SUPABASE_SERVICE_ROLE_KEY"), "SUPABASE_SERVICE_ROLE_KEY ausente"
    # Sanity check: estamos a apontar para o projecto correcto.
    assert "ojykpzwqrtusfeakzrna" in os.environ["SUPABASE_URL"], (
        "SUPABASE_URL aponta para projecto errado — esperado ojykpzwqrtusfeakzrna (EU-West-1)"
    )


def test_admin_client_connects(admin_client):
    """Confirma que o cliente Supabase com service_role consegue ler `restaurants`."""
    res = admin_client.table("restaurants").select("id").limit(1).execute()
    # Pode estar vazia em teoria, mas a query tem de devolver `data` (lista).
    assert res.data is not None, "query a restaurants devolveu None"
    assert isinstance(res.data, list), f"esperado list, veio {type(res.data).__name__}"


def test_test_password_constant():
    """Confirma que a password constante de teste está definida e não é trivial."""
    from helpers.auth import TEST_PASSWORD

    assert isinstance(TEST_PASSWORD, str), "TEST_PASSWORD tem de ser str"
    assert len(TEST_PASSWORD) >= 12, f"TEST_PASSWORD demasiado curta: {len(TEST_PASSWORD)} chars"
    # Nunca deve ser uma password trivial (defesa contra copy-paste de demos prod).
    forbidden = {"123456", "password", "12345678", "qwerty"}
    assert TEST_PASSWORD not in forbidden, "TEST_PASSWORD trivial — escolher algo único"
