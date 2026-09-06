"""T75 â€” SKIP LOCKED validators. Cria 5 tasks; worker A pega 1 em
transacao longa (via begin/commit supabase-python nao e direto; simulamos
fazendo claim sem liberar). worker B pega a proxima livre. SKIP LOCKED
garante saltar locked.
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


def test_t75_skip_locked(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        ids = []
        for i in range(5):
            ids.append(
                enqueue(admin_client, tarefa=f"T75 task {i}", autor="test_t75")
            )

        # worker-a pega 3 seguidas
        taken_a = []
        for _ in range(3):
            r = claim_next(admin_client, "worker-a")
            assert r, "worker-a should get a task"
            taken_a.append(r["id"])

        # worker-b pega 2
        r1 = claim_next(admin_client, "worker-b")
        assert r1, "worker-b should get a 4th task"
        r2 = claim_next(admin_client, "worker-b")
        assert r2, "worker-b should get a 5th task"

        # fila vazia
        r3 = claim_next(admin_client, "worker-b")
        assert r3 is None

        # verificacoes
        for tid in ids:
            row = get_task_by_id(admin_client, tid)
            assert row["status"] == "running", f"task {tid} not running"
            assert row["tentativa"] == 1

        # garantir que workers diferentes pegaram tasks diferentes
        all_taken = set(taken_a + [r1["id"], r2["id"]])
        assert len(all_taken) == 5, "5 unique tasks must have been claimed"
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)