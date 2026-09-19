"""Helpers para tests de refunds (Grupo 10 — T51-T53).

Cobre 3 caminhos de refund (Feature 1, decisão 2026-04-30):

1. **Wallet split (instantâneo)** — RPC ``wallet_credit_refund_split``:
   - 80% free balance + 20% tokens (factor ×2 ⇒ 1c → 2 tokens).
   - Fonte de truth: ``platform_settings.wallet_split_free_pct``.
   - Cobre 3 caminhos:
     a) balance ≥ 0 → split normal.
     b) balance < 0 e refund cobre dívida → settle full + split do remaining.
     c) balance < 0 e refund < dívida → tudo a settle, sem split.

2. **Stripe refund (5-10 dias)** — Edge Fn ``cancel-order-with-choice``
   com ``refund_method='stripe'``:
   - Body: ``{order_id, reason, refund_method: 'stripe'|'wallet'}``.
   - Auth: JWT cliente (verify_jwt=true).
   - Stripe.refunds.create + UPDATE orders.

3. **Admin manual (cancellation_requests path)** — Edge Fn
   ``execute-cancellation``:
   - Body: ``{request_id: uuid}``.
   - Auth: JWT admin (bora_role='admin' em JWT).
   - Pre: cancellation_request approved + refund_method.

RPCs auxiliares:
- ``compute_refund_split(p_order_id text, p_refund_eur numeric)``
  → jsonb (preview do split, sem aplicar).
- ``request_order_cancel(p_order_id text, p_reason text)``
  → cancellation_requests row (cliente cria pedido para admin rever).

Trigger ``trg_enforce_refund_cap`` (função ``_enforce_refund_cap``):
- Bloqueia ``orders.refund_amount > paid_cents`` (over-refund prevention).
- Constrain natural — não testar override directo (dispara constraint).
"""
import os
from typing import Any, Dict, Optional

import httpx
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: Default split free percentage (platform_settings.wallet_split_free_pct).
DEFAULT_SPLIT_FREE_PCT: float = 0.80

#: Refund methods válidos em ``cancel-order-with-choice``.
VALID_REFUND_METHODS = ('stripe', 'wallet')


# ─────────────────────────────────────────────────────────────
# Edge Function URL helper
# ─────────────────────────────────────────────────────────────

def _supabase_url() -> str:
    """Lê SUPABASE_URL do env (mesma estratégia que helpers/cancellation.py)."""
    url = os.getenv("SUPABASE_URL")
    if not url:
        raise RuntimeError(
            "SUPABASE_URL não encontrada no env. Corre helpers.auth.load_env() antes."
        )
    return url


# ─────────────────────────────────────────────────────────────
# RPC wrappers
# ─────────────────────────────────────────────────────────────

def credit_refund_split(
    admin_client: Client,
    order_id: str,
    user_id: str,
    total_cents: int,
    reason: str = "e2e_test_refund",
) -> Dict[str, Any]:
    """RPC ``wallet_credit_refund_split`` (split 80% free + 20% tokens).

    Args:
        order_id: TEXT (orders.id).
        user_id: UUID do cliente.
        total_cents: total a creditar (em cents).
        reason: descritivo (gravado em wallet_transactions).

    Returns:
        jsonb com ``free_cents``, ``tokens_value_cents``, ``tokens_count``,
        ``settle_cents``, ``new_balance_cents`` e similares.
    """
    result = admin_client.rpc(
        'wallet_credit_refund_split',
        {
            'p_order_id': order_id,
            'p_user_id': user_id,
            'p_total_cents': total_cents,
            'p_reason': reason,
        },
    ).execute()
    return result.data or {}


def compute_refund_split(
    admin_client: Client,
    order_id: str,
    refund_eur: float,
) -> Dict[str, Any]:
    """RPC ``compute_refund_split`` (preview, NÃO aplica)."""
    result = admin_client.rpc(
        'compute_refund_split',
        {'p_order_id': order_id, 'p_refund_eur': refund_eur},
    ).execute()
    return result.data or {}


def request_order_cancel(
    client_authed: Client,
    order_id: str,
    reason: str,
) -> Dict[str, Any]:
    """RPC ``request_order_cancel`` — cliente cria cancellation_request (admin review)."""
    result = client_authed.rpc(
        'request_order_cancel',
        {'p_order_id': order_id, 'p_reason': reason},
    ).execute()
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Edge Function wrappers
# ─────────────────────────────────────────────────────────────

def cancel_with_choice(
    client_authed: Client,
    order_id: str,
    reason: str,
    refund_method: str,
) -> Dict[str, Any]:
    """Edge Fn ``cancel-order-with-choice`` (cliente escolhe stripe/wallet).

    Body: ``{order_id, reason, refund_method}``.
    Auth: JWT cliente.

    Returns:
        Dict da resposta Edge Fn ou ``{error, ...}`` em erro HTTP.
    """
    if refund_method not in VALID_REFUND_METHODS:
        raise ValueError(
            f"refund_method inválido: {refund_method!r}. Use {VALID_REFUND_METHODS}."
        )
    token = getattr(client_authed, "_access_token", None)
    if not token:
        raise RuntimeError("cliente não autenticado — login_as_user antes")

    response = httpx.post(
        f"{_supabase_url()}/functions/v1/cancel-order-with-choice",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={
            "order_id": order_id,
            "reason": reason,
            "refund_method": refund_method,
        },
        timeout=15.0,
    )
    try:
        return response.json()
    except Exception:
        return {"error": "non_json_response", "status": response.status_code, "text": response.text}


