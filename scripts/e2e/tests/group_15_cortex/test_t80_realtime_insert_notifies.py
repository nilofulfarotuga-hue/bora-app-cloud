"""T80 â€” Realtime insert notifica. Subscrever canal cortex_tasks; INSERT;
validar notificacao recebida dentro de timeout. Decision 4.1 (c) hÃ­brido.
"""
import asyncio
import os

import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    get_task_by_id,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t80_realtime_insert_notifies(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    realtime_ok = os.environ.get("SUPABASE_URL") and os.environ.get(
        "SUPABASE_ANON_KEY"
    )
    if not realtime_ok:
        pytest.skip("SUPABASE_URL/ANON_KEY not set; cannot test realtime")

    from supabase import acreate_client, AsyncClient

    async def _test():
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_ANON_KEY"]
        anon: AsyncClient = await acreate_client(url, key)

        notified = asyncio.Event()
        payload_holder = []

        def _on_change(payload):
            payload_holder.append(payload)
            notified.set()

        await anon.channel("test-cortex-realtime").on_postgres_changes(
            "INSERT", callback=_on_change, table="cortex_tasks"
        ).subscribe()

        # dar tempo para subscrever estar ativo
        await asyncio.sleep(2)

        # Trigger via DB insert (admin_client service_role bypass RLS)
        admin_client.table("cortex_tasks").insert({
            "tarefa": "T80 realtime test",
            "zona": "verde",
            "status": "queued",
            "autor": "test_t80",
        }).execute()

        try:
            await asyncio.wait_for(notified.wait(), timeout=10)
        except asyncio.TimeoutError:
            pytest.fail("Realtime INSERT notificaÃ§Ã£o nÃ£o chegou em 10s")

        assert payload_holder, "callback chamado mas payload vazio"
        ev = payload_holder[0]
        assert ev["eventType"] == "INSERT"
        assert ev["table"] == "cortex_tasks"
        assert "tarefa" in ev["new"]
        assert ev["new"]["tarefa"] == "T80 realtime test"

        # cleanup
        cleanup_all_tasks(admin_client)
        await anon.channel("test-cortex-realtime").unsubscribe()

    asyncio.run(_test())

    try:
        cleanup_all_tasks(admin_client)
    except Exception:
        pass
    finally:
        try:
            set_robot_b_enabled(admin_client, True)
        except Exception:
            pass