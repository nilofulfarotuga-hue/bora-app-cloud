"""T71 — Concurrent status updates (last-write-wins documentado).

Cenário:
1. Order criada em status='created'.
2. 2 admin clients tentam UPDATE simultâneo:
   - Client 1: status='preparing'
   - Client 2: status='cancelled'
3. Validar:
   - Pelo menos 1 update succeeded.
   - Status final é UM dos 2 valores tentados (não corrupção).
   - Sem deadlock/exception fatal.

Postgres garante atomicidade ao nível de row (sem optimistic lock
configurado). Comportamento: last-write-wins. Test documenta.
"""
from helpers.lifecycle import attempt_concurrent_status_updates
from helpers.orders import create_test_order, get_order_field


def test_t71_concurrent_updates_last_write_wins(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """2 UPDATEs simultâneos → 1 ganha; sem corrupção."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    # Reusa mesmo admin_client (Postgres serializa UPDATEs no nível row)
    results = attempt_concurrent_status_updates(
        admin_clients=[admin_client, admin_client],
        order_id=order_id,
        new_statuses=['preparing', 'cancelled'],
    )

    # Pelo menos 1 deve ter ok=True (Postgres aceita ambos sequencialmente).
    successful = [r for r in results if r.get('ok')]
    assert successful, (
        f"esperava ≥1 UPDATE bem-sucedido, recebido {results!r}"
    )

    # Status final = um dos 2 valores tentados (last-write-wins).
    final_status = get_order_field(admin_client, order_id, 'status')
    assert final_status in ('preparing', 'cancelled'), (
        f"status final corrompido: {final_status!r} "
        f"(esperava 'preparing' ou 'cancelled')"
    )
