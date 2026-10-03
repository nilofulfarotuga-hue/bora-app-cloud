"""T81 â€” Poll recovery quando Realtime indisponÃ­vel. Decision 4.1 (c) hÃ­brido.

Simula Realtime DOWN: usa apenas cortex_claim_next (poll) sem subscrever canal;
validar que fila pode ser drenada via fallback.
"""
import pytest

from helpers.cortex_tasks import (
    claim_next,
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t81_poll_recovery_when_realtime_down(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        # 3 tasks na fila
        for i in range(3):
            enqueue(admin_client, tarefa=f"T81 poll test {i}", autor="test_t81")

        # poll puro (sem realtime)
        for _ in range(3):
            row = claim_next(admin_client, "worker-poll")
            assert row, "poll returned 0 rows despite queued tasks"
            assert row["status"] == "running"

        # fila drenada
        after = admin_client.table("cortex_tasks").select("id").eq(
            "status", "queued"
        ).execute()
        assert len(after.data) == 0

        # 4a poll retorna None
        final = claim_next(admin_client, "worker-poll")
        assert final is None
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)