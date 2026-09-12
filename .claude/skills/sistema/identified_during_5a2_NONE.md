# Skills identificadas durante Sessão 5A-2 (audit Fase A)

**Data:** 2026-05-04
**Sessão:** 5A-2/7 — Agente IA Suporte Frontend + Skills Seed
**Fase:** A (audit, read-only)

## Resultado

**Nenhuma skill nova identificada além das 9 aprovadas em 5A-1 para seed em 5A-2 B17.**

As 9 skills read-only confirmadas:
1. ORDER_STATUS — `agent_get_order_status`
2. ORDER_HISTORY — `agent_get_user_orders_summary`
3. WALLET_INFO — `agent_get_user_wallet_summary`
4. WALLET_BLOCKED_HELP — `agent_get_user_wallet_summary`
5. TOKENS_INFO — `agent_get_user_tokens_summary`
6. REFUND_STATUS — `agent_get_refund_status`
7. GENERAL_FAQ — sem tools (cobertura, horários, como funciona Bora)
8. APP_TROUBLESHOOTING — sem tools (GPS, push, crash, reset)
9. HUMAN_REQUEST — escalate (cria ticket channel='chatbot')

## Razão

5A-2 está focada em **integração frontend** + **seed dos playbooks read-only**. O escopo de novas skills WRITE/CANCEL/MARKET fica para 5B (modo SHADOW 4 semanas). Skills RAG-based para 5C (após pgvector).

## Reportar em 5B / 5C

Se durante 5B (skills write) emergir necessidade adicional, criar
`identified_during_5b_<nome>.md`.
