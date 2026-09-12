# Sessão 5B-α — Prompt original

**Data execução:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL (audit → luz verde → execução)
**Modelo:** Claude Opus 4.7 (1M context)

## Resumo do prompt original

Sessão 5B-α/7 — SKILLS WRITE: INFRA SHADOW + GRUPO 1.

### Objectivo

1. **Infra shadow** (PROD):
   - Tabela `support_pending_actions` (fila aprovação)
   - 4 RPCs: `agent_propose_action`, `admin_approve_action`, `admin_reject_action`, `admin_list_pending_actions`

2. **3 Skills WRITE** (mode='write_shadow'):
   - `UPDATE_DELIVERY_INSTRUCTIONS`
   - `UPDATE_DELIVERY_ADDRESS`
   - `OTP_RESEND`

3. **Edição `support-chatbot`** (PROD): tool `agent_propose_action`

4. **Admin Inbox** Flutter (`AdminPendingActionsScreen`):
   - Filtro status (pending/executed/rejected/failed/all)
   - Confirmação modal antes aprovar
   - Realtime badge para pendentes novas
   - Pull-to-refresh

### Decisões aplicadas após Fase A (audit)

A auditoria detectou 5 desvios entre spec pré-validada e realidade.
Após luz verde do Danilo, scope ajustado:

1. **`UPDATE_DELIVERY_INSTRUCTIONS`** mantém o nome lógico mas o RPC
   escreve em `orders.customer_notes` (`delivery_instructions` não existe).
2. **`OTP_RESEND` adiado para 5B-β** (sem fluxo OTP no app + `pg_net`
   settings ausentes).
3. **Tabela nova `support_pending_actions`** (não reutilizar
   `support_agent_actions` legado da 5A-1).
4. **Scope reduzido a 2 skills WRITE.**

### Ficheiros entregues

Ver [05b_a_write_report.md](../entregas/05b_a_write_report.md).
