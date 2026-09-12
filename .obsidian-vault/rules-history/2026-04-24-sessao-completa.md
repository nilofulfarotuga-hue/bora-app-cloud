---
date: 2026-04-24
type: session-summary
approved_by: Danilo
tags: [session, stripe, mbway, obsidian, edge-functions, backend]
---

# Sessão 2026-04-24 — O que fizemos

## ✅ Concluído hoje

### Cérebro Digital
- Obsidian configurado com vault "Bora CEO"
- Script sync-brain.js criado (~/.claude/)
- Hook automático no settings.json
- Skill auto-rules-sync criada
- Pasta rules-history/ criada no Obsidian

### Stripe LIVE
- Chaves pk_live_ e sk_live_ activadas
- main.dart refactored (sem hardcode)
- Conta Novo Banco configurada no Stripe
- Webhook LIVE criado e seguro (whsec_ rolled)
- MB WAY habilitado no Stripe Dashboard

### MBWay Real
- Edge Function create-mbway-payment-intent criada
- stripe-webhook actualizado
- payment_service.dart — mock removido, real implementado
- payment_method_screen.dart — diálogo real com polling
- Fluxo: pedido → Stripe → push MBWay → confirma → pago

### Edge Functions novas
- refund (admin-only)
- charge-extra (autenticado)
- create-mbway-payment-intent (MBWay real)

### Backend Render
- Deployed em https://bora-backend-2dp0.onrender.com
- Suspenso (app usa Supabase Edge Functions)

---

## Bloqueadores de lançamento restantes

- [ ] Firebase push notifications (google-services.json)
- [ ] Testes E2E
- [ ] Stripe smoke test (€0.50 real)
- [ ] MBWay smoke test

---

## Próxima sessão
→ Firebase push notifications
