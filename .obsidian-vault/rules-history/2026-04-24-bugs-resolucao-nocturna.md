---
date: 2026-04-24
type: launch
files_affected:
  - lib/stores/order_store.dart
  - lib/screens/driver_home_screen.dart
  - supabase/functions/create-mbway-payment-intent/index.ts
  - supabase/functions/notify-partner/index.ts
  - supabase/functions/charge-extra/index.ts
  - supabase/functions/refund/index.ts
  - CLAUDE.md
  - .dart_defines
commits:
  - 56fb788 (Edge Functions)
  - e4b3596 (Realtime sync)
  - 1a1f976 (GPS fix)
ceo_ai_section: Current System State / Architecture Awareness / Launch Readiness Checklist
approved_by: Danilo
tags: [rules, launch, bugfix, realtime, gps, mbway, firebase, credenciais]
---

# Resolução Nocturna — 8 Bugs (2026-04-24)

## Antes

- Realtime sync cliente-driver: PARCIAL — stream do cliente arrancava sem filtro `user_id`; sem canal fallback UPDATE
- GPS driver: dois `getPositionStream` activos em simultâneo (home + map screens)
- MBWay: assinalado como "simulado" — sem Edge Function real
- Push Notifications: Edge Functions existentes mas nunca commitadas ao git
- Credenciais: Supabase/Stripe hardcoded em `lib/`

## Depois

- **BUG-001 ✅** — BACKEND_BASE_URL irrelevante; app usa Supabase Edge Functions directamente
- **BUG-002 ✅** — `_subscribeToOrders()` reinicia com `user_id` filter após auth; `_clientOrdersChannel` adicionado como fallback UPDATE (commit `e4b3596`)
- **BUG-003 ✅** — `notify-driver` + `notify-partner` Edge Functions commitadas e funcionais
- **BUG-006 ✅** — 4 Edge Functions completas commitadas ao git (commit `56fb788`)
- **BUG-012 ✅** — Credenciais migradas para `.dart_defines` (gitignored)
- **BUG-013 ✅** — MBWay real via `create-mbway-payment-intent` Edge Fn + Stripe LIVE
- **BUG-014 ✅** — `pk_live_` em `.dart_defines` para release builds
- **BUG-016 ✅** — `_navigateToMap()` helper cancela stream idle antes de abrir DriverMapScreen; retoma ao fechar (commit `1a1f976`)

## Motivo

Sessão de correcção de bugs por ordem de prioridade (críticos → médios). Análise nocturna de 2026-04-24 identificou 18 bugs; 8 resolvidos nesta sessão.

## Impacto

- Edge Functions agora de 5 → 8 no SKILL.md
- `PARCIAL` perdeu: Realtime sync, Push Notifications
- `PRONTO` ganhou: Realtime sync, GPS fix, MBWay real, Push Fn, Credenciais seguras
- TOP 3 RISCOS actualizados: riscos 2 e 3 substituídos por novos riscos pós-fix
- Launch Checklist: 4 novos [x] adicionados; push notifications separado em "Edge Fns commitadas" vs "deploy em produção"

## Ficheiros alterados

- `lib/stores/order_store.dart` — `updateAuthStore` reinicia stream; `_clientOrdersChannel` adicionado
- `lib/screens/driver_home_screen.dart` — `_navigateToMap()` helper; dois `Navigator.push` substituídos
- `supabase/functions/` — 4 Edge Functions novas commitadas
- `CLAUDE.md` — MBWay corrigido de "simulado" para "real LIVE"
- `.claude/skills/ceo-ai/SKILL.md` — 7 secções actualizadas
