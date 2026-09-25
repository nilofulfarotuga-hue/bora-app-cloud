# TODOs adiados — Sessão 5D

**Última actualização:** 2026-05-06
**Sessão:** 5D (auto-suggest cron skills novas)
**Estado 5D:** ✅ FECHADA

## TODOs 5D-β (sequela)

- **pg_net settings prod (BLOQUEANTE para cron real)**:
  ```sql
  ALTER DATABASE postgres SET app.supabase_url = '<prod-url>';
  ALTER DATABASE postgres SET app.service_role_key = '<key>';
  ```
  Sem isto, `analyze-conversations-weekly` falha em silêncio.
  Análise manual via botão funciona.
- Anonimização avançada PII (Microsoft Presidio ou library equivalente)
- Dedup semântico: embeddar `support_skills.playbook_md` em
  `support_knowledge_chunks` (source_type='skill') + similarity ≥0.8
- Métricas painel: % aprovadas vs rejeitadas + tempo médio de revisão
- Editor markdown avançado (live preview) no AdminSkillSuggestionsScreen
- Re-análise inteligente: padrão N semanas consecutivas → priority boost

## Próximas sessões

- **5E** — Auto-implement zonas seguras (~5h)
- **5F** — Comunicação Robô A ↔ Robô B (~4h)
- **5G** — Painel admin inbox propostas (~3h)
- **Sessão 6** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor + docs cleanup (~6-8h)

## Histórico (de sessões anteriores)

- §12.3 (4h) vs §18.3/DB (2h) — corrigir §12.3 (Sessão 7)
- Taxa cancel_during_purchase divergente — BR §8.3 vs stripe-webhook
  hardcoded (Sessão 7)
- `admin-cancel-order` UUID-only vs `orders.id` TEXT legacy (Sessão 7)
- Email Resend SMTP custom
- Webhook receivers para resultado real Stripe
- SMS verification para phone change
