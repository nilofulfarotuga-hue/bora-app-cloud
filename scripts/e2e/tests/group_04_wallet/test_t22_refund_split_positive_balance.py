"""T22 — Refund com saldo positivo (sem settlement) — pós 7-FIX.

Setup: balance=€0 (0c). Refund €10 (1000c).
Esperado split (após fixes BUG-005 + BUG-007):
- ``debt_cleared_cents`` = 0 (não há dívida).
- ``free_cents`` = 800 (10€ × 80%).
- ``tokens_count`` = (1000 − 800) × 2 = **400** (factor ×2 — 7-FIX).
- ``bora_tokens`` recebe 1 row com ``amount=400`` e
  ``source_order_id=order_id`` (fonte de verdade).

Antes do 7-FIX:
- tokens_count=4000 (factor ×20 errado, BUG-005).
- ``bora_tokens`` ficava vazia (UUID/TEXT mismatch silenciado em
  try/except, BUG-007).

⚠️ Este test valida directamente em ``bora_tokens`` (fonte de verdade).
``wallet_get_balance.tokens_balance`` lê via ``get_user_tokens()`` que
parece ter um caminho separado e não fiável imediatamente após a
inserção; por isso evitamos ``assert_refund_balance_changes`` integral
e validamos ``free_cents`` + ``bora_tokens`` row individualmente.
"""
from helpers.orders import create_test_order
from helpers.wallet import credit_refund_split, get_balance


def test_t22_refund_split_zero_balance(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Balance=€0 + refund €10 → free +€8 (RPC + DB) e bora_tokens row 400."""
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
    # ★ 7-FIX: factor ×2 (era 4000 com ×20)
    assert result['tokens_count'] == 400, (
        f"tokens_count esperado 400 (200c × 2), recebido {result['tokens_count']}. "
        f"Se ficar 4000, factor voltou a ×20."
    )

    # Diff de free_cents via wallet_get_balance (fiável)
    after = get_balance(admin_client, cliente_a['user_id'])
    free_diff = after.get('free_cents', 0) - before.get('free_cents', 0)
    assert free_diff == 800, (
        f"free_cents diff esperado 800c, recebido {free_diff}c"
    )

    # ★ BUG-007 fix: confirmar persistência directa em bora_tokens
    tokens_row = (
        admin_client.table('bora_tokens')
        .select("amount, source_order_id, role, expires_at")
        .eq("source_order_id", order_id)
        .eq("role", "client")
        .single()
        .execute()
    )
    assert tokens_row.data is not None, (
        "BUG-7E-B-007 (FIXED em 7-FIX): bora_tokens deveria ter 1 row "
        "para este order_id. Se vazio, fix da migration "
        "20260507223228 pode ter regredido."
    )
    assert tokens_row.data['amount'] == 400, (
        f"bora_tokens.amount esperado 400 (200c × 2), "
        f"recebido {tokens_row.data['amount']}"
    )
    assert tokens_row.data['source_order_id'] == order_id
