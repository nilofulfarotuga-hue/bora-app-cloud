"""Helpers para tests de cancelamento (Grupo 7 — T35-T38).

4 caminhos de cancelamento implementados conforme decisões Danilo
(business_rules.md §7.7, §8.3, §12.5 + decisão 2026-04-30):

- ``client_cancel_order`` — cliente via Edge Fn ``client-cancel-order``
  (taxas §8.3 escalam por tier).
- ``admin_cancel_order`` — admin via Edge Fn ``admin-cancel-order``
  (override em qualquer status, decide refund manualmente — §12.5).
- ``driver_attempt_cancel`` — estafeta via RPC ``driver_cancel_order``.
  ⚠️ Comportamento ACTUAL aceita ``pickedUp`` (BUG-7E-B-004 re-confirmado
  por Danilo: regra nova quer bloquear ``pickedUp`` + redirect suporte;
  fix em sessão futura, não em 7E-B).

Adiados para 7E-C (decisão Danilo Pergunta 4):
- ``cancel-order-with-choice`` (refund method picker iFood-like)
- ``execute-cancellation`` (orchestrator post-aprovação cancellation_requests)

Constantes §8.3 (em business_rules.ts):
- CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.00 (status created/preparing/callingDriver)
- CANCEL_FEE_AFTER_ACCEPT_EUR    = 2.50 (status driverAccepted)
- CANCEL_FEE_AFTER_PURCHASE_RATIO= 1.00 (status pickedUp/onTheWay → 100%)

⚠️ BUG-7E-B-006: stripe-webhook tinha comentário "1.50 EUR retained"
para before_dispatch — diverge da tabela §8.3 (€1.00). Investigar fora
de 7E-B.
"""
import os
from typing import Any, Dict, Tuple
import httpx
from supabase import Client

from helpers.auth import load_env


def _supabase_url() -> str:
    """Resolve ``SUPABASE_URL`` em call-time (env é carregada por ``load_env``)."""
    load_env()
    url = os.environ.get("SUPABASE_URL", "")
    if not url:
        raise RuntimeError("SUPABASE_URL ausente em env após load_env()")
    return url


# ─────────────────────────────────────────────────────────────
# Path 1 — Cliente cancela via Edge Fn client-cancel-order
# ─────────────────────────────────────────────────────────────

def client_cancel_order(
    client_authenticated: Client,
    order_id: str,
) -> Dict[str, Any]:
    """Cliente cancela pedido via Edge Fn ``client-cancel-order``.

    Auth: JWT cliente (verify_jwt=true). Edge Fn aplica fee §8.3
    consoante o tier:
    - ``before_dispatch`` (created/preparing/callingDriver) → fee €1.00
    - ``after_accept`` (driverAccepted) → fee €2.50
    - ``after_pickup`` (pickedUp/onTheWay) → 100% retido (sem refund)

    Refund Stripe é processado pela Edge Fn quando aplicável (cartão +
    payment_intent_id + PI succeeded). Caso contrário, ``charge_missing=true``.

    Test mapping:
    - T35: status=``created`` → ``tier='before_dispatch'``, ``fee_eur=1.00``.
    - T36: status=``pickedUp`` → ``tier='after_pickup'``, ``refund_eur=0``.

    Returns:
        Dict da resposta Edge Fn:
        ``{ok, tier, fee_eur, refund_eur, refund_id, charge_missing}``
        ou ``{error, ...}`` em erro HTTP.
    """
    token = getattr(client_authenticated, "_access_token", None)
    if not token:
        raise RuntimeError("cliente não autenticado — login_as_user antes")
    response = httpx.post(
        f"{_supabase_url()}/functions/v1/client-cancel-order",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={"order_id": order_id},
        timeout=10.0,
    )
    return response.json()


# ─────────────────────────────────────────────────────────────
# Path 2 — Admin cancela via Edge Fn admin-cancel-order
# ─────────────────────────────────────────────────────────────

def admin_cancel_order(
    admin_client: Client,
    order_id: str,
    reason_code: str,
    reason: str,
) -> Dict[str, Any]:
    """Admin cancela pedido em QUALQUER status via Edge Fn ``admin-cancel-order``.

    Auth: service_role JWT. §12.5 — admin override + motivo obrigatório.
    Bora decide refund manualmente (não automático — GAP-1 documentado).

    Args:
        admin_client: cliente Supabase service_role (não usado para chamada
            HTTP directa — usamos a SUPABASE_SERVICE_ROLE_KEY do env, mas
            recebemos o ``Client`` para coerência das outras assinaturas
            e testes futuros que usem ``functions.invoke``).
        order_id: id do pedido.
        reason_code: enum aceite pela Edge Fn — ``client_request``,
            ``partner_unable``, ``driver_unavailable``, ``payment_failed``,
            ``fraud_suspected``, ``address_invalid``, ``food_quality_issue``,
            ``system_error``, ``other``.
        reason: texto livre ≥ 3 chars (mostrado ao cliente em notificação).

    Test mapping T38: admin cancela qualquer status, espera ``success=true``.

    Returns:
        Dict ``{success, idempotent, order_id, previous_status, refund: {...}, notifications: {...}}``.
    """
    if len(reason.strip()) < 3:
        raise ValueError("reason precisa min 3 chars (Edge Fn valida server-side)")

    load_env()
    service_role_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not service_role_key:
        raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY ausente em env")

    response = httpx.post(
        f"{_supabase_url()}/functions/v1/admin-cancel-order",
        headers={
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        },
        json={
            "order_id": order_id,
            "reason_code": reason_code,
            "reason": reason,
        },
        timeout=10.0,
    )
    return response.json()


