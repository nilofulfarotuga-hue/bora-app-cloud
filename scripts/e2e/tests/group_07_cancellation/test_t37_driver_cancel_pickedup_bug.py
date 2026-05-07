"""T37 — Driver cancela pickedUp — BUG-7E-B-004 (ACTUAL behaviour).

Regra §7.7 actual: ``driver_cancel_order`` aceita ``status ∈
{'driverAccepted', 'pickedUp'}``. Decisão Danilo 2026-05-07: deveria
**bloquear** ``pickedUp`` e redirigir o estafeta para suporte. Fix em
sessão futura — 7E-B testa apenas o comportamento ACTUAL.

Pré-requisitos:
- ``link_test_drivers_to_auth`` (PATCH B8.0) liga ``drivers.user_id`` aos
  ``auth.users`` ``@driver.bora.app``.
- ``simulate_offer_accept`` (PATCH B3.1) escreve ``assigned_driver_id``
  (validado pelo RPC).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import driver_attempt_cancel
from helpers.dispatch import link_test_drivers_to_auth, simulate_offer_accept
from helpers.orders import advance_status, create_test_order, get_order_field


def test_t37_driver_can_cancel_pickedup_bug_004(
    admin_client, cliente_a, restaurant_partner, driver_a, cleanup_test_orders
):
    """Driver autenticado em ``pickedUp`` consegue cancelar (BUG-7E-B-004 ACTUAL).

    Quando a regra for corrigida (block + redirect suporte), este test
    falhará — sinal claro para actualizar a expectativa.
    """
    link_test_drivers_to_auth(admin_client)

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    simulate_offer_accept(admin_client, order_id, driver_a['id'])
    advance_status(admin_client, order_id, 'pickedUp')

    driver_authed = login_as_user(driver_a['email'], TEST_PASSWORD)
    success, response = driver_attempt_cancel(driver_authed, order_id)

    assert success is True, (
        f"BUG-7E-B-004 (ACTUAL): driver deveria conseguir cancelar "
        f"em pickedUp. Se este assert falhar, regra §7.7 foi corrigida — "
        f"actualizar test. Response: {response}"
    )
    # Side effect: status volta a callingDriver, assigned_driver_id NULL
    assert get_order_field(admin_client, order_id, "status") == "callingDriver", (
        "Após driver cancel, status deveria voltar a 'callingDriver'"
    )
