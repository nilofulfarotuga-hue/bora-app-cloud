"""T49 — Partner aceita reserva → ``approved``.

Cenário:
1. Cria reservation status='pending'.
2. Partner owner chama ``partner_decide_reservation(accept=True)``.
3. Resposta: ``will_refund=False`` (não há refund, foi aprovada).
4. Status final: ``approved``.
5. ``decided_at`` foi preenchido.

NOTA: BUG-7E-C-003 fixed (FK directo em vez de email JOIN).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    assert_status,
    assert_will_refund,
    create_test_reservation,
    delete_test_reservations,
    get_reservation,
    partner_decide_reservation,
)


def test_t49_partner_accept_approves(
    admin_client,
    cliente_a,
    restaurant_partner,
):
    """Partner accept → status=approved + decided_at preenchido."""
    delete_test_reservations(admin_client, cliente_a['user_id'])

    reservation_id = create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=24.0,
        prepayment_cents=300,
        status='pending',
    )

    # Partner owner authed (PARTNER_OWNER_SPECS owner_a → PartnerRest).
    partner_authed = login_as_user("e2e_partner_a@boraapp.test", TEST_PASSWORD)

    response = partner_decide_reservation(
        partner_authed,
        reservation_id=reservation_id,
        accept=True,
    )

    assert_will_refund(response, expected=False)
    assert_status(admin_client, reservation_id, 'approved')

    rsv = get_reservation(admin_client, reservation_id)
    assert rsv.get('decided_at') is not None, (
        f"decided_at devia estar preenchido após accept, recebido NULL: {rsv}"
    )

    delete_test_reservations(admin_client, cliente_a['user_id'])
