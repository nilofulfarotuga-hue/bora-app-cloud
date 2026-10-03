"""T83 â€” RED_ORDER nunca executa via cortex_enqueue.

Decision 4.2: zona='vermelha' recusada em cortex_enqueue. Vermelhas ficam
em cortex_red_proposals / proposals.jsonl (file-based), nunca claimable.
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t83_red_zone_rejected_by_enqueue(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        with pytest.raises(Exception) as exc:
            enqueue(
                admin_client,
                tarefa="MUDAR tarifa TVDE para 1.0",
                zona="vermelha",
                autor="test_t83",
            )
        msg = str(exc.value)
        assert "zona_vermelha_nao_ejecutavel" in msg, (
            f"expected zona_vermelha_nao_ejecutavel; got: {msg}"
        )

        # validacao propagacional: nenhuma row cortex_tasks foi criada
        rows = admin_client.table("cortex_tasks").select("id").execute()
        assert len(rows.data) == 0, (
            f"vermelha must not appear in cortex_tasks; found {len(rows.data)} rows"
        )
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)