"""T27 — ``consume_tokens`` falha graceful com balance insuficiente.

Cenário:
1. Reset tokens.
2. add_tokens(30).
3. consume_tokens(50) → deve devolver False (balance insuficiente).
4. Balance final inalterado = 30 (sem debitar parcial).
"""
from helpers.tokens import (
    add_tokens,
    assert_tokens_balance,
    consume_tokens,
    reset_user_tokens,
)


def test_t27_consume_insufficient_balance_returns_false(admin_client, cliente_a):
    """Tentar consume > balance → False, sem efeito colateral."""
    reset_user_tokens(admin_client, cliente_a['user_id'])

    add_tokens(admin_client, user_id=cliente_a['user_id'], amount=30)

    success = consume_tokens(
        admin_client, user_id=cliente_a['user_id'], amount=50
    )
    assert success is False, (
        f"esperava False (balance insuficiente: 30<50), recebido {success!r}"
    )

    # Balance NÃO devia ter mudado (consume é all-or-nothing)
    assert_tokens_balance(
        admin_client,
        user_id=cliente_a['user_id'],
        expected=30,
        msg="balance NÃO deve mudar quando consume falha",
    )

    reset_user_tokens(admin_client, cliente_a['user_id'])
