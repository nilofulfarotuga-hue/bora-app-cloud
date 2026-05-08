"""T48 — Partner rejeita reserva → ``rejected_refunded``.

Cenário:
1. Cria reservation status='pending'.
2. Partner owner (e2e_partner_a@boraapp.test, FK ``restaurants.user_``)
   chama ``partner_decide_reservation(accept=False)``.
3. Resposta: ``will_refund=True``, ``status='rejected_refunded'``.

NOTA: BUG-7E-C-003 fixed via migration ``20260508150100_fix_bug_7ec_003_*``
em 2026-05-08. RPC agora usa ``restaurants.user_`` FK directo (era
JOIN por email).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    assert_status,
    assert_will_refund,
    create_test_reservation,
    delete_test_reservations,
    partner_decide_reservation,
)


def test_t48_partner_reject_returns_refund(
    admin_client,
    cliente_a,
    restaurant_partner,
):
    """Partner reject → status=rejected_refunded + will_refund=True."""
    delete_test_reservations(admin_client, cliente_a['user_id'])

    reservation_id = create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=24.0,
        prepayment_cents=300,
        status='pending',
    )

    # Partner owner authed (email seed PARTNER_OWNER_SPECS, owner_a → PartnerRest).
    # Após BUG-7E-C-003 fix, RPC valida via restaurants.user_ FK (não email).
    partner_authed = login_as_user("e2e_partner_a@boraapp.test", TEST_PASSWORD)

    response = partner_decide_reservation(
        partner_authed,
        reservation_id=reservation_id,
        accept=False,
        reason='lotado',
    )

    assert_will_refund(response, expected=True)
    assert_status(admin_client, reservation_id, 'rejected_refunded')

    delete_test_reservations(admin_client, cliente_a['user_id'])
