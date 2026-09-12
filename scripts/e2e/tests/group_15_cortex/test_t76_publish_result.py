"""T76 â€” publish result via cortex_finish.

Confirma que cortex_finish(p_ok=true) popula resultado, custo, modelo,
finished_at e status='done'. Segunda chamada (idempotÃªncia) raises
task_nao_encontrada_ou_nao_running.
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


def test_t76_publish_result_and_idempotency(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id = enqueue(
            admin_client, tarefa="T76 publish result test", autor="test_t76"
        )
        claim_next(admin_client, "worker-t76")

        finish(
            admin_client,
            task_id,
            ok=True,
            resultado={"output": "success"},
            custo=0.0012,
            modelo="glm-5.1",
        )

        row = get_task_by_id(admin_client, task_id)
        assert row["status"] == "done"
        assert row["resultado"] == {"output": "success"}
        assert float(row["custo"]) == 0.0012
        assert row["modelo"] == "glm-5.1"
        assert row["finished_at"] is not None

        # idempotÃªncia: 2a chamada raises (ja done)
        from supabase import PostgrestAPIError

        with pytest.raises(Exception) as exc_info:
            finish(admin_client, task_id, ok=True, resultado={"dup": True})
        # PostgreSQL exception deve conter task_nao_encontrada_ou_nao_running
        msg = str(exc_info.value)
        assert (
            "task_nao_encontrada_ou_nao_running" in msg
            or "non-running" in msg.lower()
            or "not found" in msg.lower()
        ), f"unexpected error: {msg}"
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)