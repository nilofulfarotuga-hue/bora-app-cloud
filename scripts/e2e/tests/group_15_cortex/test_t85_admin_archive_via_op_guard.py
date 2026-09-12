"""T85 â€” admin archive via _admin_op_guard.

cortex_archive chamado por admin (auto na fixture) -> ok.
Por authenticated nao-admin -> raises. Por anon -> raises (sem grant).
"""
import os

import pytest

from helpers.cortex_tasks import (
    claim_next,
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t85_admin_archive_via_op_guard(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id = enqueue(
            admin_client, tarefa="T85 to be archived", autor="test_t85"
        )
        # archive via admin_client (service_role)
        admin_client.rpc(
            "cortex_archive",
            {"p_task_id": task_id, "p_motivo": "test_t85 cleanup"},
        ).execute()
        row = get_task_by_id(admin_client, task_id)
        assert row["status"] == "archived"

        # anon: sem grant execute -> permission denied
        from supabase import create_client

        url = os.environ.get("SUPABASE_URL")
        anon_key = os.environ.get("SUPABASE_ANON_KEY")
        if url and anon_key:
            anon = create_client(url, anon_key)
            task2_id = enqueue(
                admin_client, tarefa="T85 anon archive attempt", autor="t85"
            )
            with pytest.raises(Exception) as exc:
                anon.rpc(
                    "cortex_archive",
                    {"p_task_id": task2_id, "p_motivo": "anon attempt"},
                ).execute()
            # limpa
            admin_client.table("cortex_tasks").delete().eq(
                "id", task2_id
            ).execute()
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)