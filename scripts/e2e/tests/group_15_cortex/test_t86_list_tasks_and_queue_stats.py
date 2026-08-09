"""T86 â€” cortex_list_tasks e cortex_queue_stats.

Valida outputs esperados das duas RPCs admin.
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t86_list_tasks_and_queue_stats(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        for i in range(3):
            enqueue(admin_client, tarefa=f"T86 task {i}", autor="test_t86")

        # cortex_list_tasks sem filter -> paginado
        r = admin_client.rpc(
            "cortex_list_tasks",
            {"p_status": None, "p_limit": 5, "p_offset": 0},
        ).execute()
        assert r.data is not None
        tasks = r.data if isinstance(r.data, list) else r.data[0]
        assert isinstance(tasks, list)
        # 3 tasks queued criadas por este teste
        assert len(tasks) >= 3

        # cortex_queue_stats
        s = admin_client.rpc("cortex_queue_stats", {}).execute()
        assert s.data is not None
        stats = s.data[0] if isinstance(s.data, list) else s.data
        assert isinstance(stats, dict)
        assert "pending_count" in stats
        assert "running_count" in stats
        assert "oldest_queued_age_min" in stats
        assert stats["pending_count"] >= 3
        assert stats["running_count"] == 0
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)