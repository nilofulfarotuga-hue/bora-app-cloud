"""T87 â€” .md + DB coexistÃªncia: dedup_key impede dupla execuÃ§Ã£o.

Decision 4.8: caller escreve .md com missao-id E chama cortex_enqueue com
dedup_key='missao-...'. 2a cortex_enqueue mesmo dedup_key -> mesmo id.
Garante 1 execuÃ§Ã£o.
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t87_md_db_no_duplicate_execution(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        # simulacao: caller legado (.md) escreve ordem com missao-id
        missao_id = "missao-t87-abc123"
        # caller novo (DB) chama cortex_enqueue com dedup_key = same missao-id
        id_db = enqueue(
            admin_client,
            tarefa="T87 coexist - DB track",
            autor="test_t87",
            dedup_key=missao_id,
        )
        # caller legado (.md) tenta chamar cortex_enqueue com mesmo dedup_key
        id_legacy = enqueue(
            admin_client,
            tarefa="T87 coexist - legacy track same missao",
            autor="test_t87",
            dedup_key=missao_id,
        )
        # ambiguidade: ambos chamadores recebem o mesmo id
        assert id_db == id_legacy, (
            f"same dedup_key should produce same id; got {id_db} vs {id_legacy}"
        )

        # so uma row existe
        rows = admin_client.table("cortex_tasks").select("id").eq(
            "dedup_key", missao_id
        ).execute()
        assert len(rows.data) == 1, (
            f"only 1 row with dedup_key expected; found {len(rows.data)}"
        )
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)