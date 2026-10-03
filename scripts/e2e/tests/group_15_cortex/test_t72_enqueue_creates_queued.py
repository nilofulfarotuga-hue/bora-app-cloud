"""T72 â€” enqueue normal cria row queued.

Confirma que cortex_enqueue com payload minimo devolve uuid e grava row
com status='queued', zona='verde', authority_level='normal', tentativa=0,
teto_tentativas=5, requires_consensus=false, dedup_key=NULL (sem enforcement).
"""
import uuid as _uuid

import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t72_enqueue_creates_queued(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id = enqueue(
            admin_client,
            tarefa="T72 criar fila cortex",
            autor="test_t72",
        )
        assert task_id, "cortex_enqueue devolveu None"
        # validate uuid parseable
        _uuid.UUID(task_id)

        row = get_task_by_id(admin_client, task_id)
        assert row["status"] == "queued"
        assert row["zona"] == "verde"
        assert row["authority_level"] == "normal"
        assert row["tentativa"] == 0
        assert row["teto_tentativas"] == 5
        assert row["requires_consensus"] is False
        assert row["dedup_key"] is None
        assert row["parent_id"] is None
        assert row["assigned_agent"] is None
        assert row["finished_at"] is None
        assert row["tarefa"] == "T72 criar fila cortex"
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)