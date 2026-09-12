"""T37 — Estafeta NÃO pode cancelar ``pickedUp`` (regra §7.7 pós 7-FIX).

Anteriormente este test validava o BUG-7E-B-004 (RPC permitia cancelar
``pickedUp``). Após a migration
``20260507223338_fix_7e_b_bug_004_driver_cannot_cancel_pickedup``, o RPC
``driver_cancel_order`` rejeita explicitamente ``pickedUp`` e devolve
``error='cancel_blocked_after_pickup'`` com mensagem PT-PT que a UI
deve mapear para um botão "Contactar suporte".

Pré-requisitos:
- ``link_test_drivers_to_auth`` (PATCH B8.0) liga ``drivers.user_id`` aos
  ``auth.users`` ``@driver.bora.app``.
- ``simulate_offer_accept`` (PATCH B3.1) escreve ``assigned_driver_id``.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import driver_attempt_cancel
from helpers.dispatch import link_test_drivers_to_auth, simulate_offer_accept
from helpers.orders import advance_status, create_test_order, get_order_field


def test_t37_driver_blocked_pickedup_redirects_support(
    admin_client, cliente_a, restaurant_partner, driver_a, cleanup_test_orders
):
    """Driver autenticado em ``pickedUp`` recebe erro estruturado a redirigir suporte."""
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

    # ★ 7-FIX: comportamento ESPERADO — RPC rejeita pickedUp
    assert success is False, (
        f"BUG-7E-B-004 fixed: driver NÃO deveria conseguir cancelar pickedUp. "
        f"Se success=True, fix regrediu. Response: {response}"
    )
    assert response.get('error') == 'cancel_blocked_after_pickup', (
        f"error esperado 'cancel_blocked_after_pickup', recebido {response.get('error')!r}"
    )
    assert response.get('support_required') is True, (
        f"support_required esperado True, recebido {response.get('support_required')!r}"
    )
    assert 'suporte' in (response.get('message') or '').lower(), (
        f"message PT-PT esperada com 'suporte', recebida {response.get('message')!r}"
    )

    # Status NÃO deve mudar — pedido continua em pickedUp
    assert get_order_field(admin_client, order_id, "status") == "pickedUp", (
        "Status deveria continuar 'pickedUp' (RPC rejeitou cancel)"
    )
