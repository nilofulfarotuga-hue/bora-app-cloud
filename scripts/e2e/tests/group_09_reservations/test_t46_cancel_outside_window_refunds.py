"""T46 — Cliente cancela reserva >2h antes → ``cancelled_refunded``.

Cenário:
1. Cria reservation com ``reserved_for = NOW + 24h`` (>2h window).
2. Cliente_a chama ``client_cancel_reservation``.
3. Resposta: ``will_refund=True``, ``status='cancelled_refunded'``.
4. Valida ``reservations.cancelled_at`` foi preenchido.

NOTA: BUG-7E-C-001 (cast UUID em log_admin_action) foi CLOSED via
migration ``20260508150000_fix_bug_7ec_001_*`` em 2026-05-08.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    assert_cancelled_at_set,
    assert_status,
    assert_will_refund,
    client_cancel_reservation,
    create_test_reservation,
    delete_test_reservations,
)


def test_t46_cancel_outside_window_refunds(
    admin_client,
    cliente_a,
    restaurant_partner,
):
    """Cancel >2h antes → cancelled_refunded + will_refund=True."""
    delete_test_reservations(admin_client, cliente_a['user_id'])

    reservation_id = create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=24.0,
        prepayment_cents=300,
    )

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = client_cancel_reservation(
        client_authed,
        reservation_id=reservation_id,
        reason='conflito de agenda',
    )

    assert_will_refund(response, expected=True)
    assert_status(admin_client, reservation_id, 'cancelled_refunded')
    assert_cancelled_at_set(admin_client, reservation_id)

    delete_test_reservations(admin_client, cliente_a['user_id'])
