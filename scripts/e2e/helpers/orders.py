"""Sessão 7E-A — stub do helper de orders. Implementação em 7E-B.

Funções planeadas (não implementar nesta sub-sessão):
- create_test_order(client, **kwargs) -> dict
- advance_status(client, order_id, target: OrderStatus) -> dict
- simulate_dispatch_accept(client, order_id, driver_id) -> None
- simulate_stripe_payment_succeeded(client, order_id, amount) -> None

Mantido como stub para o framework boot e o smoke test passar.
"""

from __future__ import annotations


def _not_implemented(name: str) -> None:
    raise NotImplementedError(
        f"{name}() ainda não implementado — fica para 7E-B "
        "(ver roadmap em .claude/.ai/reports/07e_a_audit.md)."
    )


def create_test_order(*args, **kwargs):
    _not_implemented("create_test_order")


def advance_status(*args, **kwargs):
    _not_implemented("advance_status")


def simulate_dispatch_accept(*args, **kwargs):
    _not_implemented("simulate_dispatch_accept")


def simulate_stripe_payment_succeeded(*args, **kwargs):
    _not_implemented("simulate_stripe_payment_succeeded")
