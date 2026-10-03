"""T60 — ``admin_approve_skill_suggestion`` cria ``support_skills`` row.

Cenário:
1. Insert suggestion pending (admin_client = service_role).
2. Login como admin_user (JWT com app_metadata.role='admin').
3. RPC ``admin_approve_skill_suggestion`` chamada via cliente authed admin.
4. Validar suggestion transitou + support_skills criada.

NOTA: a RPC verifica role via ``auth.uid()`` + metadata; service_role
puro NÃO satisfaz porque ``auth.uid()`` retorna NULL. Por isso usamos
admin_user fixture (que tem ``app_metadata.role='admin'``).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.suggestions import (
    admin_approve_suggestion,
    assert_skill_created_from_suggestion,
    delete_skill,
    delete_suggestion,
    get_suggestion,
    insert_skill_suggestion,
)


def test_t60_admin_approve_creates_support_skill(admin_client, admin_user):
    """admin_approve cria support_skills + transita suggestion."""
    skill_name = 'e2e_test_t60_skill'

    suggestion_id = insert_skill_suggestion(
        admin_client,
        pattern_summary='e2e_test_t60 — pattern para approve test',
        proposal_type='new_skill',
        zone_type='safe',
        suggested_skill_name=skill_name,
        suggested_category='general',
        suggested_mode='read_only',
        suggested_playbook_md='# Playbook\n\nResponde a perguntas X.',
        suggested_allowed_tools={'tools': ['get_order_status']},
    )

    # Login como admin_user (JWT com role='admin' em app_metadata).
    admin_authed = login_as_user(admin_user['email'], TEST_PASSWORD)
    response = admin_approve_suggestion(
        admin_authed,
        suggestion_id=suggestion_id,
        skill_name=skill_name,
        category='general',
        mode='read_only',
        playbook_md='# Playbook\n\nE2E test approved.',
        allowed_tools={'tools': ['get_order_status']},
    )
    # Resposta da RPC pode variar — apenas validamos sem erro
    assert response is not None, f"admin_approve devolveu None (esperava jsonb)"

    skill = assert_skill_created_from_suggestion(
        admin_client,
        suggestion_id=suggestion_id,
        skill_name=skill_name,
    )
    assert skill.get('skill_name') == skill_name
    assert skill.get('mode') in ('read_only', 'write', 'write_shadow', 'write_auto', 'escalate')

    suggestion = get_suggestion(admin_client, suggestion_id)
    assert suggestion.get('status') in ('approved', 'implemented'), (
        f"suggestion.status pós-approve esperado 'approved'/'implemented', "
        f"recebido {suggestion.get('status')!r}"
    )

    delete_skill(admin_client, skill_name)
    delete_suggestion(admin_client, suggestion_id)
