"""Helpers para tests de reservations (Grupo 9 — T46-T50).

RPCs disponíveis (validadas via MCP em prod 2026-05-08):
- ``client_confirm_reservation_payment(p_reservation_id uuid)``
  → jsonb (após Stripe confirma; transita ``pending_payment → pending``).
- ``client_cancel_reservation(p_reservation_id uuid, p_reason text)``
  → jsonb ``{success, status, will_refund, hours_until_reservation, prepayment_pi}``.
- ``partner_decide_reservation(p_reservation_id uuid, p_accept bool, p_reason)``
  → jsonb ``{success, status, will_refund, prepayment_pi}``.
- ``auto_close_no_show_reservations()`` → jsonb ``{marked_no_show, ran_at}``
  (CRON job — fecha reservas approved sem ``arrived_at`` após
  ``reservation_no_show_grace_minutes`` (default 60min)).
- ``admin_cancel_reservation_on_behalf_of(p_reservation_id, p_reason)``.

Edge Functions:
- ``create-reservation-payment-intent`` (verify_jwt=true) — Stripe €3 prepay.
- ``admin-cancel-reservation`` (verify_jwt=true).

Status flow:
- ``pending_payment`` (após INSERT inicial)
  → ``pending`` (após Stripe + ``client_confirm_reservation_payment``)
  → ``approved`` ou ``rejected_refunded`` (via ``partner_decide_reservation``)
  → ``no_show`` (via ``auto_close_no_show_reservations`` após grace)
  → ``cancelled_refunded`` ou ``cancelled_no_refund`` (via
    ``client_cancel_reservation``).

Refund logic (``client_cancel_reservation``):
- Window: ``platform_settings.reservation_cancel_window_hours`` (default 2h).
- ``hours_until = (reserved_for - NOW()) / 3600``.
- ``will_refund = hours_until >= window_h``.
- Status: ``cancelled_refunded`` se will_refund, senão ``cancelled_no_refund``.

⚠️ Schema ``reservations``:
- ``id`` UUID (gen_random_uuid).
- ``restaurant_id`` TEXT (legacy).
- ``client_user_id`` UUID (auth.users).
- ``reserved_for`` TIMESTAMPTZ (NOT NULL, sem default).
- ``prepayment_cents`` INT (default 0).
- ``status`` TEXT (default 'pending').
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: Prepayment default em testes (€3.00).
DEFAULT_PREPAYMENT_CENTS: int = 300

#: Window cancelamento sem fee (default platform_settings).
DEFAULT_CANCEL_WINDOW_HOURS: int = 2

#: Grace period para no-show (default platform_settings).
DEFAULT_NO_SHOW_GRACE_MINUTES: int = 60


# ─────────────────────────────────────────────────────────────
# Setup — criar reservation directo via INSERT (bypass Stripe)
# ─────────────────────────────────────────────────────────────

def create_test_reservation(
    admin_client: Client,
    client_user_id: str,
    restaurant_id: str,
    hours_from_now: float = 24.0,
    people: int = 2,
    prepayment_cents: int = DEFAULT_PREPAYMENT_CENTS,
    status: str = 'pending',
    client_name: str = 'E2E Tester',
    client_phone: str = '910000000',
    notes: Optional[str] = None,
) -> str:
    """Cria reservation directamente via INSERT (bypass Stripe).

    ``status='pending'`` por default → simula payment já confirmado.
    Para testar fluxo Stripe completo, criar com ``status='pending_payment'``
    e depois chamar ``client_confirm_reservation_payment``.

    Args:
        client_user_id: UUID do cliente (auth.users).
        restaurant_id: TEXT do restaurante (E2E_TEST_*).
        hours_from_now: ``reserved_for = NOW() + hours_from_now h``.
            Negativo → no passado (útil para testar no-show).
        prepayment_cents: pré-pagamento em cents (default 300 = €3).
        status: estado inicial (default 'pending' = post-payment).

    Returns:
        UUID (str) da reservation criada.
    """
    reserved_for = (
        datetime.now(timezone.utc) + timedelta(hours=hours_from_now)
    ).isoformat()

    payload: Dict[str, Any] = {
        'restaurant_id': restaurant_id,
        'client_user_id': client_user_id,
        'people': people,
        'reserved_for': reserved_for,
        'status': status,
        'prepayment_cents': prepayment_cents,
        'client_name': client_name,
        'client_phone': client_phone,
    }
    if notes is not None:
        payload['notes'] = notes

    result = admin_client.table("reservations").insert(payload).execute()
    rows = result.data or []
    if not rows:
        raise RuntimeError(f"INSERT reservations devolveu vazio: {result!r}")
    return rows[0]['id']


def force_reserved_for(
    admin_client: Client,
    reservation_id: str,
    hours_from_now: float,
) -> None:
    """Re-escreve ``reserved_for`` (útil para alternar window de cancel)."""
    new_ts = (
        datetime.now(timezone.utc) + timedelta(hours=hours_from_now)
    ).isoformat()
    admin_client.table("reservations").update(
        {"reserved_for": new_ts}
    ).eq("id", reservation_id).execute()


# ─────────────────────────────────────────────────────────────
# RPC wrappers
# ─────────────────────────────────────────────────────────────

def client_cancel_reservation(
    client_authed: Client,
    reservation_id: str,
    reason: Optional[str] = None,
) -> Dict[str, Any]:
    """RPC ``client_cancel_reservation`` (cliente autenticado)."""
    result = client_authed.rpc(
        'client_cancel_reservation',
        {'p_reservation_id': reservation_id, 'p_reason': reason},
    ).execute()
    return result.data or {}


def partner_decide_reservation(
    partner_authed: Client,
    reservation_id: str,
    accept: bool,
    reason: Optional[str] = None,
) -> Dict[str, Any]:
    """RPC ``partner_decide_reservation`` (partner autenticado).

    Partner ownership verificado por ``restaurants.email == auth.users.email``.
    """
    result = partner_authed.rpc(
        'partner_decide_reservation',
        {
            'p_reservation_id': reservation_id,
            'p_accept': accept,
            'p_reason': reason,
        },
    ).execute()
    return result.data or {}


def run_auto_close_no_show(admin_client: Client) -> Dict[str, Any]:
    """RPC ``auto_close_no_show_reservations`` (CRON simulado).

    Returns:
        ``{marked_no_show: int, ran_at: timestamp}``.
    """
    result = admin_client.rpc('auto_close_no_show_reservations', {}).execute()
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Direct table reads (asserts)
# ─────────────────────────────────────────────────────────────

def get_reservation(
    admin_client: Client,
    reservation_id: str,
) -> Dict[str, Any]:
    """Lê reservation completa por id."""
    result = (
        admin_client.table("reservations")
        .select("*")
        .eq("id", reservation_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_status(admin_client: Client, reservation_id: str) -> str:
    """Lê apenas ``reservations.status``."""
    return (get_reservation(admin_client, reservation_id) or {}).get('status', '')


# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────

def delete_test_reservations(admin_client: Client, client_user_id: str) -> int:
    """Apaga todas as reservations de um cliente (cleanup pós-test).

    Estratégia: filtra por ``client_user_id`` para evitar tocar em rows
    de outros workers/users.
    """
    count_result = (
        admin_client.table("reservations")
        .select("id", count="exact")
        .eq("client_user_id", client_user_id)
        .execute()
    )
    n = count_result.count or 0
    if n > 0:
        admin_client.table("reservations").delete().eq(
            "client_user_id", client_user_id
        ).execute()
    return n


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_status(
    admin_client: Client,
    reservation_id: str,
    expected_status: str,
) -> None:
    """Valida ``reservations.status`` igual ao esperado."""
    actual = get_status(admin_client, reservation_id)
    assert actual == expected_status, (
        f"reservation status esperado {expected_status!r}, recebido {actual!r}"
    )


def assert_will_refund(
    rpc_response: Dict[str, Any],
    expected: bool,
) -> None:
    """Valida ``will_refund`` no resultado da RPC client_cancel/partner_decide."""
    actual = rpc_response.get('will_refund')
    assert actual is expected, (
        f"will_refund esperado {expected}, recebido {actual!r}. "
        f"Response: {rpc_response!r}"
    )


def assert_marked_no_show(
    rpc_response: Dict[str, Any],
    min_count: int = 1,
) -> None:
    """Valida que ``auto_close_no_show_reservations`` fechou ≥ ``min_count``."""
    n = rpc_response.get('marked_no_show', 0) or 0
    assert n >= min_count, (
        f"auto_close esperava ≥{min_count} no-shows, recebeu {n}"
    )


def assert_cancelled_at_set(
    admin_client: Client,
    reservation_id: str,
) -> None:
    """Valida ``cancelled_at`` foi preenchido após cancel."""
    rsv = get_reservation(admin_client, reservation_id)
    assert rsv.get('cancelled_at') is not None, (
        f"cancelled_at devia estar preenchido após cancel, "
        f"recebido NULL: {rsv}"
    )
