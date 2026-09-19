---
date: 2026-04-24
type: launch
files_affected:
  - backend/render.yaml
  - backend/.gitignore
  - backend/package.json
  - CLAUDE.md
  - PROJECT_CONTEXT.md
commit: 5962de3
ceo_ai_section: Current System State > TOP 3 RISCOS + Architecture Awareness
approved_by: Danilo
tags: [rules, launch, backend, render, stripe, architecture]
---

# Backend deployed no Render — arquitectura híbrida

## Antes

- Node backend (`backend/server.js`) existia localmente mas nunca deployed.
- Documentação assumia que pagamentos precisavam de `BACKEND_BASE_URL` via `--dart-define`, com default `http://localhost:3000`.
- TOP 3 RISCOS listavam: "Stripe sem URL produção → falha silenciosa em card payments" como #1.
- Realidade divergia da documentação: código Dart em `lib/services/payment_service.dart` usa Supabase Edge Functions (`functions.invoke`), não HTTP REST.

## Depois

### Deploy Render

- URL: **https://bora-backend-2dp0.onrender.com**
- Plan: Free (750h/mês, dorme após 15min inactividade)
- Região: Frankfurt
- Runtime: Node 20.x
- Health check: `/health`
- Auto-deploy ligado ao `main` do repo `nilofulfarotuga-hue/bora-app-cloud`
- Env vars configuradas: `STRIPE_SECRET_KEY` (`rk_live_`), `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`, `NODE_ENV=production`
- Ficheiros novos: `backend/render.yaml` (blueprint IaC), `backend/.gitignore` (exclui `.env` + `firebase-service-account*.json`), `backend/package.json` (+ `engines.node = 20.x`)

### Arquitectura híbrida confirmada

- **Primário:** Supabase Edge Functions (create-payment-intent, refund, charge-extra, confirm-mbway-payment, dispatch-engine, stripe-webhook, notify-driver, delete-account, client-cancel-order, update-products)
- **Backup/redundância:** Node backend no Render — espelha endpoints Stripe (`/create-payment-intent`, `/refund`, `/charge-extra`) **mas não é chamado pela app** na arquitectura actual.
- **Decisão:** manter os dois sem migrar código Dart. Opção C do plano original.

### Riscos actualizados

- REMOVIDO: "Stripe sem URL produção" (já não é risco)
- ADICIONADO: "Stripe em LIVE mode sem teste end-to-end real" — key actual é `rk_live_` (restricted + LIVE), não test.

## Motivo

1. Completar Fase 2 de deploy (app Flutter precisa de backend estável).
2. Ter infra pronta caso no futuro se migre de Supabase Edge Functions para Node backend (por custos, custom logic, etc.).
3. Alinhar documentação (CLAUDE.md, PROJECT_CONTEXT.md, CEO-AI) com a realidade do código.

## Impacto

- **Não quebra nada:** app continua a usar Supabase Edge Functions. Render fica idle.
- **Prepara lançamento:** infra redundante está online. Se Supabase cair, podemos migrar `payment_service.dart` para HTTP em horas.
- **Risco novo:** Stripe está em LIVE. Qualquer teste cobra dinheiro real. Mitigação: testar com 0.50 EUR + refund imediato antes de abrir ao público.
- **Documentação sincronizada:** 6 edits (CLAUDE.md x1, PROJECT_CONTEXT.md x4, CEO-AI x3).

## Ficheiros

- `backend/render.yaml` (blueprint Render)
- `backend/.gitignore` (actualizado)
- `backend/package.json` (engines.node = 20.x)
- `CLAUDE.md` — secção "Payment integration"
- `PROJECT_CONTEXT.md` — linhas 289, 305, 333, 348
- `.claude/skills/ceo-ai/SKILL.md` — PARCIAL, TOP 3 RISCOS, Architecture Awareness
