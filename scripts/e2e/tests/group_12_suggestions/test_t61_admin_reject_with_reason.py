"""T61 — ``admin_reject_skill_suggestion`` regista rejection_reason.

Cenário:
1. Insert suggestion pending.
2. Login como admin_user (JWT role='admin').
3. admin_reject_skill_suggestion(id, 'duplicate of skill_X').
4. Validar status='rejected', rejection_reason, reviewed_at preenchido.

NOTA: RPC requer JWT admin (auth.uid() + metadata role check).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.suggestions import (
    admin_reject_suggestion,
    delete_suggestion,
    get_suggestion,
    insert_skill_suggestion,
)


def test_t61_admin_reject_with_reason(admin_client, admin_user):
    """admin_reject → status=rejected + rejection_reason gravado."""
    suggestion_id = insert_skill_suggestion(
        admin_client,
        pattern_summary='e2e_test_t61 — pattern para reject test',
        proposal_type='new_skill',
        zone_type='safe',
        suggested_skill_name='e2e_test_t61_skill',
    )

    # Login como admin_user (JWT com role='admin').
    admin_authed = login_as_user(admin_user['email'], TEST_PASSWORD)
    reason = 'duplicate of existing skill_X'
    response = admin_reject_suggestion(
        admin_authed,
        suggestion_id=suggestion_id,
        reason=reason,
    )
    assert response is not None, f"admin_reject devolveu None"

    row = get_suggestion(admin_client, suggestion_id)
    assert row.get('status') == 'rejected', (
        f"status pós-reject esperado 'rejected', recebido {row.get('status')!r}"
    )
    assert row.get('rejection_reason') == reason, (
        f"rejection_reason esperado {reason!r}, "
        f"recebido {row.get('rejection_reason')!r}"
    )
    assert row.get('reviewed_at') is not None, (
        f"reviewed_at devia estar preenchido após reject, recebido NULL"
    )

    delete_suggestion(admin_client, suggestion_id)
