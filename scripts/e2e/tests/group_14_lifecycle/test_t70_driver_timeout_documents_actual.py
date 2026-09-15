"""T70 — Driver accepted mas não picks up dentro de SLA (DOCUMENT_ACTUAL).

Cenário esperado pela regra de negócio:
- Driver accepted há >X minutos sem pickup → re-dispatch ou alerta.
- BR §3.5 menciona timeouts de offer (10s) mas não de pickup.

Cenário ACTUAL (observado em prod):
- Não há mecanismo automático de re-dispatch após acceptance.
- Order fica indefinidamente em 'driverAccepted' até driver agir.
- Admin pode intervir manualmente.

Pattern DOCUMENT_ACTUAL:
- Test PASSA validando comportamento ACTUAL (status NÃO muda
  automaticamente após acceptance).
- Se Bora implementar re-dispatch SLA, este test FAIL e força revisão.

NOTA: o test não força ``current_driver_offer_at`` no passado (coluna
não existe directamente em ``orders``). Em vez disso, valida que após
``simulate_offer_accept`` o status fica em 'driverAccepted' sem
intervenção externa — provando ausência de cron job auto-redispatch.
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import advance_status, create_test_order, get_order_field


def test_t70_no_auto_redispatch_on_pickup_timeout_documents_actual(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """Após accept, status fica 'driverAccepted' sem re-dispatch automático."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    advance_status(admin_client, order_id, 'preparing')
    advance_status(admin_client, order_id, 'callingDriver')
    simulate_offer_accept(admin_client, order_id, driver_a['id'])

    # Em prod NÃO há cron job a re-despachar após acceptance.
    # Status permanece 'driverAccepted' até driver/admin agir.
    actual_status = get_order_field(admin_client, order_id, 'status')
    assert actual_status == 'driverAccepted', (
        f"esperava status='driverAccepted' (sem re-dispatch automático ACTUAL); "
        f"recebido {actual_status!r}. Se este test FAIL: re-dispatch SLA "
        f"implementado server-side ✅ (actualizar test + considerar fechar gap)."
    )
