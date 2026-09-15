"""T29 — ``add_tokens`` cria grant com expires_at default 60 dias.

Cenário:
1. Reset tokens.
2. add_tokens(amount=200) → row em bora_tokens.
3. Valida balance = 200.
4. Valida row tem ``expires_at ≈ now() + 60 dias`` (default da RPC add_tokens).

NOTA: o test original usava ``admin_grant_tokens`` mas essa RPC requer
``auth.uid() IS NOT NULL`` (JWT admin) e service_role NÃO satisfaz.
``add_tokens`` é SECURITY DEFINER puro — funciona com service_role.
"""
from datetime import datetime, timedelta, timezone

from helpers.tokens import (
    add_tokens,
    assert_tokens_balance,
    reset_user_tokens,
)


def test_t29_add_tokens_default_60d_validity(admin_client, cliente_a):
    """add_tokens(200) → balance=200 + expires_at ≈ +60d (default RPC)."""
    reset_user_tokens(admin_client, cliente_a['user_id'])

    add_tokens(
        admin_client,
        user_id=cliente_a['user_id'],
        amount=200,
        role='client',
    )

    assert_tokens_balance(
        admin_client,
        user_id=cliente_a['user_id'],
        expected=200,
        msg="balance pós add_tokens(200)",
    )

    # Valida expires_at ≈ now() + 60d (tolerância de 1 dia)
    rows = (
        admin_client.table("bora_tokens")
        .select("expires_at, amount")
        .eq("user_id", cliente_a['user_id'])
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    ).data or []
    assert rows, "esperava 1 row em bora_tokens"
    expires_str = rows[0]['expires_at']
    expires_dt = datetime.fromisoformat(expires_str.replace('Z', '+00:00'))
    expected_dt = datetime.now(timezone.utc) + timedelta(days=60)
    diff_h = abs((expires_dt - expected_dt).total_seconds()) / 3600.0
    assert diff_h < 24, (
        f"expires_at deveria ser ≈ now()+60d ({expected_dt.isoformat()}), "
        f"recebido {expires_str} (diff {diff_h:.1f}h)"
    )

    reset_user_tokens(admin_client, cliente_a['user_id'])
