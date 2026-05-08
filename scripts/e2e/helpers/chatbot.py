"""Helpers para tests do support-chatbot (Grupo 11 — T54-T58).

Estratégia: NÃO invocar Edge Function ``support-chatbot`` directo
(precisa Gemini API key em CI). Em vez disso, simulamos sessões via
INSERT directo em ``support_chatbot_sessions/messages/quota`` e
``support_pending_actions/tickets``.

Tabelas relevantes (validadas via MCP em prod 2026-05-08):
- ``support_chatbot_sessions`` (11 cols): user_id, user_role, order_id,
  active_skill, messages_count, started_at, ended_at, escalated,
  escalation_reason, ticket_id.
- ``support_chatbot_messages`` (9 cols): session_id, role, content,
  tool_name, tool_input, tool_output, tokens_used, created_at.
- ``support_chatbot_quota`` (3 cols, composite PK user_id+day):
  messages_count.
- ``support_pending_actions`` (17 cols): session_id, user_id, skill_name,
  action_type, action_payload, status ∈ {pending,dispatched,executed,failed,rejected},
  proposed_at, reviewed_at, executed_at, dispatch_target.
- ``support_tickets`` (19 cols): user_id, user_role, question, bot_answer,
  status ∈ {open,bot_answered,human_answered,closed}, channel ∈
  {chatbot,whatsapp,email}, session_id.
- ``support_skills``: ``mode`` ∈ {read_only, write, write_shadow,
  write_auto, escalate}.

RPCs:
- ``increment_chatbot_quota()`` — sem args, usa ``auth.uid()`` implícito;
  cliente tem que estar autenticado.
- ``fn_notify_admin_pending_action()`` — trigger function (não chamada directa).

⚠️ Constraints:
- ``support_tickets.user_role`` ∈ {client, driver, partner, guest}.
- ``support_tickets.question`` length 1-2000.
"""
from datetime import date, datetime, timezone
from typing import Any, Dict, Optional

from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

VALID_USER_ROLES = ('client', 'driver', 'partner', 'guest')
VALID_TICKET_STATUS = ('open', 'bot_answered', 'human_answered', 'closed')
VALID_TICKET_CHANNELS = ('chatbot', 'whatsapp', 'email')
VALID_PENDING_ACTION_STATUS = (
    'pending', 'dispatched', 'executed', 'failed', 'rejected'
)
VALID_MESSAGE_ROLES = ('user', 'assistant', 'tool', 'system')


# ─────────────────────────────────────────────────────────────
# Sessions
# ─────────────────────────────────────────────────────────────

def create_chatbot_session(
    admin_client: Client,
    user_id: str,
    user_role: str = 'client',
    order_id: Optional[str] = None,
    active_skill: Optional[str] = None,
    escalated: bool = False,
    escalation_reason: Optional[str] = None,
) -> str:
    """Cria sessão chatbot directamente em ``support_chatbot_sessions``.

    Returns:
        UUID (str) da sessão criada.
    """
    if user_role not in VALID_USER_ROLES:
        raise ValueError(
            f"user_role inválido: {user_role!r}. Use {VALID_USER_ROLES}."
        )
    payload: Dict[str, Any] = {
        'user_id': user_id,
        'user_role': user_role,
        'messages_count': 0,
        'escalated': escalated,
    }
    if order_id is not None:
        payload['order_id'] = order_id
    if active_skill is not None:
        payload['active_skill'] = active_skill
    if escalation_reason is not None:
        payload['escalation_reason'] = escalation_reason

    result = admin_client.table("support_chatbot_sessions").insert(payload).execute()
    rows = result.data or []
    if not rows:
        raise RuntimeError(f"INSERT support_chatbot_sessions devolveu vazio: {result!r}")
    return rows[0]['id']


