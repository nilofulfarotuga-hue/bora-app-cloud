"""T55 — Sessão chatbot com skill ``GENERAL_FAQ`` (sem order context).

Cenário:
1. Criar session ``active_skill='GENERAL_FAQ'`` sem order_id (FAQ geral).
2. INSERT message user + assistant com tool_name='general_faq'.
3. Validar active_skill=GENERAL_FAQ.
"""
from helpers.chatbot import (
    assert_session_active_skill,
    cleanup_session,
    create_chatbot_session,
    get_session_state,
    insert_chatbot_message,
)


def test_t55_session_with_skill_general_faq(admin_client, cliente_a):
    """active_skill=GENERAL_FAQ sem order_id."""
    session_id = create_chatbot_session(
        admin_client,
        user_id=cliente_a['user_id'],
        user_role='client',
        order_id=None,
        active_skill='GENERAL_FAQ',
    )

    insert_chatbot_message(
        admin_client,
        session_id=session_id,
        role='user',
        content='Qual a vossa morada?',
    )
    insert_chatbot_message(
        admin_client,
        session_id=session_id,
        role='assistant',
        content='Bora App opera em Portugal Continental.',
        tool_name='general_faq',
        tool_input={'topic': 'address'},
        tool_output={'answer': 'PT continental'},
    )

    assert_session_active_skill(admin_client, session_id, 'GENERAL_FAQ')
    state = get_session_state(admin_client, session_id)
    assert state.get('order_id') is None, (
        f"order_id devia ser NULL para GENERAL_FAQ, recebido {state.get('order_id')!r}"
    )

    cleanup_session(admin_client, session_id)
