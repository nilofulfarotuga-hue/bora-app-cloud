"""T25 — RPC ``add_tokens`` cria row em ``bora_tokens``.

Cenário:
1. Reset tokens do cliente.
2. Chama ``add_tokens(user_id, role='client', amount=100, order_id=None)``.
3. Valida row em ``bora_tokens`` com ``amount=100``, ``role='client'``,
   ``is_used=false``, ``expires_at > now()``.
4. ``get_user_tokens(user_id) == 100``.
"""
from helpers.tokens import (
    add_tokens,
    assert_token_row_shape,
    assert_tokens_balance,
    reset_user_tokens,
)


def test_t25_add_tokens_creates_row_and_balance(admin_client, cliente_a):
    """add_tokens cria row + get_user_tokens reflecte saldo."""
    reset_user_tokens(admin_client, cliente_a['user_id'])

    token_id = add_tokens(
        admin_client,
        user_id=cliente_a['user_id'],
        amount=100,
        role='client',
    )
    assert token_id, f"add_tokens devia retornar UUID, recebeu {token_id!r}"

    row = assert_token_row_shape(
        admin_client,
        user_id=cliente_a['user_id'],
        expected_amount=100,
        source_order_id=None,
    )
    assert row['role'] == 'client', f"role esperado 'client', recebido {row['role']!r}"

    assert_tokens_balance(
        admin_client,
        user_id=cliente_a['user_id'],
        expected=100,
        msg="balance pós add_tokens",
    )

    # Cleanup
    reset_user_tokens(admin_client, cliente_a['user_id'])
