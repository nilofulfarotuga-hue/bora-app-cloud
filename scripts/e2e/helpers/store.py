"""Helpers para tests de storeShopping (Grupo 6 — T30-T34).

Funcionalidade central: ``finalize_storeshopping_purchase`` (RPC).
Schema validado via MCP em prod 2026-05-08.

Inputs:
- ``p_order_id`` (TEXT) — id da order ``service_type='storeShopping'``.
- ``p_items_status`` (jsonb array): ``[{id, purchase_status}]`` onde
  ``purchase_status`` ∈ ``{'bought', 'unavailable', 'pending'}``. Aceita
  também ``productId`` / ``product_id`` em vez de ``id``.
- ``p_items_added`` (jsonb array, default ``[]``):
  ``[{name, price_base_cents, qty, reason}]``. Driver adiciona items que
  não estavam na lista original. Markup +15% aplicado em cada um.
- ``p_bag_count`` (int, 0-5) — número de sacos. Bag fee = ``bag_count``
  × ``platform_settings.bag_fee_supermarket_per_bag_cents`` (default 10c).

Auth requirements:
- ``auth.uid()`` obrigatório (JWT driver autenticado).
- ``orders.assigned_driver_id::text == auth.uid()::text`` (caller TEM
  que ser o driver assignado ao pedido).

Pre-conditions:
- ``orders.is_purchase_finalized = false`` (raise ``already_finalized``).
- ``orders.status`` ainda não em ``pickedUp`` (trigger
  ``enforce_storeshopping_finalize_before_pickup``).

Output (jsonb):
- ``success``, ``order_id``, ``service_type``, ``is_partner_store``
- ``final_total_cents``, ``orig_total_cents``, ``paid_cents``
- ``refund_cents`` + ``refund_method`` (stripe/wallet) se final<orig
- ``extra_charge_cents`` + ``cash_extra_cents`` + ``wallet_debit_cents``
- ``bag_fee_cents``, ``bag_count``, ``items_added_count``
- ``payment_status``, ``markup_pct``, ``warning``
"""
import os
from typing import Any, Dict, List, Optional
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: Markup padrão para items adicionados pelo driver (15%).
DEFAULT_MARKUP_PCT: float = 0.15

#: Bag fee per bag (cents) — platform_settings.bag_fee_supermarket_per_bag_cents.
DEFAULT_PER_BAG_CENTS: int = 10

#: Limite warning extra charge (30% do orig).
DEFAULT_MAX_EXTRA_PCT: float = 0.30

#: Status válidos por item.
VALID_PURCHASE_STATUSES = ('bought', 'unavailable', 'pending')


# ─────────────────────────────────────────────────────────────
# Setup helpers — preparar order storeShopping
# ─────────────────────────────────────────────────────────────

def attach_items_to_order(
    admin_client: Client,
    order_id: str,
    items: List[Dict[str, Any]],
) -> None:
    """Escreve ``orders.items`` (jsonb array) directo via UPDATE.

    Cada item: ``{productId|id, name, price (EUR), quantity}``.
    O RPC ``finalize_storeshopping_purchase`` lê este array para
    calcular ``bought_total_cents`` e ``unavailable_total_cents``.

    Args:
        items: lista normalizada com chaves canónicas (compat. RPC).
    """
    admin_client.table("orders").update({"items": items}).eq("id", order_id).execute()


def assign_driver_to_order(
    admin_client: Client,
    order_id: str,
    driver_id: str,
) -> None:
    """Define ``orders.assigned_driver_id = driver_id`` (TEXT).

    Útil para pular o fluxo de dispatch e ir directo a finalize.
    Note: drivers.id == drivers.user_id == auth.uid() para fixtures E2E.
    """
    admin_client.table("orders").update(
        {"assigned_driver_id": driver_id, "driver_id": driver_id}
    ).eq("id", order_id).execute()


# ─────────────────────────────────────────────────────────────
# RPC wrapper — finalize_storeshopping_purchase
# ─────────────────────────────────────────────────────────────

def finalize_purchase(
    driver_authed_client: Client,
    order_id: str,
    items_status: List[Dict[str, Any]],
    items_added: Optional[List[Dict[str, Any]]] = None,
    bag_count: Optional[int] = None,
) -> Dict[str, Any]:
    """Chama RPC ``finalize_storeshopping_purchase`` como driver autenticado.

    Args:
        driver_authed_client: cliente Supabase com JWT do driver
            (``login_as_user`` no email sintético).
        order_id: id da order (TEXT).
        items_status: lista ``[{id, purchase_status}]``.
        items_added: lista ``[{name, price_base_cents, qty, reason}]``.
        bag_count: 0-5.

    Returns:
        dict com ``success``, ``final_total_cents``, ``refund_cents``,
        ``items_added_count`` etc. (ver docstring módulo).

    Raises:
        Exception se RPC raise (ex.: ``forbidden_not_assigned_driver``).
    """
    payload: Dict[str, Any] = {
        'p_order_id': order_id,
        'p_items_status': items_status,
        'p_items_added': items_added if items_added is not None else [],
    }
    if bag_count is not None:
        payload['p_bag_count'] = bag_count

    result = driver_authed_client.rpc(
        'finalize_storeshopping_purchase',
        payload,
    ).execute()
    return result.data or {}


