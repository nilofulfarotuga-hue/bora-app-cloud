"""T16 — Stacking cap: tentativa de 3ª order partner ao mesmo driver.

Regra documentada (§3): partner max 2, non-partner max 3, logistics 1.

Cenário (comportamento ACTUAL):
1. Cria 3 orders partner do mesmo vendor.
2. driver_a aceita as 3 sequencialmente via ``simulate_offer_accept``.
3. Lê DB e conta orders com ``assigned_driver_id = driver_a.id`` AND
   ``status IN ('driverAccepted', 'pickedUp', 'onTheWay')``.

Comportamento esperado (regra Bora): apenas 2 orders activas.
Comportamento ACTUAL (capacity Flutter-side): pode ter 3 (FAIL legítimo).
Test documenta a divergência.
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order


def test_t16_three_partner_cap_documents_actual(
    admin_client,
    cliente_a,
    cliente_b,
    cliente_c,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """3 partner orders sequenciais — conta quantas ficam activas no driver."""
    orders = []
    for client_id in (cliente_a['user_id'], cliente_b['user_id'], cliente_c['user_id']):
        oid = create_test_order(
            admin_client,
            user_id=client_id,
            restaurant_id=restaurant_partner['id'],
            vendor_name=restaurant_partner['name'],
            subtotal_eur=10.00,
        )
        simulate_offer_accept(admin_client, oid, driver_a['id'])
        orders.append(oid)

    # Conta orders activas no driver_a
    result = (
        admin_client.table("orders")
        .select("id, status", count="exact")
        .eq("assigned_driver_id", driver_a['id'])
        .in_("status", ['driverAccepted', 'pickedUp', 'onTheWay'])
        .eq("is_test_order", True)
        .execute()
    )
    active_count = result.count or 0

    # Comportamento ACTUAL: server-side aceita 3 (capacity é Flutter-only).
    # Test documenta — se Bora implementar enforce, ajusta para `<= 2`.
    assert active_count == 3, (
        f"esperado 3 orders activas (comportamento ACTUAL — capacity "
        f"é Flutter-side via DriverCapacityService). Recebido {active_count}. "
        f"Se este test FAIL com 2: enforcement implementado server-side ✅ "
        f"(actualizar test + fechar gap §3)."
    )