def execute_cancellation(
    admin_authed: Client,
    request_id: str,
) -> Dict[str, Any]:
    """Edge Fn ``execute-cancellation`` (admin executa request aprovado).

    Body: ``{request_id}``.
    Auth: JWT admin (``bora_role='admin'`` em ``user_metadata`` ou
    ``role='admin'`` em ``app_metadata``).
    """
    token = getattr(admin_authed, "_access_token", None)
    if not token:
        raise RuntimeError("admin não autenticado — login_as_user antes")

    response = httpx.post(
        f"{_supabase_url()}/functions/v1/execute-cancellation",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={"request_id": request_id},
        timeout=15.0,
    )
    try:
        return response.json()
    except Exception:
        return {"error": "non_json_response", "status": response.status_code, "text": response.text}


# ─────────────────────────────────────────────────────────────
# Direct table reads (asserts)
# ─────────────────────────────────────────────────────────────

def get_order_refund_state(
    admin_client: Client,
    order_id: str,
) -> Dict[str, Any]:
    """Lê campos relevantes para refund de uma order."""
    result = (
        admin_client.table("orders")
        .select(
            "id, status, payment_method, payment_status, "
            "refund_amount, refund_method, "
            "stripe_charge_cents, wallet_applied_cents, "
            "tokens_applied_value_cents, cancel_fee, "
            "cancellation_initiator"
        )
        .eq("id", order_id)
        .single()
        .execute()
    )
    return result.data or {}


def get_cancellation_request(
    admin_client: Client,
    request_id: str,
) -> Dict[str, Any]:
    """Lê uma cancellation_request por id."""
    result = (
        admin_client.table("cancellation_requests")
        .select("*")
        .eq("id", request_id)
        .single()
        .execute()
    )
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_split_80_20(
    rpc_response: Dict[str, Any],
    total_cents: int,
    split_free_pct: float = DEFAULT_SPLIT_FREE_PCT,
) -> None:
    """Valida que o split bate com a regra 80/20 (configurável)."""
    expected_free = round(total_cents * split_free_pct)
    expected_tokens_cents = total_cents - expected_free
    actual_free = rpc_response.get('free_cents', 0) or 0
    actual_tokens_cents = rpc_response.get('tokens_value_cents', 0) or 0

    # Em balance≥0 ambos >0; em balance<0 pode haver settle a comer parte
    settle = rpc_response.get('settle_cents', 0) or 0
    if settle == 0:
        assert actual_free == expected_free, (
            f"split free esperado {expected_free}c, recebido {actual_free}c "
            f"(total={total_cents}c, pct={split_free_pct})"
        )
        assert actual_tokens_cents == expected_tokens_cents, (
            f"split tokens_cents esperado {expected_tokens_cents}c, "
            f"recebido {actual_tokens_cents}c"
        )


def assert_no_refund(
    response: Dict[str, Any],
) -> None:
    """Valida que não há refund (after_pickup tier)."""
    refund_eur = response.get('refund_eur', None)
    refund_cents = response.get('refund_cents', None)
    val = refund_eur if refund_eur is not None else (
        (refund_cents or 0) / 100.0 if refund_cents is not None else 0
    )
    assert val == 0, (
        f"esperava refund=0, recebido {val}. Response: {response!r}"
    )


def assert_refund_cap_violation(error: Exception) -> None:
    """Valida que erro vem de ``trg_enforce_refund_cap``.

    Mensagens reais (validadas em prod): ``refund_exceeds_paid: refund=X
    cents > paid=Y cents``. Aceitamos também variantes históricas.
    """
    msg = str(error).lower()
    matched = any(
        kw in msg for kw in (
            'refund_exceeds_paid', 'refund_cap', 'refund exceeds',
            'enforce_refund', '23514',
        )
    )
    assert matched, (
        f"esperava erro de trg_enforce_refund_cap, recebi: {error!r}"
    )


def assert_cancel_with_choice_success(
    response: Dict[str, Any],
    expected_refund_method: Optional[str] = None,
) -> None:
    """Valida que ``cancel-order-with-choice`` devolveu success."""
    assert 'error' not in response, (
        f"cancel-with-choice falhou: {response!r}"
    )
    assert response.get('ok') is True or response.get('success') is True, (
        f"cancel-with-choice sem ok/success: {response!r}"
    )
    if expected_refund_method:
        actual = response.get('refund_method') or response.get('method')
        assert actual == expected_refund_method, (
            f"refund_method esperado {expected_refund_method!r}, "
            f"recebido {actual!r}"
        )
