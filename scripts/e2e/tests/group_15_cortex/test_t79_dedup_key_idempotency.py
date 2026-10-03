"""T79 â€” dedup_key idempotencia opt-in.

Confirma que 2 enqueues com mesmo dedup_key devolvem o mesmo id (ON CONFLICT
DO NOTHING). Sem dedup_key, mÃºltiplas rows permitidas.
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t79_dedup_key_idempotency(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        # com dedup_key â€” primeira chamada cria
        id_1 = enqueue(
            admin_client,
            tarefa="T79 dedup task",
            autor="test_t79",
            dedup_key="prop-deadbeef-t79",
        )
        # segunda chamada mesmo dedup_key â€” deve devolver o mesmo id
        id_2 = enqueue(
            admin_client,
            tarefa="T79 dedup task (replay)",
            autor="test_t79",
            dedup_key="prop-deadbeef-t79",
        )
        assert id_1 == id_2, (
            f"idempotent enqueue should return same id; got {id_1} vs {id_2}"
        )

        # Sem dedup_key â€” mÃºltiplas rows permitidas
        id_a = enqueue(admin_client, tarefa="T79 no key 1", autor="t")
        id_b = enqueue(admin_client, tarefa="T79 no key 2", autor="t")
        assert id_a != id_b

        rows_a = admin_client.table("cortex_tasks").select("id").eq(
            "tarefa", "T79 no key 1"
        ).execute()
        rows_b = admin_client.table("cortex_tasks").select("id").eq(
            "tarefa", "T79 no key 2"
        ).execute()
        assert len(rows_a.data) == 1
        assert len(rows_b.data) == 1

        # total: 3 rows (1 dedup_key shared + 2 sem key)
        all_rows = admin_client.table("cortex_tasks").select("id").execute()
        ids_set = {r["id"] for r in all_rows.data}
        assert len(ids_set) == 3
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)