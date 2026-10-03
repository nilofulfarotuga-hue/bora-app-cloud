"""T52 — Edge Fn ``cancel-order-with-choice`` com ``refund_method='wallet'``.

Cenário:
1. Order paid (status='created' = before_dispatch tier).
2. Cliente_a chama Edge Fn com ``refund_method='wallet'``.
3. Edge Fn:
   - Calcula fee €1.00 (before_dispatch tier).
   - Refund = total − fee.
   - Chama RPC ``wallet_credit_refund_split`` (instant).
4. Valida resposta e estado da order final.

NOTA: testa o caminho mais simples (before_dispatch). Tiers after_accept
e after_pickup já cobertos em T35-T36 (group_07_cancellation).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order, get_order_field
from helpers.refunds import assert_cancel_with_choice_success, cancel_with_choice


def test_t52_cancel_with_choice_wallet_path(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """before_dispatch + refund_method=wallet → split instant."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='card',
    )

    # Lê final_total real da order (inclui taxas) e marca paid coerente.
    # Edge Fn calcula refund = customer_total - fee; se stripe_charge < customer_total
    # o trigger trg_enforce_refund_cap rejeita (refund > paid).
    row = (
        admin_client.table("orders")
        .select("final_total")
        .eq("id", order_id)
        .single()
        .execute()
    ).data or {}
    final_total_eur = float(row.get('final_total') or 10.00)
    final_total_cents = round(final_total_eur * 100)

    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": final_total_cents,
        "payment_buffer_total": final_total_eur,
    }).eq("id", order_id).execute()

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = cancel_with_choice(
        client_authed,
        order_id=order_id,
        reason='cliente desistiu antes do dispatch',
        refund_method='wallet',
    )

    assert_cancel_with_choice_success(response)
    # Estado final: status='cancelled'
    final_status = get_order_field(admin_client, order_id, 'status')
    assert final_status == 'cancelled', (
        f"status final esperado 'cancelled', recebido {final_status!r}"
    )
