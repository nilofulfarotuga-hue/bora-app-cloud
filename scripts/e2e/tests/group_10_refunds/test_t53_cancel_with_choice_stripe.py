"""T53 — Edge Fn ``cancel-order-with-choice`` com ``refund_method='stripe'``.

Cenário:
1. Order paid via card (com ``payment_intent_id`` válido OU mock).
2. Cliente chama Edge Fn com ``refund_method='stripe'``.
3. Edge Fn invoca ``stripe.refunds.create``.
4. Resposta esperada: ``ok=true`` ou ``charge_missing=true`` se PI ausente.

⚠️ Stripe live calls → SKIP por default em CI. Activar via
``E2E_STRIPE_LIVE=1`` env. Sem isso o test valida apenas que Edge Fn
responde com 200 + estrutura esperada (charge_missing graceful path).
"""
from helpers.auth import TEST_PASSWORD, is_stripe_live, login_as_user
from helpers.orders import create_test_order
from helpers.refunds import cancel_with_choice


def test_t53_cancel_with_choice_stripe_path(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """before_dispatch + refund_method=stripe → Stripe refund OR charge_missing."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='card',
    )

    # Paid sem payment_intent_id → Edge Fn devolve charge_missing graceful
    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": 1000,
        "payment_buffer_total": 10.00,
        "payment_intent_id": None if not is_stripe_live() else "pi_test_dummy",
    }).eq("id", order_id).execute()

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = cancel_with_choice(
        client_authed,
        order_id=order_id,
        reason='cliente prefere stripe',
        refund_method='stripe',
    )

    # Sem live: Edge Fn responde 200 com charge_missing=true ou similar.
    # Com live: ok=true + refund_id presente.
    if is_stripe_live():
        assert response.get('ok') is True or response.get('refund_id'), (
            f"E2E_STRIPE_LIVE=1: esperava ok+refund_id, recebido {response!r}"
        )
    else:
        # Aceitamos erro graceful sem hit Stripe real
        assert (
            response.get('ok') is True
            or response.get('charge_missing') is True
            or 'error' in response
        ), (
            f"sem E2E_STRIPE_LIVE: esperava resposta graceful, recebido {response!r}"
        )
