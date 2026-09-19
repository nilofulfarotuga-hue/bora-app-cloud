"""T23 — Refund com saldo negativo: settlement-first + split do remanescente.

Setup: balance=−€10 (−1000c). Refund €15 (1500c).
Pipeline ``wallet_credit_refund_split``:
1. ``debt_cleared_cents`` = min(1000, 1500) = 1000 (settle dívida total).
2. ``remaining`` = 1500 − 1000 = 500.
3. Split do remaining: ``free`` = round(500 × 0.80) = 400; ``tokens_value``
   = 100; ``tokens_count`` = 100 × 20 = 2000 (factor × 20 actual).

Asserções via ``assert_refund_with_settlement`` (que valida exactamente
estas 3 fases).
"""
from helpers.orders import create_test_order
from helpers.wallet import assert_refund_with_settlement, credit_refund_split


def test_t23_refund_settles_debt_then_splits(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Balance=−€10 + refund €15 → settle €10 + split €5 (free €4 + tokens 2000).

    ⚠️ FIX B11.6: ordem do setup invertida — ``create_order`` aplica
    AUTO-SETTLEMENT quando vê balance<0 (zera-o e regista débito de
    settlement). Por isso criamos a order PRIMEIRO (com balance≥0) e só
    depois forçamos balance=-1000 via UPSERT directo, antes de chamar
    ``wallet_credit_refund_split``.
    """
    # 1) Garantir balance neutro antes de criar order
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': 0}
    ).execute()

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    # 2) Forçar balance=-1000c só agora (após order já estar criada)
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': -1000}
    ).execute()

    result = credit_refund_split(
        admin_client,
        order_id=order_id,
        user_id=cliente_a['user_id'],
        total_cents=1500,
        reason="t23_refund_with_settlement",
    )

    assert_refund_with_settlement(
        result_jsonb=result,
        balance_before_cents=-1000,
        refund_cents=1500,
    )
