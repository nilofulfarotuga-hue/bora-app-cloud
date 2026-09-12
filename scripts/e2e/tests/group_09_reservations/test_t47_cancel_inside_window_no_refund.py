"""T47 — Cliente cancela reserva <2h antes → ``cancelled_no_refund``.

Cenário:
1. Cria reservation com ``reserved_for = NOW + 1h`` (dentro window 2h).
2. Cliente_a cancela.
3. Resposta: ``will_refund=False``, ``status='cancelled_no_refund'``.

NOTA: BUG-7E-C-001 fixed via migration em 2026-05-08.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    assert_status,
    assert_will_refund,
    client_cancel_reservation,
    create_test_reservation,
    delete_test_reservations,
)


def test_t47_cancel_inside_window_no_refund(
    admin_client,
    cliente_a,
    restaurant_partner,
):
    """Cancel <2h antes → cancelled_no_refund + will_refund=False."""
    delete_test_reservations(admin_client, cliente_a['user_id'])

    reservation_id = create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=1.0,  # dentro window 2h
        prepayment_cents=300,
    )

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = client_cancel_reservation(
        client_authed,
        reservation_id=reservation_id,
        reason='última hora',
    )

    assert_will_refund(response, expected=False)
    assert_status(admin_client, reservation_id, 'cancelled_no_refund')

    delete_test_reservations(admin_client, cliente_a['user_id'])
