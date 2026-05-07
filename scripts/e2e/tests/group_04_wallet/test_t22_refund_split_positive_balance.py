"""T22 — Refund com saldo positivo (sem settlement).

Setup: balance=€0 (0c). Refund €10 (1000c).
Esperado split actual:
- ``debt_cleared_cents`` = 0 (não há dívida)
- ``free_cents`` = 800 (10€ × 80%)
- ``tokens_count`` = (1000 − 800) × 20 = 4000 (factor × 20 actual,
  BUG-7E-B-005)
"""
from helpers.orders import create_test_order
from helpers.wallet import (
    assert_refund_balance_changes,
    credit_refund_split,
    get_balance,
)


def test_t22_refund_split_zero_balance(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Balance=€0 + refund €10 → free +€8, tokens +4000 (factor × 20)."""
    # Reset balance a zero
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': 0}
    ).execute()

    before = get_balance(admin_client, cliente_a['user_id'])

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    result = credit_refund_split(
        admin_client,
        order_id=order_id,
        user_id=cliente_a['user_id'],
        total_cents=1000,
        reason="t22_refund_split_zero_balance",
    )
    assert result['debt_cleared_cents'] == 0
    assert result['free_cents'] == 800
    assert result['tokens_count'] == 4000

    after = get_balance(admin_client, cliente_a['user_id'])
    # Balance de partida foi zero → refund líquido = 1000c
    assert_refund_balance_changes(before, after, refund_cents=1000)
