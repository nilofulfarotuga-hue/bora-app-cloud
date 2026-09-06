"""T56 — Escalation: cliente pede humano → support_ticket criado.

Cenário:
1. Criar session com escalated=true + escalation_reason='human_request'.
2. INSERT support_tickets linkado via session_id, status='open',
   user_role='client', channel='chatbot'.
3. Update session.ticket_id ← ticket criado (linkagem bidireccional).
4. Validar:
   - session.escalated=true
   - ticket.status='open', user_role='client', channel='chatbot'
   - ticket.session_id == session_id
"""
from helpers.chatbot import (
    assert_session_escalated,
    cleanup_session,
    create_chatbot_session,
    create_support_ticket,
    get_ticket,
)


def test_t56_escalation_creates_open_ticket(admin_client, cliente_a):
    """escalated=true + ticket aberto + linkado."""
    session_id = create_chatbot_session(
        admin_client,
        user_id=cliente_a['user_id'],
        user_role='client',
        active_skill='ESCALATE',
        escalated=True,
        escalation_reason='human_request',
    )

    ticket_id = create_support_ticket(
        admin_client,
        user_id=cliente_a['user_id'],
        user_role='client',
        question='Quero falar com um humano sobre o meu pedido',
        session_id=session_id,
        status='open',
        channel='chatbot',
    )

    # Linkar session.ticket_id
    admin_client.table("support_chatbot_sessions").update(
        {"ticket_id": ticket_id}
    ).eq("id", session_id).execute()

    assert_session_escalated(admin_client, session_id, expected_reason='human_request')

    ticket = get_ticket(admin_client, ticket_id)
    assert ticket.get('status') == 'open', (
        f"ticket.status esperado 'open', recebido {ticket.get('status')!r}"
    )
    assert ticket.get('user_role') == 'client'
    assert ticket.get('channel') == 'chatbot'
    assert ticket.get('session_id') == session_id, (
        f"ticket.session_id esperado {session_id!r}, recebido {ticket.get('session_id')!r}"
    )

    cleanup_session(admin_client, session_id)
