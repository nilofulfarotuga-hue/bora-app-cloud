"""T78 â€” parent/child via parent_id FK com ON DELETE CASCADE.

Confirma que enqueue pai + filho (com parent_id) grava FK, e cascade delete
remove filho quando pai Ã© removido (via cleanup, usa service_role).
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t78_parent_child_cascade_delete(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        parent_id = enqueue(
            admin_client, tarefa="T78 parent orchestrator", autor="test_t78"
        )
        child_id = enqueue(
            admin_client,
            tarefa="T78 child executor",
            autor="test_t78",
            parent_id=parent_id,
        )
        assert child_id != parent_id

        child = get_task_by_id(admin_client, child_id)
        assert child["parent_id"] == parent_id

        # cascade delete: remover parent via service_role
        admin_client.table("cortex_tasks").delete().eq("id", parent_id).execute()
        # child deve sumir (FK cascade)
        orphan = get_task_by_id(admin_client, child_id)
        assert orphan is None, (
            f"child {child_id} should have been cascade-deleted; found {orphan}"
        )
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)