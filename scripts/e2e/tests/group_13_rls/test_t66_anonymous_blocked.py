"""T66 — Utilizador anónimo (sem JWT) bloqueado em tabelas sensíveis.

Cenário:
1. Cria order test (admin).
2. Cliente Supabase com APENAS anon key (sem JWT user) tenta SELECT.
3. Validar para cada tabela sensível:
   - Resultado vazio (RLS filtrou) OU
   - PostgrestError (sem permissão).

Tabelas testadas: orders, client_wallets, bora_tokens.

NOTA: ``SUPABASE_ANON_KEY`` não está em ``scripts/rag/.env``. Este test
é skipped automaticamente se a key não estiver disponível. Para activar,
exportar SUPABASE_ANON_KEY antes de correr pytest.
"""
import os

import pytest

from helpers.auth import load_env
from helpers.orders import create_test_order
from helpers.rls import build_anon_client


def test_t66_anonymous_blocked_in_sensitive_tables(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """Anon user vê 0 rows em orders/wallets/tokens."""
    load_env()
    if not os.getenv("SUPABASE_ANON_KEY"):
        pytest.skip(
            "SUPABASE_ANON_KEY não disponível — exportar manualmente "
            "para activar este test."
        )

    create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    anon = build_anon_client()

    blocked_tables = ('orders', 'client_wallets', 'bora_tokens')
    for table in blocked_tables:
        rows_visible = 0
        error_raised = None
        try:
            result = anon.table(table).select("*").limit(50).execute()
            rows_visible = len(result.data or [])
        except Exception as e:
            error_raised = e

        # Aceitamos qualquer um: erro RLS OU rows vazias
        if error_raised is None:
            assert rows_visible == 0, (
                f"anon SELECT em {table!r} devia retornar 0 rows OU erro, "
                f"recebido {rows_visible} rows"
            )