def build_items_status(
    bought_ids: Optional[List[str]] = None,
    unavailable_ids: Optional[List[str]] = None,
) -> List[Dict[str, str]]:
    """Constrói payload ``p_items_status`` a partir de listas separadas.

    Útil em tests onde só interessa marcar uns como bought e outros como
    unavailable, sem replicar IDs em loops.
    """
    out: List[Dict[str, str]] = []
    for pid in (bought_ids or []):
        out.append({'id': pid, 'purchase_status': 'bought'})
    for pid in (unavailable_ids or []):
        out.append({'id': pid, 'purchase_status': 'unavailable'})
    return out


def build_added_item(
    name: str,
    price_base_cents: int,
    qty: int = 1,
    reason: str = 'driver_substitution',
) -> Dict[str, Any]:
    """Helper para construir entry em ``p_items_added``."""
    return {
        'name': name,
        'price_base_cents': price_base_cents,
        'qty': qty,
        'reason': reason,
    }


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_finalize_success(result: Dict[str, Any]) -> None:
    """Valida que finalize devolveu success=true."""
    assert result.get('success') is True, (
        f"finalize falhou: {result!r}"
    )


def assert_markup_applied(
    result: Dict[str, Any],
    item_base_cents: int,
    qty: int,
    markup_pct: float = DEFAULT_MARKUP_PCT,
) -> None:
    """Valida que items_added contribuem com markup +15% para o final_total.

    Assume que apenas items_added (sem items canonicos bought) contribuem
    para o final — usar em tests focados.
    """
    expected_added = round(item_base_cents * (1 + markup_pct)) * qty
    bag_fee = result.get('bag_fee_cents', 0) or 0
    delivery = result.get('delivery_fee_cents', 0) or 0
    service = result.get('service_fee_cents', 0) or 0
    final = result.get('final_total_cents', 0) or 0
    inferred_added = final - bag_fee - delivery - service
    assert inferred_added == expected_added, (
        f"markup +{int(markup_pct*100)}% falhou: esperava {expected_added}c "
        f"em items_added, inferido {inferred_added}c (final={final}, "
        f"bag={bag_fee}, delivery={delivery}, service={service})"
    )


def assert_refund_for_unavailable(
    result: Dict[str, Any],
    min_refund_cents: int,
) -> None:
    """Valida que ao menos ``min_refund_cents`` foram refundidos.

    Quando items são marcados ``unavailable``, o final_total fica abaixo
    do orig_total ⇒ refund_cents > 0.
    """
    refund = result.get('refund_cents', 0) or 0
    assert refund >= min_refund_cents, (
        f"refund esperado ≥{min_refund_cents}c, recebido {refund}c. "
        f"final_total_cents={result.get('final_total_cents')}, "
        f"orig_total_cents={result.get('orig_total_cents')}"
    )


def assert_bag_fee_market(
    result: Dict[str, Any],
    bag_count: int,
    per_bag_cents: int = DEFAULT_PER_BAG_CENTS,
) -> None:
    """Valida bag_fee = bag_count × per_bag_cents (default 10c)."""
    expected = bag_count * per_bag_cents
    actual = result.get('bag_fee_cents', 0) or 0
    assert actual == expected, (
        f"bag_fee storeShopping esperado {expected}c "
        f"({bag_count} sacos × {per_bag_cents}c), recebido {actual}c"
    )


def assert_finalize_blocked_after_pickup(error_or_result: Any) -> None:
    """Valida que trigger bloqueia finalize após pickedUp.

    Aceita Exception (raise via PostgREST) ou dict com error.
    """
    if isinstance(error_or_result, Exception):
        msg = str(error_or_result).lower()
        assert 'pickup' in msg or 'pickedup' in msg or 'enforce' in msg, (
            f"esperava erro relacionado com pickup, recebi: {msg}"
        )
        return
    if isinstance(error_or_result, dict) and error_or_result.get('error'):
        msg = str(error_or_result['error']).lower()
        assert 'pickup' in msg or 'pickedup' in msg, (
            f"esperava error 'pickup', recebi: {error_or_result}"
        )
        return
    raise AssertionError(
        f"esperava Exception ou dict com error, recebi: {error_or_result!r}"
    )