def insert_chatbot_message(
    admin_client: Client,
    session_id: str,
    role: str,
    content: str,
    tool_name: Optional[str] = None,
    tool_input: Optional[Dict[str, Any]] = None,
    tool_output: Optional[Dict[str, Any]] = None,
    tokens_used: Optional[int] = None,
) -> str:
    """INSERT row em ``support_chatbot_messages`` + bump messages_count."""
    if role not in VALID_MESSAGE_ROLES:
        raise ValueError(
            f"role inválido: {role!r}. Use {VALID_MESSAGE_ROLES}."
        )
    payload: Dict[str, Any] = {
        'session_id': session_id,
        'role': role,
        'content': content,
    }
    if tool_name is not None:
        payload['tool_name'] = tool_name
    if tool_input is not None:
        payload['tool_input'] = tool_input
    if tool_output is not None:
        payload['tool_output'] = tool_output
    if tokens_used is not None:
        payload['tokens_used'] = tokens_used

    result = admin_client.table("support_chatbot_messages").insert(payload).execute()
    rows = result.data or []
    msg_id = rows[0]['id'] if rows else None
    if not msg_id:
        raise RuntimeError(f"INSERT support_chatbot_messages devolveu vazio: {result!r}")

    # Bump messages_count na sessão (não há trigger automático conhecido)
    cur = (
        admin_client.table("support_chatbot_sessions")
        .select("messages_count")
        .eq("id", session_id)
        .single()
        .execute()
    ).data or {}
    new_count = (cur.get('messages_count') or 0) + 1
    admin_client.table("support_chatbot_sessions").update(
        {"messages_count": new_count}
    ).eq("id", session_id).execute()

    return msg_id


def get_session_state(
    admin_client: Client,
    session_id: str,
) -> Dict[str, Any]:
    """Lê snapshot da sessão (active_skill, messages_count, escalated, ticket_id)."""
    result = (
        admin_client.table("support_chatbot_sessions")
        .select("*")
        .eq("id", session_id)
        .single()
        .execute()
    )
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Quota (RPC + leitura directa)
# ─────────────────────────────────────────────────────────────

def increment_quota(client_authed: Client) -> None:
    """Chama RPC ``increment_chatbot_quota`` (usa auth.uid() implícito)."""
    client_authed.rpc('increment_chatbot_quota', {}).execute()


def get_quota_today(admin_client: Client, user_id: str) -> int:
    """Lê ``support_chatbot_quota.messages_count`` para hoje."""
    today = date.today().isoformat()
    result = (
        admin_client.table("support_chatbot_quota")
        .select("messages_count")
        .eq("user_id", user_id)
        .eq("day", today)
        .execute()
    )
    rows = result.data or []
    if not rows:
        return 0
    return int(rows[0].get('messages_count') or 0)


# ─────────────────────────────────────────────────────────────
# Pending actions (write-shadow)
# ─────────────────────────────────────────────────────────────

def create_pending_action(
    admin_client: Client,
    session_id: str,
    user_id: str,
    skill_name: str,
    action_type: str,
    action_payload: Dict[str, Any],
    status: str = 'pending',
    user_message: Optional[str] = None,
    agent_reasoning: Optional[str] = None,
    dispatch_target: Optional[str] = None,
) -> str:
    """INSERT row em ``support_pending_actions`` (admin aprova depois)."""
    if status not in VALID_PENDING_ACTION_STATUS:
        raise ValueError(
            f"status inválido: {status!r}. Use {VALID_PENDING_ACTION_STATUS}."
        )
    payload: Dict[str, Any] = {
        'session_id': session_id,
        'user_id': user_id,
        'skill_name': skill_name,
        'action_type': action_type,
        'action_payload': action_payload,
        'status': status,
    }
    if user_message is not None:
        payload['user_message'] = user_message
    if agent_reasoning is not None:
        payload['agent_reasoning'] = agent_reasoning
    if dispatch_target is not None:
        payload['dispatch_target'] = dispatch_target

    result = admin_client.table("support_pending_actions").insert(payload).execute()
    rows = result.data or []
    if not rows:
        raise RuntimeError(f"INSERT support_pending_actions devolveu vazio: {result!r}")
    return rows[0]['id']


# ─────────────────────────────────────────────────────────────
# Tickets (escalation)
# ─────────────────────────────────────────────────────────────

def create_support_ticket(
    admin_client: Client,
    user_id: Optional[str],
    user_role: str,
    question: str,
    session_id: Optional[str] = None,
    bot_answer: Optional[str] = None,
    status: str = 'open',
    channel: str = 'chatbot',
    order_id: Optional[str] = None,
) -> str:
    """INSERT row em ``support_tickets``. ``user_id`` opcional (guest)."""
    if user_role not in VALID_USER_ROLES:
        raise ValueError(
            f"user_role inválido: {user_role!r}. Use {VALID_USER_ROLES}."
        )
    if status not in VALID_TICKET_STATUS:
        raise ValueError(
            f"status inválido: {status!r}. Use {VALID_TICKET_STATUS}."
        )
    if channel not in VALID_TICKET_CHANNELS:
        raise ValueError(
            f"channel inválido: {channel!r}. Use {VALID_TICKET_CHANNELS}."
        )
    if not (1 <= len(question) <= 2000):
        raise ValueError(
            f"question length fora de [1,2000]: {len(question)}"
        )

    payload: Dict[str, Any] = {
        'user_role': user_role,
        'question': question,
        'status': status,
        'channel': channel,
    }
    if user_id is not None:
        payload['user_id'] = user_id
    if session_id is not None:
        payload['session_id'] = session_id
    if bot_answer is not None:
        payload['bot_answer'] = bot_answer
    if order_id is not None:
        payload['order_id'] = order_id

    result = admin_client.table("support_tickets").insert(payload).execute()
    rows = result.data or []
    if not rows:
        raise RuntimeError(f"INSERT support_tickets devolveu vazio: {result!r}")
    return rows[0]['id']


