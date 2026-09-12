"""T54 — Sessão chatbot com skill ``ORDER_STATUS`` (simulado via INSERT).

Cenário (sem invocar Edge Fn live):
1. Criar order test (cliente_a).
2. Criar session ``support_chatbot_sessions`` com active_skill='ORDER_STATUS',
   ligada à order via ``order_id``.
3. INSERT 2 messages: user pergunta + assistant responde com tool_name.
4. Validar ``session.active_skill='ORDER_STATUS'`` + ``messages_count=2``.
"""
from helpers.chatbot import (
    assert_session_active_skill,
    cleanup_session,
    create_chatbot_session,
    get_session_state,
    insert_chatbot_message,
)
from helpers.orders import create_test_order


def test_t54_session_with_skill_order_status(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """active_skill=ORDER_STATUS + tool_name registado em messages."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    session_id = create_chatbot_session(
        admin_client,
        user_id=cliente_a['user_id'],
        user_role='client',
        order_id=order_id,
        active_skill='ORDER_STATUS',
    )

    insert_chatbot_message(
        admin_client,
        session_id=session_id,
        role='user',
        content='Qual o estado do meu pedido?',
    )
    insert_chatbot_message(
        admin_client,
        session_id=session_id,
        role='assistant',
        content='O teu pedido está em preparação.',
        tool_name='get_order_status',
        tool_input={'order_id': order_id},
        tool_output={'status': 'preparing'},
        tokens_used=42,
    )

    assert_session_active_skill(admin_client, session_id, 'ORDER_STATUS')
    state = get_session_state(admin_client, session_id)
    assert state.get('messages_count') == 2, (
        f"messages_count esperado 2, recebido {state.get('messages_count')!r}"
    )

    cleanup_session(admin_client, session_id)
