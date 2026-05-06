# Sessão 5B-β1 — Prompt original

**Data execução:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Cenário:** **Ambicioso (3)** — luz verde Danilo

## Resumo

Sessão 5B-β1/7 — SKILLS WRITE GRUPO 2 + PUSH ADMIN.

### Objectivo

1. **3 skills WRITE Grupo 2** (mode='write_shadow')
2. **Trigger push admin** AFTER INSERT support_pending_actions
3. **Edge Fn nova** support-password-reset (Auth Admin API)
4. **support-chatbot v4** com 3 tools especializadas
5. **Flutter dispatch** para CANCEL_PRE_PURCHASE em AdminPendingActionsScreen

### Decisões aplicadas após Fase A

A auditoria detectou 4 desvios entre spec e realidade:

1. `users.full_name` não existe → RPC usa `users.name`
2. `notify-client` é FCM-only → criar Edge Fn `support-password-reset` dedicada
3. `client-cancel-order` valida user JWT → CANCEL via Flutter dispatch para `admin-cancel-order`
4. `users.email` NULL para muitos → RPC PASSWORD_RESET lê de `auth.users`

### Cenário escolhido (luz verde): **3 (Ambicioso)**

3 skills + Edge Fn nova + Flutter dispatch — tudo em 5B-β1.

### Ficheiros entregues

Ver [05b_b1_write_report.md](../entregas/05b_b1_write_report.md).
