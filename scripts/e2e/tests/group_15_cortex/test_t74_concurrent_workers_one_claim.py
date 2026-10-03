"""T74 â€” dois workers concorrentes, somente um claim.

Cria 1 task; dois workers fazem claim_next em paralelo (threads). SKIPLocked garante que apenas um obtem a row; o outro devolve None.
"""
import threading

import pytest

from helpers.cortex_tasks import (
    claim_next,
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t74_concurrent_workers_one_claim(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        task_id = enqueue(admin_client, tarefa="T74 concurrent test", autor="test_t74")
        results = {"worker_a": None, "worker_b": None}
        errors = []

        def claim(worker_name):
            try:
                r = claim_next(admin_client, worker_name)
                results[worker_name] = r
            except Exception as e:
                errors.append((worker_name, e))

        t1 = threading.Thread(target=claim, args=("worker_a",))
        t2 = threading.Thread(target=claim, args=("worker_b",))
        t1.start(); t2.start()
        t1.join(timeout=15); t2.join(timeout=15)
        assert not errors, f"claim_next threads raised: {errors}"

        # Apenas um worker obtem a row
        a = results["worker_a"]
        b = results["worker_b"]
        assert (a is not None) ^ (b is not None), (
            f"exactly one worker should win; a={a}, b={b}"
        )
        winner = a if a else b
        assert winner["assigned_agent"] in {"worker_a", "worker_b"}
        assert winner["status"] == "running"
        # row ainda running no DB
        db_row = get_task_by_id(admin_client, task_id)
        assert db_row["status"] == "running"
        assert db_row["tentativa"] == 1
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)