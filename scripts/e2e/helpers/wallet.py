"""Helpers para tests de wallet (Grupo 4 — T19-T24).

Adaptações 7E-B audit + validação MCP em prod:

- ``client_wallets`` tem APENAS ``free_balance_cents`` — não existe
  ``promotional_balance_cents``. Tests T20-T23 originais (promo balance)
  foram reescopados para hard_floor / settlement / tokens.
- ``wallet_credit_refund_split`` tem 3 caminhos:
    a) balance ≥ 0 → split normal (80% free + 20% tokens).
    b) balance < 0 e refund cobre toda a dívida → settle full + split do
       remaining.
    c) balance < 0 e refund < dívida → tudo a settle, sem split (free=0,
       tokens=0).
- ``tokens_count = tokens_amount_cents × 2`` — fórmula matemática
  correcta (1 token = €0.005 = meio cêntimo). Fix aplicado em 7-FIX
  (migration 20260507223228) — anteriormente era ×20 (BUG-7E-B-005).
- ``hard_floor`` é dinâmico via ``platform_settings`` (default −2000c =
  −€20.00). Erro ``wallet_hard_floor_exceeded`` ERRCODE 23514.
- ``wallet_get_balance`` retorna jsonb (auto-dict via supabase-py).
"""
from typing import Any, Dict
from supabase import Client

DEFAULT_HARD_FLOOR_CENTS: int = -2000   # platform_settings.wallet_hard_floor_cents
DEFAULT_SOFT_CAP_CENTS: int = -1000     # platform_settings.wallet_max_negative_balance_cents
SPLIT_FREE_PCT: float = 0.80            # platform_settings.wallet_split_free_pct
# 7-FIX (2026-05-07): factor ×2 corrigido. 1 token = €0.005 ⇒ 1 cent ⇒ 2 tokens.
# Antes era ×20 (BUG-7E-B-005, fix em migration 20260507223228).
TOKENS_PER_CENT: int = 2


# ─────────────────────────────────────────────────────────────
# Helpers base (chamadas RPC)
# ─────────────────────────────────────────────────────────────

def get_balance(admin_client: Client, user_id: str) -> Dict[str, Any]:
    """Retorna balance dict via RPC ``wallet_get_balance``.

    Keys do return (jsonb auto-deserialized):
    ``user_id``, ``free_cents``, ``tokens_balance``,
    ``token_value_cents_x100``, ``last_transactions`` (lista jsonb).
    """
    result = admin_client.rpc(
        'wallet_get_balance',
        {'p_user_id': user_id},
    ).execute()
    return result.data


def debit_for_order(
    admin_client: Client,
    user_id: str,
    order_id: str,
    amount_cents: int,
) -> Dict[str, Any]:
    """Chama RPC ``wallet_debit_for_order``.

    Returns:
        Dict com ``success``, ``debited_cents``, ``new_balance_cents``.

    Raises:
        Exception: ``wallet_hard_floor_exceeded`` (ERRCODE 23514) se o
        débito faria ``balance_after < hard_floor``.
    """
    result = admin_client.rpc(
        'wallet_debit_for_order',
        {
            'p_user_id': user_id,
            'p_order_id': order_id,
            'p_amount_cents': amount_cents,
        },
    ).execute()
    return result.data


def credit_refund_split(
    admin_client: Client,
    order_id: str,
    user_id: str,
    total_cents: int,
    reason: str,
) -> Dict[str, Any]:
    """Chama RPC ``wallet_credit_refund_split``. ``reason`` ≥ 3 chars.

    Pipeline server-side:
    1. Se ``balance_before < 0``, deduz ``debt_cleared`` do refund.
    2. ``remaining = total_cents − debt_cleared``.
    3. Split: ``free = round(remaining × 0.80)``, ``tokens_value =
       remaining − free``, ``tokens_count = tokens_value × 20``.

    Returns:
        Dict com ``success``, ``debt_cleared_cents``, ``free_cents``,
        ``tokens_count``, ``tokens_value_cents``, ``split_pct``,
        ``balance_before_cents``.
    """
    if len(reason.strip()) < 3:
        raise ValueError("reason precisa min 3 chars (RPC valida server-side)")
    result = admin_client.rpc(
        'wallet_credit_refund_split',
        {
            'p_order_id': order_id,
            'p_user_id': user_id,
            'p_total_cents': total_cents,
            'p_reason': reason,
        },
    ).execute()
    return result.data


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_refund_with_settlement(
    result_jsonb: Dict[str, Any],
    balance_before_cents: int,
    refund_cents: int,
) -> None:
    """§28.6 valida 3 cenários de ``wallet_credit_refund_split``.

    Cenários:
    a) ``balance_before ≥ 0`` → ``debt_cleared=0``; full split.
    b) ``-balance_before ≥ refund`` → ``debt_cleared=refund``; sem split
       (``free=0``, ``tokens_count=0``).
    c) ``0 < -balance_before < refund`` → settle parcial; split do
       ``remaining``.

    Args:
        result_jsonb: jsonb devolvido pela RPC.
        balance_before_cents: saldo antes (pode ser negativo).
        refund_cents: total do refund pedido.
    """
    expected_debt = max(0, min(-balance_before_cents, refund_cents))
    assert result_jsonb['debt_cleared_cents'] == expected_debt, (
        f"debt_cleared esperado {expected_debt}c, "
        f"recebido {result_jsonb['debt_cleared_cents']}c"
    )
    remaining = refund_cents - expected_debt
    expected_free = round(remaining * SPLIT_FREE_PCT)
    expected_tokens_value = remaining - expected_free
    expected_tokens_count = expected_tokens_value * TOKENS_PER_CENT
    assert result_jsonb['free_cents'] == expected_free, (
        f"free_cents esperado {expected_free}c "
        f"(remaining={remaining}c × 0.80), "
        f"recebido {result_jsonb['free_cents']}c"
    )
    assert result_jsonb['tokens_count'] == expected_tokens_count, (
        f"tokens_count esperado {expected_tokens_count} "
        f"({expected_tokens_value}c × 20), "
        f"recebido {result_jsonb['tokens_count']}"
    )


