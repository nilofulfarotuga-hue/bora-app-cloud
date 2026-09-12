"""T58 — RPC ``increment_chatbot_quota`` incrementa contador diário.

Cenário:
1. Cliente_a autentica.
2. Cleanup quota actual.
3. Chama ``increment_chatbot_quota()`` 5 vezes.
4. Valida ``support_chatbot_quota.messages_count == 5`` para hoje.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.chatbot import (
    cleanup_user_chatbot_state,
    get_quota_today,
    increment_quota,
)


def test_t58_quota_increments_per_call(admin_client, cliente_a):
    """5 chamadas RPC → messages_count=5."""
    cleanup_user_chatbot_state(admin_client, cliente_a['user_id'])

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)

    for _ in range(5):
        increment_quota(client_authed)

    actual = get_quota_today(admin_client, cliente_a['user_id'])
    assert actual == 5, (
        f"messages_count esperado 5, recebido {actual}"
    )

    cleanup_user_chatbot_state(admin_client, cliente_a['user_id'])
