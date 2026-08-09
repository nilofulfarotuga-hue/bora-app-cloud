"""T77 â€” retry Ã© explicito via nova enqueue, nao automatico via DB.

F2 nao tem requeue (failed -> queued automatico). Validar que cortex_finish
com ok=false deixa status='failed' e nova enqueue cria nova row.
"""
import pytest

from helpers.cortex_tasks import (
    claim_next,
    cleanup_all_tasks,
    enqueue,
    finish,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t77_retry_via_new_enqueue_not_requeue(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id_1 = enqueue(
            admin_client, tarefa="T77 attempt 1", autor="test_t77"
        )
        claim_next(admin_client, "worker-t77")
        finish(admin_client, task_id_1, ok=False, erro="transient failure")

        row1 = get_task_by_id(admin_client, task_id_1)
        assert row1["status"] == "failed"
        assert row1["erro"] == "transient failure"
        assert row1["tentativa"] == 1

        # nova enqueue = nova row (sem auto-requeue)
        task_id_2 = enqueue(
            admin_client, tarefa="T77 attempt 2", autor="test_t77", dedup_key=None
        )
        assert task_id_2 != task_id_1

        row2 = get_task_by_id(admin_client, task_id_2)
        assert row2["status"] == "queued"
        assert row2["tentativa"] == 0

        # fila ainda tem 1 row queued (a nova), 1 failed (velha)
        from helpers.cortex_tasks import claim_next as _claim
        nxt = _claim(admin_client, "worker-t77b")
        assert nxt is not None
        assert nxt["id"] == task_id_2
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)