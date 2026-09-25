"""Helpers para tests de skill_suggestions (Grupo 12 — T59-T61).

Schema validado via MCP em prod 2026-05-08:
- ``skill_suggestions`` (27 cols): proposal_type ∈ {new_skill,
  playbook_update, settings_update}; zone_type ∈ {safe, critical};
  status ∈ {pending, approved, rejected, implemented, rolled_back,
  auto_archived}; suggested_mode ∈ {read_only, write_shadow, escalate}.
- type_coherence constraint: ``new_skill`` OK; ``playbook_update``
  requer ``target_skill_id``; ``settings_update`` requer
  ``target_setting_key`` + ``target_setting_value``.
- ``target_setting_key`` regex ``^[a-z_]+$``.

RPCs disponíveis:
- ``admin_approve_skill_suggestion(p_suggestion_id, p_skill_name,
  p_category, p_mode, p_playbook_md, p_allowed_tools)`` → cria row em
  ``support_skills`` + transita suggestion para ``approved`` ou
  ``implemented``.
- ``admin_reject_skill_suggestion(p_suggestion_id, p_reason)`` →
  transita suggestion para ``rejected`` + grava ``rejection_reason``.
- ``admin_list_skill_suggestions(p_status, p_type, p_zone, p_category,
  p_search, p_limit)``.
- ``admin_bulk_reject_skill_suggestions(p_ids[], p_reason)``.
- ``admin_skill_suggestions_stats()`` / ``admin_skill_suggestions_metrics()``.
"""
from typing import Any, Dict, List, Optional

from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

VALID_PROPOSAL_TYPES = ('new_skill', 'playbook_update', 'settings_update')
VALID_ZONE_TYPES = ('safe', 'critical')
VALID_STATUS = (
    'pending', 'approved', 'rejected', 'implemented',
    'rolled_back', 'auto_archived',
)
VALID_SUGGESTED_MODES = ('read_only', 'write_shadow', 'escalate')

# Modes válidos em ``support_skills`` (super-set de suggested_mode).
VALID_SKILL_MODES = (
    'read_only', 'write', 'write_shadow', 'write_auto', 'escalate'
)


# ─────────────────────────────────────────────────────────────
# Insert directo (simula analyze-conversations Edge Fn)
# ─────────────────────────────────────────────────────────────

def insert_skill_suggestion(
    admin_client: Client,
    pattern_summary: str,
    sample_messages: Optional[List[Dict[str, Any]]] = None,
    message_count: int = 5,
    proposal_type: str = 'new_skill',
    zone_type: str = 'safe',
    status: str = 'pending',
    suggested_skill_name: Optional[str] = None,
    suggested_category: Optional[str] = None,
    suggested_mode: Optional[str] = None,
    suggested_playbook_md: Optional[str] = None,
    suggested_allowed_tools: Optional[Dict[str, Any]] = None,
    target_skill_id: Optional[str] = None,
    target_setting_key: Optional[str] = None,
    target_setting_value: Optional[str] = None,
    pattern_hash: Optional[str] = None,
) -> str:
    """INSERT directo em ``skill_suggestions`` (simula analyze-conversations).

    Defaults sensatos: proposal_type='new_skill', zone='safe',
    status='pending'. Para playbook_update/settings_update tem que
    passar os campos coerentes (constraint type_coherence).
    """
    if proposal_type not in VALID_PROPOSAL_TYPES:
        raise ValueError(
            f"proposal_type inválido: {proposal_type!r}. Use {VALID_PROPOSAL_TYPES}."
        )
    if zone_type not in VALID_ZONE_TYPES:
        raise ValueError(
            f"zone_type inválido: {zone_type!r}. Use {VALID_ZONE_TYPES}."
        )
    if status not in VALID_STATUS:
        raise ValueError(
            f"status inválido: {status!r}. Use {VALID_STATUS}."
        )
    if suggested_mode is not None and suggested_mode not in VALID_SUGGESTED_MODES:
        raise ValueError(
            f"suggested_mode inválido: {suggested_mode!r}. "
            f"Use {VALID_SUGGESTED_MODES}."
        )

    # Defaults para sample_messages — sample mínimo válido (jsonb array).
    if sample_messages is None:
        sample_messages = [
            {'role': 'user', 'content': 'Exemplo de pergunta utilizador'},
            {'role': 'assistant', 'content': 'Exemplo de resposta bot'},
        ]

    payload: Dict[str, Any] = {
        'pattern_summary': pattern_summary,
        'sample_messages': sample_messages,
        'message_count': message_count,
        'proposal_type': proposal_type,
        'zone_type': zone_type,
        'status': status,
    }

    if suggested_skill_name is not None:
        payload['suggested_skill_name'] = suggested_skill_name
    if suggested_category is not None:
        payload['suggested_category'] = suggested_category
    if suggested_mode is not None:
        payload['suggested_mode'] = suggested_mode
    if suggested_playbook_md is not None:
        payload['suggested_playbook_md'] = suggested_playbook_md
    if suggested_allowed_tools is not None:
        payload['suggested_allowed_tools'] = suggested_allowed_tools
    if target_skill_id is not None:
        payload['target_skill_id'] = target_skill_id
    if target_setting_key is not None:
        payload['target_setting_key'] = target_setting_key
    if target_setting_value is not None:
        payload['target_setting_value'] = target_setting_value
    if pattern_hash is not None:
        payload['pattern_hash'] = pattern_hash

    result = admin_client.table("skill_suggestions").insert(payload).execute()
    rows = result.data or []
    if not rows:
        raise RuntimeError(f"INSERT skill_suggestions devolveu vazio: {result!r}")
    return rows[0]['id']


