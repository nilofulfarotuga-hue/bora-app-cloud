"""T73 â€” dequeue moves to running.

Confirma que cortex_claim_next devolve 1 row; cortex_finish(ok) popula
done. Fila vazia devolve None (nao levanta).
"""
import pytest

from helpers.cortex_tasks import (
    claim_next,
    cleanup_all_tasks,
    enqueue,
    finish,
    get_robot_b_enabled,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t73_dequeue_moves_to_running(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id = enqueue(admin_client, tarefa="T73 dequeue test", autor="test_t73")
        row = claim_next(admin_client, agent="worker-t73")
        assert row, "claim_next returned 0 rows despite queued row"
        assert row["status"] == "running"
        assert row["assigned_agent"] == "worker-t73"
        assert row["assigned_at"] is not None
        assert row["tentativa"] == 1

        finish(admin_client, task_id, ok=True, resultado={"ok": True})
        final = get_task_by_id(admin_client, task_id)
        assert final["status"] == "done"
        assert final["resultado"] == {"ok": True}
        assert final["finished_at"] is not None

        # fila vazia apos consumir tudo
        row2 = claim_next(admin_client, agent="worker-t73b")
        assert row2 is None, "claim_next returned row despite empty queue"
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)