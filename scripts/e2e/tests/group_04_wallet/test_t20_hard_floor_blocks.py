"""T20 — ``wallet_debit_for_order`` rejeita débitos que cruzam o hard floor.

Hard floor configurado em ``platform_settings.wallet_hard_floor_cents``
(default −2000c = −€20.00). Setup: balance=−€8 (−800c). Tentar debitar
€15 (1500c) → balance_after = −2300c < −2000 → ``RAISE
wallet_hard_floor_exceeded`` ERRCODE 23514.
"""
from helpers.wallet import assert_hard_floor_blocks


def test_t20_hard_floor_blocks_excess_debit(admin_client, cliente_a):
    """Balance=−€8 + debit €15 → balance_after=−€23 cruza floor → exception."""
    # Setup balance directo via UPSERT (admin bypass)
    admin_client.table('client_wallets').upsert(
        {'user_id': cliente_a['user_id'], 'free_balance_cents': -800}
    ).execute()

    # Validação: debit 1500c (€15) levanta wallet_hard_floor_exceeded
    assert_hard_floor_blocks(
        admin_client,
        user_id=cliente_a['user_id'],
        order_id="T20_hard_floor_test_pseudo_order",
        attempted_debit_cents=1500,
        expected_floor_cents=-2000,
    )
