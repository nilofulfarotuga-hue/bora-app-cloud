"""Sessão 7E-A — mocks granulares para o framework E2E.

Decisões #3-#6 (audit 07e_a_audit.md):
- Stripe → SQL UPDATE em orders (`payment_status='paid'`)
- FCM → push_log em memória
- Gemini → respostas hardcoded por skill_id
- dispatch-engine → RPC `accept_dispatch_offer` directa
"""

from __future__ import annotations

from typing import Any

# ──────────────────────────────────────────────────────────────────────────
# FCM mock — logger em memória partilhado entre testes do mesmo run.
# Helpers em 7E-B/D vão consultar esta lista para asserções.
# ──────────────────────────────────────────────────────────────────────────
push_log: list[dict[str, Any]] = []


def reset_push_log() -> None:
    """Limpa o log de pushes — chamar em fixtures `setup` se necessário."""
    push_log.clear()


def record_push(target: str, payload: dict[str, Any]) -> None:
    """Stub que será chamado por wrappers de notify-* em fases seguintes."""
    push_log.append({"target": target, "payload": payload})


# ──────────────────────────────────────────────────────────────────────────
# Stripe mock — SQL UPDATE directo via admin_client.
# 7E-B vai chamar `simulate_stripe_payment_succeeded(client, order_id)`.
# Implementação fica para o helpers/orders.py em 7E-B.
# ──────────────────────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────────────────
# Gemini mock — respostas hardcoded por skill_id.
# 7E-D popula este dict conforme as skills sob teste.
# ──────────────────────────────────────────────────────────────────────────
RESPONSE_FIXTURES: dict[str, str] = {
    # Exemplo (será expandido em 7E-D Grupo 11):
    # "support_general": "Como posso ajudar?",
    # "skill_suggestion": "Sugestão: criar nova zona.",
}


def gemini_response(skill_id: str) -> str:
    """Devolve a resposta mockada para um skill_id ou raise se desconhecido."""
    if skill_id not in RESPONSE_FIXTURES:
        raise KeyError(
            f"Mock Gemini não tem fixture para skill_id={skill_id!r}. "
            "Adicionar em RESPONSE_FIXTURES ou activar E2E_GEMINI_LIVE=1."
        )
    return RESPONSE_FIXTURES[skill_id]
