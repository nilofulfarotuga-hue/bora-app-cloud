"""T57 — write_shadow skill cria ``support_pending_actions`` (admin aprova).

Cenário:
1. Criar order test (cliente_a).
2. Criar session com active_skill='CANCEL_PRE_PURCHASE'.
3. INSERT support_pending_actions:
   - skill_name='CANCEL_PRE_PURCHASE'
   - action_type='cancel_order'
   - action_payload={'order_id': order_id}
   - status='pending'
4. Validar row criada com status='pending', linkagem session_id correcta.

Nota: trigger ``fn_notify_admin_pending_action`` pode disparar (notify
admin via FCM). Não validamos o push em si — apenas que a row é criada.
"""
from helpers.chatbot import (
    assert_pending_action_created,
    cleanup_session,
    create_chatbot_session,
    create_pending_action,
)
from helpers.orders import create_test_order


def test_t57_write_shadow_creates_pending_action(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """write_shadow skill insere row em support_pending_actions."""
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
        active_skill='CANCEL_PRE_PURCHASE',
    )

    # NOTA: support_pending_actions.user_id é FK para public.users
    # (não auth.users). Cliente_a existe só em auth.users → passar None
    # (coluna é nullable). session_id mantém-se para tracking.
    action_id = create_pending_action(
        admin_client,
        session_id=session_id,
        user_id=None,
        skill_name='CANCEL_PRE_PURCHASE',
        action_type='cancel_order',
        action_payload={'order_id': order_id, 'reason': 'cliente desistiu'},
        status='pending',
        user_message='Quero cancelar o meu pedido por favor',
        agent_reasoning='Cliente solicita cancelamento pre-dispatch',
    )
    assert action_id, f"create_pending_action devia retornar UUID, recebeu {action_id!r}"

    row = assert_pending_action_created(
        admin_client,
        session_id=session_id,
        skill_name='CANCEL_PRE_PURCHASE',
        expected_status='pending',
    )
    assert row.get('action_type') == 'cancel_order', (
        f"action_type esperado 'cancel_order', recebido {row.get('action_type')!r}"
    )
    assert row.get('action_payload', {}).get('order_id') == order_id, (
        f"action_payload.order_id esperado {order_id!r}, "
        f"recebido {row.get('action_payload')!r}"
    )

    cleanup_session(admin_client, session_id)
