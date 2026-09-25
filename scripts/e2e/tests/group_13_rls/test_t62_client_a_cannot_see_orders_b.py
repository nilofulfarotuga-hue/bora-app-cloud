"""T62 — Cliente_A NÃO vê orders do Cliente_B (RLS orders).

Cenário:
1. Criar 1 order para cliente_a + 1 order para cliente_b (admin).
2. Login como cliente_a.
3. SELECT orders → só vê orders próprias (filter user_id=auth.uid()).
4. Validar: zero orders alheias no resultado.

Policy esperada: ``orders_select_client`` qual=``user_id = auth.uid()``.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.rls import assert_query_returns_only_own, select_visible_orders


def test_t62_client_a_orders_isolation(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    cleanup_test_orders,
):
    """Cliente A só vê orders próprias (não vê cliente B)."""
    create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    create_test_order(
        admin_client,
        user_id=cliente_b['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=15.00,
    )

    client_a_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)

    # SELECT orders como cliente_a — deve ver apenas próprias
    result = (
        client_a_authed.table("orders")
        .select("id, user_id, status")
        .eq("is_test_order", True)
        .execute()
    )

    n_visible = assert_query_returns_only_own(
        result,
        owner_id=cliente_a['user_id'],
        key='user_id',
        msg='orders SELECT como cliente_a',
    )
    # Pelo menos 1 (a sua própria order)
    assert n_visible >= 1, (
        f"cliente_a deveria ver pelo menos 1 order própria, recebido {n_visible}"
    )
