"""Helpers para tests de Row Level Security (Grupo 13 — T62-T66).

Estratégia: usar ``login_as_user`` (helpers/auth.py) para criar cliente
Supabase autenticado com JWT do utilizador. Tentar SELECT/UPDATE em
tabelas sensíveis e validar que RLS bloqueia (PostgrestError ou
resultado vazio/filtrado).

Diferente de ``admin_client`` (service_role bypass RLS): aqui usamos
clientes user-authed que respeitam policies.

⚠️ DESCOBERTAS RLS via MCP (validadas em prod 2026-05-08):

1. ``drivers_select_authenticated`` qual = ``auth.uid() IS NOT NULL``
   → QUALQUER driver autenticado vê TODOS os drivers (RLS frouxa).
   T63 documenta este BUG como ACTUAL behaviour.

2. ``reservations_partner_read_all`` qual = ``true``
   → QUALQUER partner autenticado vê TODAS as reservations.
   T64 documenta este BUG (PRIVACY).

Tests T63/T64 usam pattern ``DOCUMENT_ACTUAL`` em vez de pattern
``EXPECTED`` — registar bugs em BUGS_FOUND.md sem tentar fixar.
"""
from typing import Any, Callable, List, Optional

from supabase import Client


# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

# Tabelas sensíveis que devem ter RLS apertada.
SENSITIVE_TABLES = (
    'orders',
    'client_wallets',
    'wallet_transactions',
    'bora_tokens',
    'driver_transactions',
    'ratings',
    'reservations',
    'support_chatbot_messages',
)


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_rls_denied(
    callable_fn: Callable[[], Any],
    expected_codes: tuple = ('42501', 'PGRST116', '401'),
) -> Exception:
    """Captura excepção esperada de RLS deny.

    Usar em contexto onde a query DEVE falhar (ex.: anon a fazer SELECT
    em tabela com RLS estrita).

    Args:
        callable_fn: lambda/closure que executa a query.
        expected_codes: códigos aceitos no erro (PostgREST varia).

    Returns:
        A excepção apanhada (para inspecção adicional).
    """
    try:
        callable_fn()
    except Exception as e:
        msg = str(e).lower()
        if any(code.lower() in msg for code in expected_codes):
            return e
        # Aceitar qualquer erro relacionado com RLS/auth/permission
        if 'rls' in msg or 'permission' in msg or 'denied' in msg or 'unauthorized' in msg:
            return e
        raise AssertionError(
            f"esperava RLS deny (codes {expected_codes}), recebi: {e!r}"
        )
    raise AssertionError(
        f"esperava RLS deny mas callable não levantou exception"
    )


def assert_query_returns_empty(query_result: Any, msg: str = "") -> None:
    """Valida que ``result.data`` é lista vazia (RLS filtrou tudo)."""
    data = getattr(query_result, 'data', None)
    if data is None and isinstance(query_result, dict):
        data = query_result.get('data')
    assert data == [] or data is None, (
        f"{msg or 'query'} esperava [] (RLS filtrou), recebi: {data!r}"
    )


def assert_query_returns_only_own(
    query_result: Any,
    owner_id: str,
    key: str = 'user_id',
    msg: str = "",
) -> int:
    """Valida que TODAS as rows retornadas têm ``row[key] == owner_id``.

    Returns:
        Número de rows retornadas (0+).
    """
    data = getattr(query_result, 'data', None) or []
    foreign_rows = [r for r in data if r.get(key) != owner_id]
    assert not foreign_rows, (
        f"{msg or 'query'} retornou {len(foreign_rows)} rows alheias "
        f"(esperava só {key}={owner_id}). Exemplos: "
        f"{foreign_rows[:3]!r}"
    )
    return len(data)


def assert_query_returns_others(
    query_result: Any,
    owner_id: str,
    key: str = 'user_id',
    msg: str = "",
) -> int:
    """Valida que retornou rows ALHEIAS (RLS frouxa — bug actual).

    Pattern ``DOCUMENT_ACTUAL`` para T63/T64: prova que vê dados de
    outros utilizadores. Usar quando o BUG já é conhecido e o test
    serve para fail-safe se algum dia for corrigido.

    Returns:
        Número de rows alheias detectadas.
    """
    data = getattr(query_result, 'data', None) or []
    foreign_rows = [r for r in data if r.get(key) != owner_id]
    assert foreign_rows, (
        f"{msg or 'query'} esperava rows alheias (RLS frouxa documentada) "
        f"mas retornou só próprias. data={data!r}"
    )
    return len(foreign_rows)


# ─────────────────────────────────────────────────────────────
# Builders — anonymous client (sem JWT)
# ─────────────────────────────────────────────────────────────

def build_anon_client() -> Client:
    """Cliente Supabase com anon key apenas (sem JWT user).

    Usado em T66 para validar que tabelas sensíveis bloqueiam anon.
    """
    import os
    from supabase import create_client

    url = os.getenv("SUPABASE_URL")
    anon_key = os.getenv("SUPABASE_ANON_KEY")
    if not url or not anon_key:
        raise RuntimeError(
            "SUPABASE_URL ou SUPABASE_ANON_KEY ausentes. "
            "Corre helpers.auth.load_env() primeiro."
        )
    return create_client(url, anon_key)


# ─────────────────────────────────────────────────────────────
# Atalhos para tests
# ─────────────────────────────────────────────────────────────

def select_visible_orders(
    client_authed: Client,
    limit: int = 100,
) -> List[dict]:
    """SELECT em ``orders`` com cliente user-authed (RLS aplicado)."""
    result = (
        client_authed.table("orders")
        .select("id, user_id, status")
        .limit(limit)
        .execute()
    )
    return result.data or []


def select_visible_drivers(
    client_authed: Client,
    limit: int = 100,
) -> List[dict]:
    """SELECT em ``drivers`` com cliente user-authed."""
    result = (
        client_authed.table("drivers")
        .select("id, name, user_id")
        .limit(limit)
        .execute()
    )
    return result.data or []


def select_visible_reservations(
    client_authed: Client,
    limit: int = 100,
) -> List[dict]:
    """SELECT em ``reservations`` com cliente user-authed."""
    result = (
        client_authed.table("reservations")
        .select("id, restaurant_id, client_user_id, status")
        .limit(limit)
        .execute()
    )
    return result.data or []
