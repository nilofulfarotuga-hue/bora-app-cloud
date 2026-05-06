# TODOs adiados — Sessão 5B-β2a

**Última actualização:** 2026-05-06
**Sessão:** 5B-β2a (cancelamentos avançados — Grupo 3a)

## Próxima sessão (5B-β2b — última de 5B)

- `ITEM_UNAVAILABLE` / `ITEM_ADDED` / `PRICE_DIFFERENCE` — `read_only` (info-only)
- `PARTNER_REJECTED_ORDER` — `escalate`
- Tool nova `agent_explain_event`
- support-chatbot v6

## Bugs/inconsistências docs (Sessão 7 housekeeping)

- **§12.3 (4h) vs §18.3/DB (2h)** — DB é fonte da verdade; §12.3 está
  desactualizada
- **Taxa cancel_during_purchase divergente** — BR §8.3 (€1/€2.50/100%) vs
  `stripe-webhook` hardcoded (€1.50/50%/100%). Decidir se migrar para
  `platform_settings` (chaves novas).
- **`admin-cancel-order` UUID format puro** — falha em orders.id legados
  não-UUID. Auditar e migrar antes de purga.

## Geral pendente

- `pg_net` settings em prod (`app.supabase_url`, `app.service_role_key`)
  → desbloqueia `PASSWORD_RESET` actual e push admin trigger
- Email Resend SMTP custom (5B-β2 follow-up)
- Webhook receivers para resultado real Stripe (cliente UX da proposta)
- SMS verification para phone change
- Auditar order IDs em formato não-UUID antes de purga (R7 Fase A)