def assert_tokens_conversion(
    tokens_amount_cents: int,
    expected_tokens_count: int,
) -> None:
    """Valida ``tokens_count = tokens_amount_cents × 2`` (regra correcta pós 7-FIX).

    Matemática: 1 token = €0.005 ⇒ 1 cent investido em tokens deve gerar
    2 tokens (1c / 0.5c = 2). Fix em 7-FIX (migration 20260507223228)
    corrigiu o factor que estava em ×20 (BUG-7E-B-005).
    """
    expected = tokens_amount_cents * TOKENS_PER_CENT
    assert expected_tokens_count == expected, (
        f"tokens_count esperado {expected} "
        f"({tokens_amount_cents}c × {TOKENS_PER_CENT}), "
        f"recebido {expected_tokens_count}"
    )


def assert_refund_balance_changes(
    before: Dict[str, Any],
    after: Dict[str, Any],
    refund_cents: int,
) -> None:
    """Valida diff de saldos pós-refund usando snapshots ``wallet_get_balance``.

    Schema real (auto-deserialized via supabase-py):
    ``{user_id, free_cents, tokens_balance, token_value_cents_x100,
    last_transactions}``.

    Em refund de ``refund_cents`` líquido (já após settlement parcial,
    se aplicável), espera-se:
    - ``free_diff = round(refund_cents × 0.80)`` (saldo livre).
    - ``tokens_diff = (refund_cents − free_diff) × 20`` — factor × 20 é o
      comportamento ACTUAL (BUG-7E-B-005 confirmado por Danilo:
      fórmula correcta seria × 2).

    Args:
        before: snapshot ``wallet_get_balance`` antes do refund.
        after: snapshot ``wallet_get_balance`` depois do refund.
        refund_cents: valor LÍQUIDO em cents (após settlement). Caller
            é responsável por descontar a dívida saldada.
    """
    free_diff = after.get('free_cents', 0) - before.get('free_cents', 0)
    tokens_diff = after.get('tokens_balance', 0) - before.get('tokens_balance', 0)
    expected_free = round(refund_cents * SPLIT_FREE_PCT)
    expected_tokens_value_cents = refund_cents - expected_free
    expected_tokens_count = expected_tokens_value_cents * TOKENS_PER_CENT
    assert free_diff == expected_free, (
        f"free_cents diff esperado {expected_free}c "
        f"(refund {refund_cents}c × 0.80), recebido {free_diff}c"
    )
    assert tokens_diff == expected_tokens_count, (
        f"tokens_balance diff esperado {expected_tokens_count} "
        f"({expected_tokens_value_cents}c × {TOKENS_PER_CENT}), "
        f"recebido {tokens_diff}"
    )


def assert_split_80_20(
    before: Dict[str, Any],
    after: Dict[str, Any],
    refund_cents: int,
) -> None:
    """DEPRECATED — usar ``assert_refund_balance_changes``."""
    return assert_refund_balance_changes(before, after, refund_cents)


def assert_hard_floor_blocks(
    admin_client: Client,
    user_id: str,
    order_id: str,
    attempted_debit_cents: int,
    expected_floor_cents: int = DEFAULT_HARD_FLOOR_CENTS,
) -> None:
    """Valida que débito que rebenta o hard floor levanta excepção.

    A RPC ``wallet_debit_for_order`` deve devolver
    ``RAISE wallet_hard_floor_exceeded`` (ERRCODE 23514) sempre que
    ``balance_after < expected_floor_cents``.

    Pré-requisito: o chamador é responsável por preparar
    ``balance_before`` tal que o débito tentado rebente o piso. O
    helper NÃO faz setup do saldo.

    Args:
        admin_client: cliente Supabase service_role.
        user_id: UUID do utilizador alvo.
        order_id: id do pedido (referência para wallet_transactions).
        attempted_debit_cents: montante a debitar (positivo).
        expected_floor_cents: piso esperado (ler de
            ``platform_settings.wallet_hard_floor_cents``).
    """
    try:
        result = admin_client.rpc(
            'wallet_debit_for_order',
            {
                'p_user_id': user_id,
                'p_order_id': order_id,
                'p_amount_cents': attempted_debit_cents,
            },
        ).execute()
        raise AssertionError(
            f"Esperava excepção wallet_hard_floor_exceeded "
            f"(floor={expected_floor_cents}c, débito={attempted_debit_cents}c) "
            f"mas RPC devolveu: {result.data}"
        )
    except AssertionError:
        raise
    except Exception as e:
        msg = str(e)
        assert 'wallet_hard_floor_exceeded' in msg, (
            f"Esperava 'wallet_hard_floor_exceeded' (ERRCODE 23514), "
            f"recebido: {msg}"
        )
