"""T59 — INSERT ``skill_suggestions`` (simula analyze-conversations Edge Fn).

Cenário:
1. INSERT directo em skill_suggestions com:
   - proposal_type='new_skill', zone_type='safe'
   - pattern_summary, sample_messages, message_count
2. Validar:
   - status='pending' (default)
   - suggested_at preenchido (default now())
"""
from helpers.suggestions import (
    assert_suggestion_status,
    delete_suggestion,
    insert_skill_suggestion,
)


def test_t59_insert_pending_suggestion_new_skill(admin_client):
    """INSERT new_skill suggestion → status='pending', suggested_at preenchido."""
    suggestion_id = insert_skill_suggestion(
        admin_client,
        pattern_summary='e2e_test_t59 — clientes perguntam preço entrega',
        sample_messages=[
            {'role': 'user', 'content': 'Quanto custa entrega para Guarda?'},
            {'role': 'user', 'content': 'A taxa de entrega é fixa?'},
        ],
        message_count=12,
        proposal_type='new_skill',
        zone_type='safe',
        suggested_skill_name='delivery_fee_query',
        suggested_category='pricing',
        suggested_mode='read_only',
    )
    assert suggestion_id, f"insert devia retornar UUID, recebeu {suggestion_id!r}"

    row = assert_suggestion_status(admin_client, suggestion_id, 'pending')
    assert row.get('suggested_at') is not None, (
        f"suggested_at devia estar preenchido, recebido NULL"
    )
    assert row.get('proposal_type') == 'new_skill'
    assert row.get('zone_type') == 'safe'

    delete_suggestion(admin_client, suggestion_id)
