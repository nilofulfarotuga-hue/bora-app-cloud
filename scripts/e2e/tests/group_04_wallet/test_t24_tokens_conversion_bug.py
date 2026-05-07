"""T24 — BUG-7E-B-005: factor de conversão tokens × 20 (deveria ser × 2).

Refund €1 (100c) com balance=€0:
- 80% free = 80c.
- 20% destinado a tokens = 20c.
- Tokens criados ACTUAL = 20 × 20 = **400 tokens**.
- Fórmula correcta seria 20 × 2 = **40 tokens** (confirmado por Danilo
  em 2026-05-07).

Test valida o comportamento ACTUAL. Quando a RPC for corrigida, este
test passará a falhar — sinal claro para actualizar a expectativa.
"""
from helpers.orders import create_test_order
from helpers.wallet import assert_tokens_conversion, credit_refund_split


def test_t24_tokens_conversion_factor_20(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Refund €1 → tokens_count=400 (factor × 20 ACTUAL, BUG-7E-B-005)."""
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
        total_cents=100,
        reason="t24_tokens_conversion_factor",
    )

    # 100c × 0.80 = 80c free; 20c → tokens
    assert result['free_cents'] == 80, (
        f"free_cents esperado 80c, recebido {result['free_cents']}c"
    )
    # 20c × 20 = 400 tokens (ACTUAL — BUG-7E-B-005)
    assert_tokens_conversion(
        tokens_amount_cents=20,
        expected_tokens_count=result['tokens_count'],
    )
    assert result['tokens_count'] == 400, (
        f"BUG-7E-B-005 ACTUAL: tokens_count esperado 400 "
        f"(20c × factor 20), recebido {result['tokens_count']}. "
        f"Se passar a 40, factor foi corrigido para × 2."
    )
