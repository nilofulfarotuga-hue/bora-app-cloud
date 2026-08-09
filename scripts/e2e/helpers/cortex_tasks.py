"""Helpers para testes do Cortex Tasks (F2).

Todos os testes de group_15_cortex skipam automaticamente se a tabela
`public.cortex_tasks` nao existir na DB alvo (migracao F2 ainda nao
aplicada). Quando a migracao for aplicada via MCP Supabase (por sessao
apropriada), os testes correm automaticamente.
"""
from __future__ import annotations

import os
import sys
from typing import Any

import pytest
from supabase import Client

# helpers.auth do projeto
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from helpers.auth import get_admin_client  # noqa: E402


def cortex_tasks_exists(admin: Client) -> bool:
    """Verifica se a tabela `public.cortex_tasks` existe. True se exists."""
    try:
        r = admin.table("cortex_tasks").select("id").limit(1).execute()
        return r is not None  # se nao raise, tabela existe
    except Exception:
        return False


def skip_if_no_cortex_tasks(admin: Client) -> None:
    """Pytest skip se cortex_tasks nao existe ainda."""
    if not cortex_tasks_exists(admin):
        pytest.skip(
            "cortex_tasks table does not exist — apply migration "
            "20260809120000_PROPOSTA_cortex_tasks_f2.sql via MCP Supabase first",
            allow_module_level=False,
        )


def cleanup_all_tasks(admin: Client) -> None:
    """Remove todas as rows de cortex_tasks (testes E2E nao devem deixar lixo).
    Usa service_role (admin) bypassando RLS. Ordem: archived/done/failed/queued
    primeiro, depois running (FK self-ref parent_id CASCADE resolve).
    """
    admin.table("cortex_tasks").delete().in_(
        "status", ["queued", "done", "failed", "archived"]
    ).execute()
    # se running, force-remover tambem
    admin.table("cortex_tasks").delete().eq("status", "running").execute()


def set_robot_b_enabled(admin: Client, value: bool) -> None:
    """True/False no kill switch global. Usa admin_autonomy_set_switch."""
    # admin_autonomy_set_switch e RPC authenticated; chamada via service_role
    # assume papel admin via .rpc() com service_role_key (bypass RLS)
    admin.rpc(
        "admin_autonomy_set_switch",
        {"p_key": "robot_b_enabled", "p_enabled": value},
    ).execute()


def get_robot_b_enabled(admin: Client) -> bool:
    """Le valor atual do kill switch global."""
    r = admin.rpc("admin_robot_metrics", {}).execute()
    if not r.data:
        return True
    return bool(r.data[0].get("robot_b_enabled", True))


def enqueue(
    anon_or_service: Client,
    tarefa: str,
    zona: str = "verde",
    authority_level: str = "normal",
    autor: str | None = "test",
    pid_original: str | None = None,
    parent_id: str | None = None,
    payload: Any | None = None,
    priority: int = 0,
    teto_tentativas: int = 5,
    requires_consensus: bool = False,
    dedup_key: str | None = None,
):
    """Wrapper de `cortex_enqueue`. Devolve o uuid devolvido pela RPC."""
    r = anon_or_service.rpc(
        "cortex_enqueue",
        {
            "p_tarefa": tarefa,
            "p_zona": zona,
            "p_authority_level": authority_level,
            "p_autor": autor,
            "p_pid_original": pid_original,
            "p_parent_id": parent_id,
            "p_payload": payload,
            "p_priority": priority,
            "p_teto_tentativas": teto_tentativas,
            "p_requires_consensus": requires_consensus,
            "p_dedup_key": dedup_key,
        },
    ).execute()
    return r.data[0] if r.data else None


def claim_next(anon_or_service: Client, agent: str):
    """Wrapper de `cortex_claim_next(agent)`. Devolve a row reclamada ou None."""
    r = anon_or_service.rpc("cortex_claim_next", {"p_agent": agent}).execute()
    return r.data[0] if r.data else None


def finish(
    anon_or_service: Client,
    task_id: str,
    ok: bool,
    resultado: Any | None = None,
    erro: str | None = None,
    custo: float | None = None,
    modelo: str | None = None,
):
    """Wrapper de `cortex_finish`. Devolve None se OK."""
    return anon_or_service.rpc(
        "cortex_finish",
        {
            "p_task_id": task_id,
            "p_ok": ok,
            "p_resultado": resultado,
            "p_erro": erro,
            "p_custo": custo,
            "p_modelo": modelo,
        },
    ).execute()


def get_task_by_id(admin: Client, task_id: str):
    """Le uma row via service_role (bypass RLS) para validacao."""
    r = admin.table("cortex_tasks").select("*").eq("id", task_id).limit(1).execute()
    return r.data[0] if r.data else None