"""T51 — Trigger ``_enforce_refund_cap`` bloqueia ``refund_amount > paid_cents``.

Cenário:
1. Order paid via card: ``stripe_charge_cents=500`` (€5).
2. Tentar UPDATE ``refund_amount=10.0`` (=1000c, > paid).
3. Trigger raise ``refund_exceeds_paid: refund=1000 > paid=500 ...``
   (ERRCODE 23514).

Cobre TODO 7E-C grupo 10: ``incluindo trg_enforce_refund_cap``.
"""
import pytest

from helpers.orders import create_test_order
from helpers.refunds import assert_refund_cap_violation


def test_t51_trg_enforce_refund_cap_blocks_overrefund(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """refund_amount > paid_cents → trigger raise."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=5.00,
        payment_method='card',
    )

    # Marca paid com €5 (500c)
    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": 500,
        "wallet_applied_cents": 0,
        "tokens_applied_value_cents": 0,
    }).eq("id", order_id).execute()

    # Tenta UPDATE refund=€10 (1000c) > paid 500c → trigger bloqueia
    with pytest.raises(Exception) as exc_info:
        admin_client.table("orders").update(
            {"refund_amount": 10.0}
        ).eq("id", order_id).execute()

    assert_refund_cap_violation(exc_info.value)
