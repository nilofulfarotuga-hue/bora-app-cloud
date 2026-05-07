"""T24 — Tokens conversion factor ×2 (regra correcta pós 7-FIX).

Anteriormente este test validava o BUG-7E-B-005 (factor ×20 errado).
Após a migration ``20260507223228_fix_7e_b_bug_005_bug_007_tokens_uuid_to_text``
o factor passou a ser ×2 — fórmula matemática correcta:

    1 token = €0.005 (meio cêntimo)
    ⇒ 1 cent investido em tokens gera 2 tokens

Cenário do test:
- balance=€0, refund €5 (500c) com split 80/20.
- ``free_cents`` = round(500 × 0.80) = 400.
- ``tokens_value_cents`` = 500 − 400 = 100.
- ``tokens_count`` = 100 × 2 = **200** (factor ×2).
"""
from helpers.orders import create_test_order
from helpers.wallet import assert_tokens_conversion, credit_refund_split


def test_t24_tokens_conversion_factor_2(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Refund €5 → free=€4 + tokens=200 (100c × 2)."""
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': 0}
    ).execute()

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=5.00,
    )

    result = credit_refund_split(
        admin_client,
        order_id=order_id,
        user_id=cliente_a['user_id'],
        total_cents=500,
        reason="t24_tokens_conversion_factor_2",
    )

    assert result['free_cents'] == 400, (
        f"free_cents esperado 400c (500c × 0.80), recebido {result['free_cents']}c"
    )
    # ★ 7-FIX: factor ×2 (regra correcta) — antes era ×20 (BUG-7E-B-005)
    assert_tokens_conversion(
        tokens_amount_cents=100,
        expected_tokens_count=result['tokens_count'],
    )
    assert result['tokens_count'] == 200, (
        f"BUG-7E-B-005 fixed: tokens_count esperado 200 (100c × 2), "
        f"recebido {result['tokens_count']}. Se for 2000, factor voltou a ×20."
    )
