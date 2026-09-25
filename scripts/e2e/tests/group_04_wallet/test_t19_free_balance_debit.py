"""T19 — Wallet debit retira do ``free_cents`` (caminho positivo).

Cliente_a parte com €100 (10000 cents) free + 50 tokens. Debit de €5
deve resultar em €95.

Setup determinístico via UPSERT em ``client_wallets`` para isolar este
test de outros que mexem no saldo.
"""
from helpers.orders import create_test_order
from helpers.wallet import debit_for_order, get_balance


def test_t19_free_balance_debit(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Cliente_a com €100, debit €5 → €95 free."""
    # Reset determinístico ao saldo
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': 10000}
    ).execute()

    before = get_balance(admin_client, cliente_a['user_id'])
    initial_free = before.get('free_cents', 0)
    assert initial_free == 10000, f"Setup falhou: free={initial_free}c"

    # Cria order de teste para FK em wallet_transactions
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    result = debit_for_order(
        admin_client, cliente_a['user_id'], order_id, 500
    )
    assert result.get('success') is True, f"debit_for_order falhou: {result}"
    assert result.get('debited_cents') == 500
    assert result.get('new_balance_cents') == 9500

    after = get_balance(admin_client, cliente_a['user_id'])
    assert after['free_cents'] == initial_free - 500, (
        f"free_cents esperado {initial_free - 500}c, recebido {after['free_cents']}c"
    )
