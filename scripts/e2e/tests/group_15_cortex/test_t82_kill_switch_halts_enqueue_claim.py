"""T82 â€” kill switch OFF: corta enqueue + claim (nao finish).

Decision 4.9: robot_b_enabled=false -> raises KILL_SWITCH_ATIVO em
cortex_enqueue e cortex_claim_next. cortex_finish ainda funciona (deixa
drenar running).
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


def test_t82_kill_switch_halts_enqueue_claim(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    cleanup_all_tasks(admin_client)
    original = None
    try:
        original = get_robot_b_enabled(admin_client)
        # 1. setup: set true, enqueue 1, claim it
        set_robot_b_enabled(admin_client, True)
        task_id_running = enqueue(
            admin_client, tarefa="T82 task que vai running", autor="test_t82"
        )
        claim_next(admin_client, "worker-t82")

        # 2. set kill switch FALSE
        set_robot_b_enabled(admin_client, False)
        assert get_robot_b_enabled(admin_client) is False

        # 3. cortex_enqueue raises
        with pytest.raises(Exception) as exc_enqueue:
            enqueue(
                admin_client,
                tarefa="T82 should fail - kill switch",
                autor="test_t82",
            )
        assert "KILL_SWITCH_ATIVO" in str(exc_enqueue.value), str(exc_enqueue.value)

        # 4. cortex_claim_next raises (nao deve entregar trabalho)
        with pytest.raises(Exception) as exc_claim:
            claim_next(admin_client, "worker-t82b")
        assert "KILL_SWITCH_ATIVO" in str(exc_claim.value), str(exc_claim.value)

        # 5. cortex_finish ainda funciona (drenar running)
        finish(admin_client, task_id_running, ok=True, resultado={"drained": True})
        row = get_task_by_id(admin_client, task_id_running)
        assert row["status"] == "done"
    finally:
        if original is not None:
            try:
                set_robot_b_enabled(admin_client, original)
            except Exception:
                set_robot_b_enabled(admin_client, True)
        cleanup_all_tasks(admin_client)