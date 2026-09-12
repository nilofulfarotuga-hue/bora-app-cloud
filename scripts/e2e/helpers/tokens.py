"""Helpers para tests de tokens (Grupo 5 — T25-T29).

RPCs disponíveis (validadas via MCP em prod 2026-05-08):
- ``add_tokens(p_user_id uuid, p_role text, p_amount integer, p_order_id text)``
  → uuid (id da row inserida em ``bora_tokens``).
- ``consume_tokens(p_user_id uuid, p_amount integer)`` → boolean
  (FIFO, true se conseguiu consumir, false se balance insuficiente).
- ``get_user_tokens(p_user_id uuid)`` → integer
  (saldo total não-expirados e não-usados).
- ``admin_grant_tokens(p_user_id, p_role, p_amount, p_reason, p_validity_days)``
  → jsonb (admin grant manual com validity custom).
- ``admin_revoke_token_grant(p_token_id uuid, p_reason text)``
  → jsonb (revoga grant específico).

Tabela ``bora_tokens``:
- ``source_order_id`` é TEXT (após BUG-007 fix em 7-FIX 2026-05-07).
- ``expires_at`` default = ``now() + INTERVAL '60 days'`` em ``add_tokens``.
- ``role`` ∈ {'client', 'driver'} (CHECK constraint).

Conversão tokens (regra negócio confirmada §32.4):
- 1 token = €0.005 (meio cêntimo) ⇒ 1 cêntimo = 2 tokens (factor ×2).
- Discount máximo no checkout = 50% do total (CAP §32.4).

⚠️ ``submit_rating`` faz CAST ``p_order_id::uuid``; ``add_tokens`` aceita
TEXT directo. Não confundir.
"""
from typing import Any, Dict, Optional
from supabase import Client

# ─────────────────────────────────────────────────────────────
# Constantes
# ─────────────────────────────────────────────────────────────

#: Factor de conversão cents → tokens (1 cent gera 2 tokens).
TOKENS_PER_CENT: int = 2

#: Desconto máximo via tokens em checkout (§32.4).
MAX_DISCOUNT_PCT: float = 0.50

#: Validity default para grants automáticos (60 dias = 60 × 24 × 60 × 60 s).
DEFAULT_VALIDITY_DAYS: int = 60


# ─────────────────────────────────────────────────────────────
# Helpers base (chamadas RPC)
# ─────────────────────────────────────────────────────────────

def add_tokens(
    admin_client: Client,
    user_id: str,
    amount: int,
    role: str = 'client',
    order_id: Optional[str] = None,
) -> str:
    """Concede ``amount`` tokens ao utilizador via RPC ``add_tokens``.

    Args:
        admin_client: cliente Supabase service_role.
        user_id: UUID do destinatário.
        amount: número de tokens (positivo).
        role: ``'client'`` (default) ou ``'driver'``.
        order_id: TEXT do pedido associado (opcional — refunds passam o
            order original; grants manuais passam ``None``).

    Returns:
        UUID (string) da row criada em ``bora_tokens``.
    """
    if amount <= 0:
        raise ValueError(f"add_tokens: amount deve ser >0, recebi {amount}")
    result = admin_client.rpc(
        'add_tokens',
        {
            'p_user_id': user_id,
            'p_role': role,
            'p_amount': amount,
            'p_order_id': order_id,
        },
    ).execute()
    token_id = result.data
    if not token_id:
        raise RuntimeError(f"add_tokens devolveu vazio: {result.data!r}")
    return token_id


def consume_tokens(
    admin_client: Client,
    user_id: str,
    amount: int,
) -> bool:
    """Consome ``amount`` tokens FIFO via RPC ``consume_tokens``.

    Returns:
        ``True`` se consumiu com sucesso, ``False`` se balance insuficiente.
    """
    result = admin_client.rpc(
        'consume_tokens',
        {'p_user_id': user_id, 'p_amount': amount},
    ).execute()
    return bool(result.data)


def get_user_tokens(admin_client: Client, user_id: str) -> int:
    """Lê saldo total de tokens via RPC ``get_user_tokens``.

    Soma apenas rows com ``is_used=false`` AND ``expires_at > now()``.
    """
    result = admin_client.rpc(
        'get_user_tokens',
        {'p_user_id': user_id},
    ).execute()
    val = result.data
    return int(val) if val is not None else 0


def admin_grant_tokens(
    admin_client: Client,
    user_id: str,
    amount: int,
    reason: str,
    role: str = 'client',
    validity_days: int = DEFAULT_VALIDITY_DAYS,
) -> Dict[str, Any]:
    """Admin concede tokens manualmente via ``admin_grant_tokens``.

    Diferente de ``add_tokens``: requer JWT admin e regista ``reason`` +
    ``validity_days`` custom. Útil para campanhas / compensações.
    """
    result = admin_client.rpc(
        'admin_grant_tokens',
        {
            'p_user_id': user_id,
            'p_role': role,
            'p_amount': amount,
            'p_reason': reason,
            'p_validity_days': validity_days,
        },
    ).execute()
    return result.data or {}


