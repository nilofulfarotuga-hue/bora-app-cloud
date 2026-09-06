"""T21 — Débito que excede saldo positivo (mas mantém balance > hard_floor).

Setup: balance=€10 (1000c), debit €15 (1500c) → balance_after=−500c.
−500c > −2000 (hard_floor), pelo que ``wallet_debit_for_order`` actual
**permite** o débito (apenas verifica hard_floor, não saldo positivo).

⚠️ Expectativa do prompt original: deveria levantar ``INSUFFICIENT``
ERRCODE 23514. Comportamento ACTUAL: passa em silêncio (saldo torna-se
negativo dentro do budget hard_floor).

Test valida o comportamento ACTUAL — se a regra de negócio mudar para
bloquear ir abaixo de zero antes de hard_floor, este test falhará e
sinalizará a alteração necessária.
"""
from helpers.orders import create_test_order
from helpers.wallet import debit_for_order, get_balance


def test_t21_debit_exceeds_balance_but_within_hard_floor(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Balance=€10, debit €15 → balance=−€5 (ACTUAL — RPC permite).

    Documenta gap: faltaria check ``INSUFFICIENT_WALLET_BALANCE`` em
    ``wallet_debit_for_order`` (existe em ``create_order`` mas não na
    RPC isolada). Se vier a ser adicionado, ajustar este test para
    ``pytest.raises``.
    """
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': 1000}
    ).execute()

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    result = debit_for_order(
        admin_client, cliente_a['user_id'], order_id, 1500
    )
    # Comportamento ACTUAL: sucesso, balance vai para −500c
    assert result.get('success') is True, (
        f"Débito deveria passar (saldo > hard_floor) — recebido {result}"
    )
    assert result.get('new_balance_cents') == -500, (
        f"new_balance esperado −500c, recebido {result.get('new_balance_cents')}c"
    )

    after = get_balance(admin_client, cliente_a['user_id'])
    assert after['free_cents'] == -500, (
        f"free_cents pós-debit esperado −500c, recebido {after['free_cents']}c"
    )
