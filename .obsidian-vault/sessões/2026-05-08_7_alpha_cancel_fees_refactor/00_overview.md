# Sessão 7-α-CANCEL-FEES-REFACTOR — Overview

**Data:** 2026-05-08
**Branch:** autonomous-night-2026-04-29
**Risco:** Médio (refactor multi-ficheiro código de pagamento)
**Modo:** PROTECÇÃO TOTAL (4 fases com STOP entre cada)

## Problema

3 Edge Functions deployed estavam a calcular cancel fees com valores
antigos hardcoded (CANCEL_FEE_*=1.00, 2.50, 1.00) embebidos no bundle
pré-2026-05-08. Quando settings em `platform_settings` mudavam, as
funções não viam.

## Solução

Refactor para LER `platform_settings` em runtime via novo helper
`supabase/functions/_shared/platform_settings.ts`. Cache 5min,
fallback defensivo, logging WARN visível em Edge Function logs.

## Settings em prod (2026-05-08)

| Key | Value | Status |
|---|---|---|
| `cancel_fee_before_dispatch_cents` | 150 (€1.50) | pré-existia |
| `cancel_fee_after_accept_cents` | 250 (€2.50) | NOVO 2026-05-08 |
| `cancel_fee_after_pickup_ratio` | 1.00 (100%) | NOVO 2026-05-08 |

## Edge Functions deployed

| Função | v ANTES | v DEPOIS | Linhas Δ |
|---|---|---|---|
| `client-cancel-order` | v11 | **v12 ACTIVE** | -16 |
| `cancel-order-with-choice` | v3 | **v4 ACTIVE** | -16 |
| `execute-cancellation` | v2 | **v3 ACTIVE** | -12 |

## Smoke test

Diferido para fim da maratona (regra Danilo). Critérios para
validação manual:
- Order cancelada antes dispatch → `cancel_fee = 1.50` (não €1.00)
- Push notification chega
- Refund Stripe processa OK

## Cache TTL

5 minutos por Edge Function process. Primeira chamada paga query DB;
próximas 5min vêm do cache em memória. Settings change tem
propagation delay máx. 5min por instância.

## Anomalia registada (fora-scope)

`lib/widgets/refund_choice_dialog.dart:145-154` usa `Radio.onChanged`
e `groupValue` deprecated post-Flutter 3.32 — TODO separado para
sessão futura.

## Validation summary

- ✅ Smart quotes ZERO em todos os 4 ficheiros
- ✅ Zero refs `CANCEL_FEE_*` em `index.ts` das 3 fns
- ✅ `deno check` passa no helper
- ⚠️ `deno check` nas 3 fns falha com `@types/node` — pre-existente
  (validado via stash em HEAD), environmental do esm.sh Stripe, não
  bloqueia `supabase functions deploy`
- ✅ flutter analyze baseline preservada (55 issues, info-only)

## Files changed

- ✨ `supabase/functions/_shared/platform_settings.ts` (novo, 133 linhas)
- ✏️ `supabase/functions/client-cancel-order/index.ts` (-16 linhas)
- ✏️ `supabase/functions/cancel-order-with-choice/index.ts` (-16 linhas)
- ✏️ `supabase/functions/execute-cancellation/index.ts` (-12 linhas)
- ✏️ `.claude/.ai/business_rules.md` (+ §49)
- ✏️ `PROJECT_CONTEXT.md` (root + ceo-ai/references)
