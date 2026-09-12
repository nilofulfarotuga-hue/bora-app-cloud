"""T04 — Cash limit €40 enforçado pelo trigger ``enforce_cash_payment_limit``.

⚠️ BUG-7E-B-001 (versão REVISTA — DOCS_VS_CODE MISMATCH, severidade LOW):
- ``business_rules.ts`` declara ``CASH_MAX_ORDER_VALUE_EUR=30.00``.
- Trigger SQL (``platform_settings.max_cash_amount_cents=4000``) enforça €40.
- Acção: confirmar com Danilo qual é o valor real e harmonizar.

Tests validam o comportamento ACTUAL (€40):
- Total ≤ €40 → cria order OK.
- Total > €40 → ``CASH_LIMIT_EXCEEDED`` ERRCODE 23514.
"""
import pytest

from helpers.orders import create_test_order


def test_t04_cash_at_limit_passes(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Cash com total dentro do limite €40 → criação sucesso.

    PATCH B6.1: subtotal=30 + service+delivery+bag ≈ €5.30 → total ~€35.30
    (validado via MCP: ``pricing_calculate('restaurant', 30.00, 2.0, false)``
    devolve customer_total ≈ €35.30, margem segura até €40).
    is_partner_store=False (subtotal directo, sem ×1.15 markup interno
    para previsibilidade do total final).
    """
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=30.00,
        payment_method='cash',
        is_partner_store=False,
        distance_km=2.0,
    )
    assert order_id, "create_test_order não devolveu order_id"


def test_t04_cash_above_limit_fails(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Cash com total > €40 → trigger levanta CASH_LIMIT_EXCEEDED."""
    with pytest.raises(Exception) as exc_info:
        create_test_order(
            admin_client,
            user_id=cliente_a['user_id'],
            restaurant_id=restaurant_partner['id'],
            vendor_name=restaurant_partner['name'],
            subtotal_eur=50.00,
            payment_method='cash',
            distance_km=2.0,
        )
    msg = str(exc_info.value)
    assert 'CASH_LIMIT_EXCEEDED' in msg or '23514' in msg, (
        f"Esperava CASH_LIMIT_EXCEEDED (ou ERRCODE 23514), recebido: {msg}"
    )
