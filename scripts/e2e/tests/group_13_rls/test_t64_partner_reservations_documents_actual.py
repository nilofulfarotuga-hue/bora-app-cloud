"""T64 — RLS reservations SELECT (DOCUMENT_ACTUAL — privacy bug).

⚠️ Descoberta MCP: ``reservations_partner_read_all`` policy
qual=``true`` → QUALQUER partner autenticado vê TODAS as reservations
(de TODOS os restaurantes — bug PRIVACY).

Pattern DOCUMENT_ACTUAL:
- Test PASSA validando comportamento ACTUAL (partner A vê reservations
  de partner B).
- Registado como BUG-7E-D-002 em BUGS_FOUND.md.

Cenário:
1. Cria reserva para restaurant_partner (A) e restaurant_market (C).
2. Partner A login.
3. SELECT reservations → vê reservas de A E C (BUG).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    create_test_reservation,
    delete_test_reservations,
)
from helpers.rls import select_visible_reservations


def test_t64_partner_sees_other_restaurants_reservations(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    restaurant_market,
):
    """Partner A vê reservations do partner C (RLS frouxa — BUG-7E-D-002)."""
    # Cleanup prévio
    delete_test_reservations(admin_client, cliente_a['user_id'])
    delete_test_reservations(admin_client, cliente_b['user_id'])

    # Reserva no PartnerRest (A)
    create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=24.0,
    )
    # Reserva no Market (C)
    create_test_reservation(
        admin_client,
        client_user_id=cliente_b['user_id'],
        restaurant_id=restaurant_market['id'],
        hours_from_now=12.0,
    )

    # Partner A login (owner_a → PartnerRest)
    partner_a_authed = login_as_user("e2e_partner_a@boraapp.test", TEST_PASSWORD)

    visible = select_visible_reservations(partner_a_authed, limit=50)

    # Vê reservas de pelo menos 2 restaurantes diferentes
    distinct_restaurants = {r.get('restaurant_id') for r in visible}
    assert len(distinct_restaurants) >= 2, (
        f"esperava reservations de ≥2 restaurantes (BUG-7E-D-002 ACTUAL), "
        f"recebido só {distinct_restaurants}. Se test FAIL: RLS apertada ✅."
    )

    delete_test_reservations(admin_client, cliente_a['user_id'])
    delete_test_reservations(admin_client, cliente_b['user_id'])
