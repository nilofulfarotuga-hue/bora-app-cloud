"""T50 — ``auto_close_no_show_reservations`` fecha reservas approved expiradas.

Cenário:
1. Cria reservation com:
   - ``status='approved'`` (já aprovada).
   - ``reserved_for = NOW − 2h`` (passou + grace 60min).
   - ``arrived_at = NULL`` (cliente não chegou).
2. Chama ``auto_close_no_show_reservations()`` (RPC CRON simulado).
3. Resposta: ``marked_no_show >= 1``.
4. Status final: ``no_show``.
"""
from helpers.reservations import (
    assert_marked_no_show,
    assert_status,
    create_test_reservation,
    delete_test_reservations,
    run_auto_close_no_show,
)


def test_t50_auto_close_marks_no_show(
    admin_client,
    cliente_a,
    restaurant_partner,
):
    """Reserva approved + reserved_for no passado → no_show via CRON."""
    delete_test_reservations(admin_client, cliente_a['user_id'])

    reservation_id = create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=-2.0,  # 2h no passado
        prepayment_cents=300,
        status='approved',
    )

    response = run_auto_close_no_show(admin_client)
    assert_marked_no_show(response, min_count=1)
    assert_status(admin_client, reservation_id, 'no_show')

    delete_test_reservations(admin_client, cliente_a['user_id'])
