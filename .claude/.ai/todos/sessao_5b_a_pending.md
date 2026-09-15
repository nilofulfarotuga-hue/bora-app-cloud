# Sessão 5B-α — TODOs adiados

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Sessão concluída:** 5B-α (infra shadow + Grupo 1, scope reduzido a 2 skills)

## Adiado para 5B-β

### Skills WRITE adicionais
- **OTP_RESEND** (Grupo 1, originalmente em 5B-α)
  - Bloqueado porque (a) não há fluxo OTP no Bora App, (b) `app.supabase_url` + `app.service_role_key` não estão configurados, impossibilitando `pg_net.http_post`.
  - Decisão: avaliar se o app vai introduzir flow OTP custom OU se Supabase Auth nativo cobre o caso.
- **Grupo 2:** `ACCOUNT_UPDATE`, `PASSWORD_RESET`, `CANCEL_PRE_PURCHASE`, `RESERVATION_CANCEL`
- **Grupo 3:** `CANCEL_DURING_PURCHASE`, `ITEM_UNAVAILABLE`, `ITEM_ADDED`, `PRICE_DIFFERENCE`, `PARTNER_REJECTED_ORDER`

### Notificações
- **Email outbound (Resend SMTP)** — alerta admin quando há nova proposta
- **Push admin (FCM)** — alternativa/complemento ao email
- **Webhook resultado real OTP_RESEND** — fechar loop fire-and-forget

### Configuração infra
- **`pg_net` settings** — popular `app.supabase_url` + `app.service_role_key` ou refactor para Edge Function como camada intermédia
- Adicionar verificação periódica + alerta se settings ficarem NULL

### UX
- Notificação in-app para o cliente quando proposta é aprovada/rejeitada
- Histórico de propostas no chatbot do cliente (read-only) — actualmente o cliente só vê o "aguarda aprovação"

### Regressão a monitorar
- **support_agent_actions** vs **support_pending_actions** — duas tabelas similares. Considerar consolidação numa única tabela em sessão futura, ou clarificar semântica:
  - `support_agent_actions` = log histórico (audit trail)
  - `support_pending_actions` = fila de aprovação (operacional)

## Decisões registadas em 5B-α

1. **`UPDATE_DELIVERY_INSTRUCTIONS`** mantém o nome lógico mas o RPC escreve em `orders.customer_notes` (coluna real).
2. **`orders.id` = TEXT** — RPC aceita string sem cast UUID (suporta legacy IDs não-UUID).
3. **`mode` CHECK constraint** estendido para incluir `'write_shadow'` e `'write_auto'` (futuro).
4. **`agent_propose_action`** rota separada via `adminClient` (service_role) no Edge Fn, NÃO pelo `callRpc` user JWT.

## Smokes confirmados (S1–S26)

Todos passam. Ver `05b_a_write_report.md` para detalhes.
