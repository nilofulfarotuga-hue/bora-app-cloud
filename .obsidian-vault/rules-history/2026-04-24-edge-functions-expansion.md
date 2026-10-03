---
date: 2026-04-24
type: tech-rule
files_affected:
  - supabase/functions/refund/index.ts
  - supabase/functions/refund/config.toml
  - supabase/functions/charge-extra/index.ts
  - supabase/functions/charge-extra/config.toml
  - CLAUDE.md
  - PROJECT_CONTEXT.md
commit: manual
ceo_ai_section: Architecture Awareness > Edge Functions
approved_by: Danilo
tags: [rules, tech-rule, edge-functions, stripe, payments]
---

# Edge Functions expansion — refund + charge-extra

## Antes

4 Edge Functions no Supabase:
- `dispatch-engine`
- `create-payment-intent`
- `stripe-webhook`
- `confirm-mbway-payment`

Pedidos de refund e charge-extra dependiam do Node backend (`backend/server.js`) em `http://localhost:3000` — falha silenciosa em produção.

## Depois

6 Edge Functions deployed e activas:
- `dispatch-engine`
- `create-payment-intent`
- `stripe-webhook`
- `confirm-mbway-payment`
- **`refund`** — admin-only (verify_jwt=true + JWT claim `role=service_role`)
- **`charge-extra`** — utilizadores autenticados (verify_jwt=true)

Ambas enforçam mínimo 0.50 EUR (Stripe requirement). Ambas importam `_shared/cors.ts` e usam Stripe 14.21.0 via esm.sh para Deno.

### Probes validados

| Função | Teste | Resultado |
|---|---|---|
| refund | Bad JWT | 401 Supabase layer ✅ |
| refund | SR sem body | 400 `paymentIntentId is required` ✅ |
| refund | SR amount < 0.50 | 400 `Amount too small (min 0.50 EUR)` ✅ |
| refund | SR valid params | 500 `No such payment_intent: pi_test` (Stripe real) ✅ |
| charge-extra | Bad JWT | 401 `UNAUTHORIZED_INVALID_JWT_FORMAT` ✅ |
| charge-extra | SR sem body | 400 validação ✅ |
| charge-extra | SR amount < 0.50 | 400 `Amount too small (min 0.50 EUR)` ✅ |

## Motivo

`PaymentService` em `lib/services/payment_service.dart` já invoca estas funções via `Supabase.instance.client.functions.invoke(...)`. Antes retornavam 404 porque não estavam deployed. Agora o fluxo completo de pagamento (create → refund / charge-extra) está funcional sem dependência do Node backend.

## Impacto

- **Desbloqueia:** reembolsos parciais quando `finalTotal < paymentBuffer` (driver comprou menos que estimado).
- **Desbloqueia:** charges extra quando `finalTotal > paymentBuffer` (shortfall cobrado ao cliente).
- **Não quebra:** nada — código Dart já esperava estas funções. Antes falhava com "function not found".
- **Segurança:** refund decode JWT manualmente porque env var `SUPABASE_SERVICE_ROLE_KEY` injectado pelo Supabase pode estar em formato diferente (legacy JWT vs novo `sb_secret_`); verificação por claim `role` é agnóstica ao formato.

## Ficheiros

- `supabase/functions/refund/index.ts` (86 linhas)
- `supabase/functions/refund/config.toml` (`verify_jwt = true`)
- `supabase/functions/charge-extra/index.ts` (67 linhas)
- `supabase/functions/charge-extra/config.toml` (`verify_jwt = true`)
- `CLAUDE.md` — secção "Payment integration" reescrita
- `PROJECT_CONTEXT.md` — linhas 289, 305 actualizadas (status Stripe: Parcial → Funcional)
