"""Helpers para tests de lifecycle (Grupo 14 — T67-T71).

Orchestra o ciclo completo de uma order:
``created → preparing → callingDriver → driverAccepted → pickedUp →
onTheWay → delivered``.

Reusa primitives de:
- ``helpers/orders.py`` (create_test_order, advance_status, get_order)
- ``helpers/dispatch.py`` (simulate_offer_accept)
- ``helpers/cancellation.py`` (client_cancel_order, admin_cancel_order)

NÃO reimplementa lógica — apenas compõe sequências.

Status flow oficial (CLAUDE.md):
- ``created`` → ``preparing`` ou ``rejected`` (partner accept/reject)
- ``preparing`` → ``callingDriver`` (partner ready)
- ``callingDriver`` → ``driverAccepted`` (driver accept)
- ``driverAccepted`` → ``pickedUp``
- ``pickedUp`` → ``onTheWay``
- ``onTheWay`` → ``delivered``
"""
from typing import Any, Dict, List, Optional

from supabase import Client

from helpers.dispatch import simulate_offer_accept
from helpers.orders import advance_status, create_test_order, get_order


# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: Sequência completa do happy path (5 transições).
HAPPY_PATH_SEQUENCE = [
    'preparing',
    'callingDriver',
    'driverAccepted',  # via simulate_offer_accept (não advance_status)
    'pickedUp',
    'onTheWay',
    'delivered',
]

#: Steps válidos para cancelamento (group_07_cancellation já cobre pickedUp/onTheWay).
CANCEL_STEPS_PRE_PICKUP = (
    'created', 'preparing', 'callingDriver', 'driverAccepted'
)


# ─────────────────────────────────────────────────────────────
# Happy path
# ─────────────────────────────────────────────────────────────

def run_happy_path(
    admin_client: Client,
    user_id: str,
    restaurant_id: str,
    vendor_name: str,
    driver_id: str,
    subtotal_eur: float = 10.00,
    payment_method: str = 'cash',
) -> str:
    """Executa happy path completo: create → delivered. Retorna order_id.

    Pipeline:
    1. ``create_test_order`` (status default='created').
    2. advance ``preparing`` → ``callingDriver``.
    3. ``simulate_offer_accept`` (driverAccepted + 4 campos).
    4. advance ``pickedUp`` → ``onTheWay`` → ``delivered``.
    """
    order_id = create_test_order(
        admin_client,
        user_id=user_id,
        restaurant_id=restaurant_id,
        vendor_name=vendor_name,
        subtotal_eur=subtotal_eur,
        payment_method=payment_method,
    )

    # Status default em create_order é 'created'. Avançar.
    advance_status(admin_client, order_id, 'preparing')
    advance_status(admin_client, order_id, 'callingDriver')

    # Driver accept (preenche driver_id, assigned_driver_id, current_offer)
    simulate_offer_accept(admin_client, order_id, driver_id)

    advance_status(admin_client, order_id, 'pickedUp')
    advance_status(admin_client, order_id, 'onTheWay')
    advance_status(admin_client, order_id, 'delivered')

    return order_id


# ─────────────────────────────────────────────────────────────
# Cancel a meio do flow
# ─────────────────────────────────────────────────────────────

def advance_to_step(
    admin_client: Client,
    order_id: str,
    target_step: str,
    driver_id: Optional[str] = None,
) -> None:
    """Avança order_id desde estado actual até ``target_step``.

    Para ``driverAccepted`` em diante, requer ``driver_id`` (usado em
    simulate_offer_accept).
    """
    current = (get_order(admin_client, order_id) or {}).get('status', 'created')
    flow = ['created', 'preparing', 'callingDriver', 'driverAccepted',
            'pickedUp', 'onTheWay', 'delivered']
    try:
        cur_idx = flow.index(current)
        target_idx = flow.index(target_step)
    except ValueError:
        raise ValueError(
            f"step inválido (current={current!r}, target={target_step!r})"
        )

    for i in range(cur_idx + 1, target_idx + 1):
        next_step = flow[i]
        if next_step == 'driverAccepted':
            if not driver_id:
                raise ValueError(
                    "advance_to_step('driverAccepted') requer driver_id"
                )
            simulate_offer_accept(admin_client, order_id, driver_id)
        else:
            advance_status(admin_client, order_id, next_step)


