"""T28 — Tokens expirados não contam para ``get_user_tokens``.

Cenário:
1. Reset tokens.
2. add_tokens(100) → ``token_a``.
3. Força ``token_a.expires_at`` no passado (1 dia atrás).
4. add_tokens(50) → ``token_b`` (válido, expires_at = now+60d).
5. ``get_user_tokens()`` deve devolver apenas 50 (só ``token_b``).
6. ``count_active_tokens`` confirma 1 row activa.
"""
from helpers.tokens import (
    add_tokens,
    assert_tokens_balance,
    count_active_tokens,
    expire_token_row,
    reset_user_tokens,
)


def test_t28_expired_tokens_excluded_from_balance(admin_client, cliente_a):
    """Token expirado não conta para balance."""
    reset_user_tokens(admin_client, cliente_a['user_id'])

    token_a = add_tokens(admin_client, user_id=cliente_a['user_id'], amount=100)
    expire_token_row(admin_client, token_a)

    add_tokens(admin_client, user_id=cliente_a['user_id'], amount=50)

    assert_tokens_balance(
        admin_client,
        user_id=cliente_a['user_id'],
        expected=50,
        msg="balance ignora token expirado (100), conta só válido (50)",
    )

    active = count_active_tokens(admin_client, user_id=cliente_a['user_id'])
    assert active == 1, (
        f"esperava 1 row activa (token expirado excluído), recebido {active}"
    )

    reset_user_tokens(admin_client, cliente_a['user_id'])
