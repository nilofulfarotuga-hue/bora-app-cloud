"""T64 — RLS reservations partner SELECT (validação policy nova).

✅ BUG-7E-D-002 FIXED 2026-05-08 (migration
``20260508160000_fix_bug_7ed_002_reservations_partner_rls_rgpd``).

Antes: ``reservations_partner_read_all`` qual=``true`` → partner via
TODAS as reservations (bug RGPD).

Agora: ``reservations_partner_read_own`` qual=
``restaurant_id IN (SELECT id FROM restaurants WHERE user_ = auth.uid())``.

Pattern: assertion **invertida** após fix — valida que partner SÓ vê
reservas dos seus restaurantes (compliance RGPD).

Cenário:
1. Cria reserva no PartnerRest (owner_a) — visível.
2. Cria reserva no Market (owner_c) — NÃO visível para owner_a.
3. Partner A login → SELECT reservations.
4. Validar: todas as rows visíveis têm ``restaurant_id`` ∈ owner_a.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.reservations import (
    create_test_reservation,
    delete_test_reservations,
)
from helpers.rls import select_visible_reservations


def test_t64_partner_only_sees_own_restaurants_reservations(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    restaurant_market,
):
    """Partner A vê SÓ reservas do PartnerRest (não vê Market)."""
    # Cleanup prévio
    delete_test_reservations(admin_client, cliente_a['user_id'])
    delete_test_reservations(admin_client, cliente_b['user_id'])

    # Reserva no PartnerRest (A) — owner_a deve ver
    create_test_reservation(
        admin_client,
        client_user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        hours_from_now=24.0,
    )
    # Reserva no Market (C) — owner_a NÃO deve ver
    create_test_reservation(
        admin_client,
        client_user_id=cliente_b['user_id'],
        restaurant_id=restaurant_market['id'],
        hours_from_now=12.0,
    )

    # Partner A login (owner_a → PartnerRest, FK restaurants.user_)
    partner_a_authed = login_as_user("e2e_partner_a@boraapp.test", TEST_PASSWORD)

    visible = select_visible_reservations(partner_a_authed, limit=50)

    # Após BUG-7E-D-002 fix: TODAS as rows visíveis têm restaurant_id
    # do PartnerRest. Market reserva NÃO aparece (RGPD compliance).
    foreign = [r for r in visible if r.get('restaurant_id') != restaurant_partner['id']]
    assert not foreign, (
        f"BUG-7E-D-002 regressão: partner A vê reservas alheias "
        f"({len(foreign)} rows). Esperado: SÓ {restaurant_partner['id']}. "
        f"Foreign sample: {foreign[:3]!r}"
    )

    # Confirmar que viu pelo menos a sua própria (não silent-fail)
    own = [r for r in visible if r.get('restaurant_id') == restaurant_partner['id']]
    assert own, (
        f"partner A não vê nem a sua própria reserva (test data issue?): "
        f"visible={visible!r}"
    )

    delete_test_reservations(admin_client, cliente_a['user_id'])
    delete_test_reservations(admin_client, cliente_b['user_id'])
