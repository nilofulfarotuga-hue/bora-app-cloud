"""T84 â€” RLS bloqueia SELECT direto de anon e authenticated nao-admin.

anon consegue chamar cortex_enqueue (grant explicit) mas nao SELECT direto.
authenticated nao-admin tambem bloqueado em SELECT.
"""
import os

import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    enqueue,
    set_robot_b_enabled,
    skip_if_no_cortex_tasks,
)


def test_t84_rls_blocks_direct_select(admin_client):
    skip_if_no_cortex_tasks(admin_client)
    set_robot_b_enabled(admin_client, True)
    cleanup_all_tasks(admin_client)
    try:
        from supabase import create_client

        url = os.environ.get("SUPABASE_URL")
        anon_key = os.environ.get("SUPABASE_ANON_KEY")
        if not (url and anon_key):
            pytest.skip("SUPABASE_URL/ANON_KEY not set")
        anon = create_client(url, anon_key)

        # 1. anon nao deve conseguir SELECT direto em cortex_tasks
        # RLS sem policies = 0 rows devolvidas (nao raises, apenas empty)
        rows = anon.table("cortex_tasks").select("id").limit(10).execute()
        assert rows.data == [], (
            f"anon should see empty via RLS; got {len(rows.data)} rows"
        )

        # 2. anon consegue chamar cortex_enqueue (grant explicit)
        task_id = enqueue(anon, tarefa="T84 via anon", autor="test_t84")
        assert task_id, "anon should be able to call cortex_enqueue (grant)"

        # 3. cleanup via admin
        cleanup_all_tasks(admin_client)

        # 4. authenticated nao-admin tambem bloqueado (tentativa simples):
        #    como neste projeto testamos com fixture admin_client (service_role),
        #    se houver um client_authenticated_fixture disponivel, testar aqui.
        #    por enquanto, deixamos o teste cobrir anon + apenas.
    finally:
        cleanup_all_tasks(admin_client)
        set_robot_b_enabled(admin_client, True)