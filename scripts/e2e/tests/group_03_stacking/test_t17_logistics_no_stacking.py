"""T17 — Stacking: logistics order (carryGroceries) não pode ser stacked.

Regra documentada (§3): logistics orders (``carryGroceries``,
``sendPackage``) consomem 100% capacity do driver — NÃO podem ser
combinadas com nada.

Cenário (comportamento ACTUAL):
1. Cria order A (carryGroceries, sem restaurant).
2. driver_a aceita A.
3. Cria order B (partner restaurant) → tenta atribuir a driver_a.
4. Documenta comportamento actual.

NOTA: ``carryGroceries`` requer ``pickup_lat/lng`` mas SEM restaurant_id
nem vendor_name (logistic puro entre 2 endereços).
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order, get_order_field


def test_t17_logistics_then_partner_documents_actual(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """1 carryGroceries + 1 partner — actual aceita ambas (Flutter capacity gap)."""
    # Logistics: carryGroceries (sem vendor, sem partner_store)
    order_logistics = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=None,
        vendor_name='E2E_LOGISTICS',  # nome livre para sendPackage/carryGroceries
        subtotal_eur=15.00,
        service_type='carryGroceries',
        is_partner_store=False,
    )
    simulate_offer_accept(admin_client, order_logistics, driver_a['id'])

    # Tenta atribuir partner order — comportamento ACTUAL aceita
    order_partner = create_test_order(
        admin_client,
        user_id=cliente_b['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    simulate_offer_accept(admin_client, order_partner, driver_a['id'])

    # Server-side aceita — guard é Flutter-only (DriverCapacityService).
    # Se este test FAIL: enforcement server-side foi implementado ✅
    assert get_order_field(admin_client, order_logistics, 'assigned_driver_id') == driver_a['id']
    assert get_order_field(admin_client, order_partner, 'assigned_driver_id') == driver_a['id'], (
        "comportamento ACTUAL aceita stacking logistics+partner server-side. "
        "Capacity guard só em Flutter (DriverCapacityService)."
    )