# ─────────────────────────────────────────────────────────────
# RPCs admin
# ─────────────────────────────────────────────────────────────

def admin_approve_suggestion(
    admin_client: Client,
    suggestion_id: str,
    skill_name: str,
    category: str = 'general',
    mode: str = 'read_only',
    playbook_md: str = '# Playbook\n\nDefault e2e test playbook.',
    allowed_tools: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """RPC ``admin_approve_skill_suggestion`` (6 args obrigatórios).

    Cria row em ``support_skills`` + transita suggestion para
    ``approved`` ou ``implemented`` (depende implementação).
    """
    if mode not in VALID_SKILL_MODES:
        raise ValueError(
            f"mode inválido: {mode!r}. Use {VALID_SKILL_MODES}."
        )
    if allowed_tools is None:
        allowed_tools = {}

    result = admin_client.rpc(
        'admin_approve_skill_suggestion',
        {
            'p_suggestion_id': suggestion_id,
            'p_skill_name': skill_name,
            'p_category': category,
            'p_mode': mode,
            'p_playbook_md': playbook_md,
            'p_allowed_tools': allowed_tools,
        },
    ).execute()
    return result.data or {}


def admin_reject_suggestion(
    admin_client: Client,
    suggestion_id: str,
    reason: str,
) -> Dict[str, Any]:
    """RPC ``admin_reject_skill_suggestion``."""
    result = admin_client.rpc(
        'admin_reject_skill_suggestion',
        {
            'p_suggestion_id': suggestion_id,
            'p_reason': reason,
        },
    ).execute()
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Reads + asserts
# ─────────────────────────────────────────────────────────────

def get_suggestion(admin_client: Client, suggestion_id: str) -> Dict[str, Any]:
    """Lê suggestion completa por id."""
    result = (
        admin_client.table("skill_suggestions")
        .select("*")
        .eq("id", suggestion_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_skill_by_name(admin_client: Client, skill_name: str) -> Dict[str, Any]:
    """Lê suporte_skills por skill_name (assume único)."""
    result = (
        admin_client.table("support_skills")
        .select("*")
        .eq("skill_name", skill_name)
        .order("version", desc=True)
        .limit(1)
        .execute()
    )
    rows = result.data or []
    return rows[0] if rows else {}


def assert_suggestion_status(
    admin_client: Client,
    suggestion_id: str,
    expected_status: str,
) -> Dict[str, Any]:
    """Valida ``skill_suggestions.status`` igual ao esperado."""
    row = get_suggestion(admin_client, suggestion_id)
    actual = row.get('status')
    assert actual == expected_status, (
        f"suggestion status esperado {expected_status!r}, recebido {actual!r}"
    )
    return row


def assert_skill_created_from_suggestion(
    admin_client: Client,
    suggestion_id: str,
    skill_name: str,
) -> Dict[str, Any]:
    """Valida que ``admin_approve`` criou row em ``support_skills``.

    Returns:
        Row do support_skills criado.
    """
    skill = get_skill_by_name(admin_client, skill_name)
    assert skill, (
        f"esperava skill {skill_name!r} criada após approve, mas não foi encontrada"
    )
    return skill


# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────

def delete_suggestion(admin_client: Client, suggestion_id: str) -> None:
    """Apaga suggestion (cleanup pós-test)."""
    admin_client.table("skill_suggestions").delete().eq(
        "id", suggestion_id
    ).execute()


def delete_skill(admin_client: Client, skill_name: str) -> None:
    """Apaga skill por nome (cleanup pós approve)."""
    admin_client.table("support_skills").delete().eq(
        "skill_name", skill_name
    ).execute()


def cleanup_e2e_suggestions_and_skills(
    admin_client: Client,
    pattern_prefix: str = 'e2e_test_',
) -> int:
    """Apaga todas as suggestions e skills com pattern_summary começando
    em ``pattern_prefix`` (padrão de tests).

    Returns:
        Total de rows apagadas (suggestions + skills).
    """
    n_total = 0
    sugs = (
        admin_client.table("skill_suggestions")
        .select("id, suggested_skill_name")
        .like("pattern_summary", f"{pattern_prefix}%")
        .execute()
    ).data or []
    for s in sugs:
        if s.get('suggested_skill_name'):
            delete_skill(admin_client, s['suggested_skill_name'])
            n_total += 1
        delete_suggestion(admin_client, s['id'])
        n_total += 1
    return n_total