def get_ticket(admin_client: Client, ticket_id: str) -> Dict[str, Any]:
    """Lê ticket completo."""
    result = (
        admin_client.table("support_tickets")
        .select("*")
        .eq("id", ticket_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_pending_action(admin_client: Client, action_id: str) -> Dict[str, Any]:
    """Lê pending action completa."""
    result = (
        admin_client.table("support_pending_actions")
        .select("*")
        .eq("id", action_id)
        .single()
        .execute()
    )
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_session_active_skill(
    admin_client: Client,
    session_id: str,
    expected_skill: str,
) -> None:
    """Valida ``support_chatbot_sessions.active_skill``."""
    state = get_session_state(admin_client, session_id)
    actual = state.get('active_skill')
    assert actual == expected_skill, (
        f"active_skill esperado {expected_skill!r}, recebido {actual!r}"
    )


def assert_session_escalated(
    admin_client: Client,
    session_id: str,
    expected_reason: Optional[str] = None,
) -> None:
    """Valida ``escalated=true`` + opcional ``escalation_reason``."""
    state = get_session_state(admin_client, session_id)
    assert state.get('escalated') is True, (
        f"esperava escalated=True, recebido {state.get('escalated')!r}"
    )
    if expected_reason is not None:
        assert state.get('escalation_reason') == expected_reason, (
            f"escalation_reason esperado {expected_reason!r}, "
            f"recebido {state.get('escalation_reason')!r}"
        )


def assert_pending_action_created(
    admin_client: Client,
    session_id: str,
    skill_name: str,
    expected_status: str = 'pending',
) -> Dict[str, Any]:
    """Valida que existe pending action para a sessão; retorna a row."""
    result = (
        admin_client.table("support_pending_actions")
        .select("*")
        .eq("session_id", session_id)
        .eq("skill_name", skill_name)
        .order("proposed_at", desc=True)
        .limit(1)
        .execute()
    )
    rows = result.data or []
    assert rows, (
        f"esperava pending action skill={skill_name!r} para session={session_id}, "
        f"recebido vazio"
    )
    row = rows[0]
    assert row.get('status') == expected_status, (
        f"status esperado {expected_status!r}, recebido {row.get('status')!r}"
    )
    return row


# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────

def cleanup_session(admin_client: Client, session_id: str) -> None:
    """Apaga sessão + cascata: messages, pending_actions, tickets linkados."""
    admin_client.table("support_chatbot_messages").delete().eq(
        "session_id", session_id
    ).execute()
    admin_client.table("support_pending_actions").delete().eq(
        "session_id", session_id
    ).execute()
    admin_client.table("support_tickets").delete().eq(
        "session_id", session_id
    ).execute()
    admin_client.table("support_chatbot_sessions").delete().eq(
        "id", session_id
    ).execute()


def cleanup_user_chatbot_state(
    admin_client: Client,
    user_id: str,
) -> None:
    """Limpa todas as sessões/quota/tickets/pending actions do utilizador."""
    # Sessions cascade: messages → pending_actions → tickets → sessions
    sessions = (
        admin_client.table("support_chatbot_sessions")
        .select("id")
        .eq("user_id", user_id)
        .execute()
    ).data or []
    for s in sessions:
        cleanup_session(admin_client, s['id'])

    # Quota (composite PK — apaga todas as datas do user)
    admin_client.table("support_chatbot_quota").delete().eq(
        "user_id", user_id
    ).execute()

    # Pending actions órfãs (sem session)
    admin_client.table("support_pending_actions").delete().eq(
        "user_id", user_id
    ).execute()

    # Tickets órfãos (sem session)
    admin_client.table("support_tickets").delete().eq(
        "user_id", user_id
    ).execute()
