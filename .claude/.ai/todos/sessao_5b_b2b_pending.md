# TODOs adiados — Sessão 5B-β2b (5B COMPLETO)

**Última actualização:** 2026-05-06
**Sessão:** 5B-β2b (info-only mercado + escalate — Grupo 3b)
**Estado 5B:** ✅ FECHADO (20 skills active)

## Próximas sessões (5B fechado)

- **5D** — Auto-suggest cron skills novas (~3h)
- **5E** — Auto-implement zonas seguras (~5h)
- **5F** — Comunicação Robô A ↔ Robô B (~4h)
- **5G** — Painel admin inbox propostas (~3h)
- **Sessão 6** ORIGINAL — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor + docs cleanup (~6-8h)

## Bugs/inconsistências docs (Sessão 7 housekeeping)

- §12.3 (4h) vs §18.3/DB (2h) — corrigir §12.3
- Taxa cancel_during_purchase divergente — BR §8.3 (€1/€2.50/100%) vs
  stripe-webhook hardcoded (€1.50/50%/100%)
- `admin-cancel-order` UUID-only vs `orders.id` TEXT legacy

## Pendentes técnicos (não bloqueantes)

- `pg_net` settings prod (`app.supabase_url`, `app.service_role_key`)
  → desbloqueia PASSWORD_RESET e push admin trigger
- Email Resend SMTP custom
- Webhook receivers resultado real Stripe (cliente UX da proposta)
- SMS verification para phone change

## Validação manual recomendada (Danilo)

- S7: chat real "o leite não veio" → confirmar resposta + row em
  `support_agent_actions` com skill_name='ITEM_UNAVAILABLE',
  shadow_status='not_applicable'
- S8: chat real "o restaurante recusou" → confirmar empatia +
  `[HANDOFF_HUMAN]` + row em `support_tickets` (NÃO em
  `support_pending_actions`)