# ─────────────────────────────────────────────────────────────
# Path 3 — Driver tenta cancelar via RPC driver_cancel_order
# ─────────────────────────────────────────────────────────────

def driver_attempt_cancel(
    driver_authenticated: Client,
    order_id: str,
) -> Tuple[bool, Dict[str, Any]]:
    """Driver tenta cancelar pedido via RPC ``driver_cancel_order``.

    ⚠️ Comportamento ACTUAL (RE-CONFIRMADO por Danilo 2026-05-07):
    O RPC aceita ``status ∈ {'driverAccepted', 'pickedUp'}`` — body §7.7.
    A regra NOVA (não documentada ainda) quer **bloquear pickedUp** e
    redirigir o estafeta a "contactar suporte". Tests 7E-B validam o
    comportamento ACTUAL e geram entry BUG-7E-B-004 (severidade ALTA)
    com 3 fix actions:
      1. RPC: ``WHERE status = 'driverAccepted'`` (remover pickedUp).
      2. ``business_rules.md §7.7``: actualizar regra.
      3. UI estafeta: botão "Contactar suporte" quando ``pickedUp``.

    Side effects do comportamento actual:
    - Status volta a ``callingDriver``.
    - ``assigned_driver_id`` → NULL.
    - Driver é adicionado a ``tried_driver_ids``.
    - Re-dispatch automático via ``net.http_post → dispatch-engine``.

    Pré-condição: ``orders.assigned_driver_id = drivers.id::text``
    (garantido pelo PATCH B3.1 em ``helpers/dispatch.py``).

    Args:
        driver_authenticated: cliente Supabase com JWT do estafeta.
        order_id: id do pedido.

    Returns:
        Tupla ``(ok, response_dict)``. ``response_dict`` segue o shape
        ``{'ok': bool, 'error'?: str}`` devolvido pela RPC. Em excepção
        Python, devolve ``(False, {'ok': False, 'error': str(e)})``.
    """
    try:
        result = driver_authenticated.rpc(
            'driver_cancel_order',
            {'p_order_id': order_id},
        ).execute()
        data = result.data if isinstance(result.data, dict) else {}
        return (bool(data.get('ok', False)), data)
    except Exception as e:
        return (False, {'ok': False, 'error': str(e)})


# ─────────────────────────────────────────────────────────────
# Helpers utilitários — leitura pós-cancel
# ─────────────────────────────────────────────────────────────

def get_order_status(admin_client: Client, order_id: str) -> str:
    """Lê ``status`` do pedido via admin client (bypass RLS)."""
    result = (
        admin_client.table("orders")
        .select("status")
        .eq("id", order_id)
        .single()
        .execute()
    )
    return result.data.get('status', '') if result.data else ''


def get_cancel_fee_retained(admin_client: Client, order_id: str) -> float:
    """Lê ``orders.cancel_fee`` directamente (regra §8.3 fee retida).

    PATCH B4.1: corrigido em B8 — ``cancel_fee`` é COLUNA em ``orders``,
    não ``wallet_transactions.kind``. Edge Fn ``client-cancel-order``
    popula este campo conforme tier:
    - ``before_dispatch`` → 1.00
    - ``after_accept`` → 2.50
    - ``after_pickup`` → 0.00 (cliente paga 100% — ratio aplicado em
      ``refund_amount``, não ``cancel_fee``).

    Returns:
        Valor em EUR (float). 0.0 se ``cancel_fee`` for NULL.
    """
    result = (
        admin_client.table("orders")
        .select("cancel_fee")
        .eq("id", order_id)
        .single()
        .execute()
    )
    return float((result.data or {}).get('cancel_fee') or 0)


def get_order_refund_state(
    admin_client: Client,
    order_id: str,
) -> Dict[str, Any]:
    """Lê estado completo de refund/cancel do pedido.

    Returns:
        Dict com: ``refund_amount``, ``refund_method``, ``refund_id``,
        ``refund_status``, ``refunded_at``, ``cancellation_reason_code``,
        ``cancelled_by``, ``cancel_reason``. Devolve ``{}`` se pedido
        não existir.
    """
    fields = (
        "refund_amount, refund_method, refund_id, refund_status, "
        "refunded_at, cancellation_reason_code, cancelled_by, cancel_reason"
    )
    result = (
        admin_client.table("orders")
        .select(fields)
        .eq("id", order_id)
        .single()
        .execute()
    )
    return result.data or {}
