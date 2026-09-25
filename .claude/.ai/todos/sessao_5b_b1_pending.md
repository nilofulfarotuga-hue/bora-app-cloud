# Sessão 5B-β1 — TODOs adiados

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Sessão concluída:** 5B-β1 (cenário ambicioso: 3 skills Grupo 2 + push admin trigger + Edge Fn `support-password-reset`)

## Adiado para 5B-β2

### Skills Grupo 3 (mercado + cancelamentos avançados)
- `CANCEL_DURING_PURCHASE` — cancelar após dispatch (estafeta a caminho)
- `RESERVATION_CANCEL` — cancelar reserva de mesa
- `ITEM_UNAVAILABLE` — substituir/remover item indisponível
- `ITEM_ADDED` — adicionar item ao pedido pós-criação
- `PRICE_DIFFERENCE` — ajustar preço final pós-shopping
- `PARTNER_REJECTED_ORDER` — handler quando partner rejeita

### Notificações
- **Email outbound (Resend SMTP)** — alerta admin (alternativa/complemento ao FCM)
- **Webhook receiver** para resultado real:
  - `admin-cancel-order` async result → reconcile pending status
  - `support-password-reset` confirmation
- **UI cliente:** notificação in-app quando proposta aprovada/rejeitada

### Configuração infra
- **`pg_net` settings em prod**:
  - `ALTER DATABASE postgres SET app.supabase_url = '<url>'`
  - `ALTER DATABASE postgres SET app.service_role_key = '<key>'`
  - Sem isto, `PASSWORD_RESET` e trigger push falham silenciosamente
- **Phone change SMS verification** — actualmente RPC valida E.164 mas não verifica posse via OTP

### Smoke tests E2E (manual)
- ACCOUNT_UPDATE end-to-end via chatbot real (tool agent_propose_action_account)
- PASSWORD_RESET com `pg_net` configurado → email real chega
- CANCEL_PRE_PURCHASE com pedido real created/preparing → Stripe refund actual

## Decisões registadas em 5B-β1

1. **`users.full_name`** não existe — RPC ACCOUNT_UPDATE escreve em `users.name` (com fallback `full_name` no payload).
2. **`notify-client`** é FCM-only (não suporta email) — PASSWORD_RESET usa Edge Fn nova `support-password-reset` que chama `auth.resetPasswordForEmail`.
3. **CANCEL_PRE_PURCHASE** usa **Flutter dispatch** para `admin-cancel-order` (com admin JWT) em vez de pg_net (que falha por causa do `auth.getUser()` validation). RPC stub `EXTERNAL_DISPATCH_REQUIRED` força este path.
4. **`admin_finalize_action`** RPC nova — permite Flutter marcar pending action após execução externa.
5. **Trigger push admin** — guard `IS NOT NULL` em settings, silent skip se ausentes (badge realtime fallback).

## Smokes confirmados (todos passam)

- ACCOUNT_UPDATE happy: status=executed, users.name actualizada
- ACCOUNT_UPDATE forbidden_field: status=failed, FORBIDDEN_FIELD
- ACCOUNT_UPDATE invalid_phone: status=failed, INVALID_PHONE_FORMAT
- CANCEL_PRE_PURCHASE stub: status=failed, EXTERNAL_DISPATCH_REQUIRED (Flutter handles)
- 14 skills (8 read_only + 1 escalate + 5 write_shadow)
- Trigger `trg_zz_pending_action_notify_admin` enabled
- `admin_finalize_action` RPC criado
- Regression: RAG enabled, 534 chunks, final_total numeric ✓