# ─────────────────────────────────────────────────────────────
# Manipulação directa em bora_tokens (cleanup + setup)
# ─────────────────────────────────────────────────────────────

def reset_user_tokens(admin_client: Client, user_id: str) -> int:
    """Apaga TODAS as rows ``bora_tokens`` do utilizador (setup limpo).

    Returns:
        Número estimado de rows afectadas (best-effort).
    """
    count_result = (
        admin_client.table("bora_tokens")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .execute()
    )
    n = count_result.count or 0
    if n > 0:
        admin_client.table("bora_tokens").delete().eq("user_id", user_id).execute()
    return n


def expire_token_row(
    admin_client: Client,
    token_id: str,
) -> None:
    """Força ``expires_at`` no passado (1 dia atrás) — simula token expirado.

    Útil em T28 (consume com tokens expirados não conta).

    ⚠️ supabase-py não interpreta strings SQL como expressões — passa
    como literal. Logo usar ISO timestamp Python em vez de ``"now() - ..."``.
    """
    from datetime import datetime, timedelta, timezone
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    admin_client.table("bora_tokens").update(
        {"expires_at": past}
    ).eq("id", token_id).execute()


def count_active_tokens(
    admin_client: Client,
    user_id: str,
) -> int:
    """Conta rows ``bora_tokens`` activas (não-usadas + não-expiradas).

    Diferente de ``get_user_tokens`` que soma ``amount``: este conta rows.
    """
    result = (
        admin_client.table("bora_tokens")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .eq("is_used", False)
        .gt("expires_at", "now()")
        .execute()
    )
    return result.count or 0


# ─────────────────────────────────────────────────────────────
# Asserts
# ─────────────────────────────────────────────────────────────

def assert_tokens_balance(
    admin_client: Client,
    user_id: str,
    expected: int,
    msg: str = "",
) -> None:
    """Valida saldo total de tokens igual ao esperado."""
    actual = get_user_tokens(admin_client, user_id)
    assert actual == expected, (
        f"{msg or 'tokens balance'}: esperado {expected}, recebido {actual}"
    )


def assert_conversion_factor_2(
    refund_cents: int,
    expected_tokens: int,
) -> None:
    """Valida fórmula: tokens = (cents do split tokens) × 2.

    Para refund €X (X*100 cents) com split 80/20:
    - free_cents = round(X*100 * 0.80)
    - tokens_cents = X*100 - free_cents
    - tokens_count = tokens_cents × 2

    Args:
        refund_cents: total do refund em cents (input do split).
        expected_tokens: número de tokens esperado em ``bora_tokens.amount``.
    """
    free_cents = round(refund_cents * 0.80)
    tokens_cents = refund_cents - free_cents
    expected = tokens_cents * TOKENS_PER_CENT
    assert expected_tokens == expected, (
        f"conversion factor ×2 falhou: refund={refund_cents}c → "
        f"tokens_cents={tokens_cents} ⇒ esperava {expected} tokens, "
        f"recebido {expected_tokens}"
    )


def assert_max_discount_50pct(
    discount_cents: int,
    order_total_cents: int,
) -> None:
    """Valida CAP §32.4: discount nunca > 50% do total."""
    cap_cents = order_total_cents // 2
    assert discount_cents <= cap_cents, (
        f"discount tokens {discount_cents}c excede CAP 50% "
        f"({cap_cents}c em order de {order_total_cents}c)"
    )


def assert_token_row_shape(
    admin_client: Client,
    user_id: str,
    expected_amount: int,
    source_order_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Lê última row ``bora_tokens`` do utilizador e valida shape.

    Returns:
        Dict da row encontrada (para asserts adicionais no test).
    """
    query = (
        admin_client.table("bora_tokens")
        .select("id, user_id, role, amount, source_order_id, expires_at, is_used")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(1)
    )
    result = query.execute()
    rows = result.data or []
    assert rows, f"sem rows em bora_tokens para user_id={user_id}"
    row = rows[0]
    assert row['amount'] == expected_amount, (
        f"bora_tokens.amount esperado {expected_amount}, recebido {row['amount']}"
    )
    if source_order_id is not None:
        assert row.get('source_order_id') == source_order_id, (
            f"source_order_id esperado {source_order_id!r}, "
            f"recebido {row.get('source_order_id')!r}"
        )
    assert row.get('is_used') is False, (
        f"row recém-criada com is_used=True (esperado False): {row}"
    )
    return row
