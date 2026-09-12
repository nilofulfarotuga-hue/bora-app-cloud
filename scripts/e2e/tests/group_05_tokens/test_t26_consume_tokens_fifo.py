"""T26 — ``consume_tokens`` debita FIFO (oldest first).

Cenário:
1. Reset tokens.
2. add_tokens 50 (1ª row, mais antiga).
3. add_tokens 100 (2ª row, mais recente).
4. consume_tokens(60) → deve consumir 50 da 1ª + 10 da 2ª (FIFO).
5. Balance final = 90 (200 - 110... hmm, 50+100=150, consume 60 → 90).
"""
import time

from helpers.tokens import (
    add_tokens,
    assert_tokens_balance,
    consume_tokens,
    reset_user_tokens,
)


def test_t26_consume_tokens_fifo_oldest_first(admin_client, cliente_a):
    """Consume 60 do total 150 → balance final 90."""
    reset_user_tokens(admin_client, cliente_a['user_id'])

    add_tokens(admin_client, user_id=cliente_a['user_id'], amount=50)
    # Sleep mínimo para garantir created_at distinto (FIFO ordering)
    time.sleep(0.05)
    add_tokens(admin_client, user_id=cliente_a['user_id'], amount=100)

    success = consume_tokens(admin_client, user_id=cliente_a['user_id'], amount=60)
    assert success, "consume_tokens falhou: balance suficiente (150) mas devolveu False"

    assert_tokens_balance(
        admin_client,
        user_id=cliente_a['user_id'],
        expected=90,
        msg="balance pós consume(60) de [50,100]",
    )

    reset_user_tokens(admin_client, cliente_a['user_id'])