# ─────────────────────────────────────────────────────────────
# Asserts lifecycle
# ─────────────────────────────────────────────────────────────

def assert_status_terminal(
    admin_client: Client,
    order_id: str,
    expected_status: str,
) -> Dict[str, Any]:
    """Valida ``orders.status`` final igual ao esperado."""
    order = get_order(admin_client, order_id)
    actual = order.get('status')
    assert actual == expected_status, (
        f"status final esperado {expected_status!r}, recebido {actual!r}"
    )
    return order


def assert_delivered_at_set(
    admin_client: Client,
    order_id: str,
) -> None:
    """Valida ``orders.delivered_at`` foi preenchido (happy path final)."""
    order = get_order(admin_client, order_id)
    assert order.get('delivered_at') is not None, (
        f"delivered_at devia estar preenchido, recebido NULL: order_id={order_id}"
    )


def assert_driver_assigned(
    admin_client: Client,
    order_id: str,
    expected_driver_id: str,
) -> None:
    """Valida ``orders.assigned_driver_id`` + ``driver_id`` coerentes."""
    order = get_order(admin_client, order_id)
    assert order.get('assigned_driver_id') == expected_driver_id, (
        f"assigned_driver_id esperado {expected_driver_id!r}, "
        f"recebido {order.get('assigned_driver_id')!r}"
    )
    assert order.get('driver_id') == expected_driver_id, (
        f"driver_id esperado {expected_driver_id!r}, "
        f"recebido {order.get('driver_id')!r}"
    )


def assert_lifecycle_invariants(
    admin_client: Client,
    order_id: str,
    expected_final_status: str = 'delivered',
) -> Dict[str, Any]:
    """Validações end-to-end após happy path:
    - ``status == expected_final_status``
    - ``delivered_at`` preenchido (se delivered)
    - ``current_driver_offer_id`` definido
    - ``cancelled_at`` NULL (não foi cancelado)

    Returns:
        Order completa para asserts adicionais.
    """
    order = get_order(admin_client, order_id)
    assert order.get('status') == expected_final_status, (
        f"status final esperado {expected_final_status!r}, "
        f"recebido {order.get('status')!r}"
    )
    if expected_final_status == 'delivered':
        assert order.get('delivered_at') is not None, (
            f"delivered_at deveria estar preenchido"
        )
    assert order.get('cancelled_at') is None, (
        f"cancelled_at deveria ser NULL no happy path, "
        f"recebido {order.get('cancelled_at')!r}"
    )
    return order


# ─────────────────────────────────────────────────────────────
# Concurrent updates (T71)
# ─────────────────────────────────────────────────────────────

def attempt_concurrent_status_updates(
    admin_clients: List[Client],
    order_id: str,
    new_statuses: List[str],
) -> List[Dict[str, Any]]:
    """Tenta UPDATEs simultâneos do status com diferentes admin clients.

    Não é verdadeiramente concurrent (Python GIL + sync), mas testa
    last-write-wins / race-condition behaviour. Retorna list de
    resultados ou erros.
    """
    if len(admin_clients) != len(new_statuses):
        raise ValueError(
            "admin_clients e new_statuses devem ter o mesmo tamanho"
        )
    results = []
    for client, status in zip(admin_clients, new_statuses):
        try:
            res = client.table("orders").update(
                {"status": status}
            ).eq("id", order_id).execute()
            results.append({"ok": True, "status_attempted": status, "data": res.data})
        except Exception as e:
            results.append({"ok": False, "status_attempted": status, "error": str(e)})
    return results
