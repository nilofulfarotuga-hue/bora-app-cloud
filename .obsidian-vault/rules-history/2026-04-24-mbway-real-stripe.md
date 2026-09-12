---
date: 2026-04-24
type: tech-rule
files_affected:
  - supabase/functions/create-mbway-payment-intent/index.ts
  - supabase/functions/stripe-webhook/index.ts
  - lib/services/payment_service.dart
  - lib/screens/payment_method_screen.dart
commit: manual
ceo_ai_section: Architecture Awareness
approved_by: Danilo
tags: [rules, tech-rule, payment, stripe, mbway]
---

# MBWay Real via Stripe — Implementação Completa

## Antes

MBWay era **100% fake/mock**:
- `payWithMBWay()` devolvia `true` após 300ms (sem chamada a nenhuma API)
- Diálogo com botão manual "Confirmar no MBWay" simulava confirmação
- `confirm-mbway-payment` Edge Function era stub manual — marcava `payment_status=paid` sem verificação real
- Conta bancária e MB WAY não configurados no Stripe

## Depois

MBWay é **real via Stripe**:
- Novo fluxo server-trusted idêntico ao cartão
- Edge Function `create-mbway-payment-intent` cria + confirma PaymentIntent Stripe com `payment_method_types: ['mb_way']`
- Stripe envia push notification real para a app MBWay do utilizador
- `stripe-webhook` (payment_intent.succeeded) trata MBWay sem modificações — já existia
- Diálogo faz polling a `orders.payment_status` a cada 3s até `paid` ou timeout 120s
- Conta bancária Novo Banco configurada no Stripe Dashboard
- MB WAY activado no Stripe Dashboard

## Fluxo técnico

```
App → finishOrder(pending) → create-mbway-payment-intent
                                      ↓
                              Stripe PaymentIntent (mb_way)
                                      ↓
                          Push notification MBWay app user
                                      ↓
                            User confirms in MBWay app
                                      ↓
                    stripe-webhook (payment_intent.succeeded)
                                      ↓
                      orders.payment_status = 'paid'
                      orders.status = 'callingDriver'
                                      ↓
                              dispatch-engine invoked
```

## Motivo

Lançamento da Bora App requer pagamentos reais. MBWay é o método de pagamento dominante em Portugal. Stripe suporta `mb_way` nativamente sem necessidade de PSP adicional (Easypay/SIBS).

## Impacto

- `confirm-mbway-payment` Edge Function agora **obsoleta** — manter até testes prod confirmarem, depois apagar
- Utilizador precisa de número de telemóvel no perfil para MBWay funcionar
- Stripe live mode obrigatório (não funciona em test mode com números reais PT)
- `payment_intent.processing` não existe na versão API Stripe usada (2023-10-16) — ignorado

## Ficheiros

- `supabase/functions/create-mbway-payment-intent/index.ts` — CRIADO · Edge Function nova · LIVE
- `supabase/functions/create-mbway-payment-intent/config.toml` — CRIADO · verify_jwt=false
- `supabase/functions/stripe-webhook/index.ts` — +6 linhas (handler payment_intent.processing) · LIVE
- `lib/services/payment_service.dart` — `payWithMBWay` mock removido → `initiateMbwayPayment` real
- `lib/screens/payment_method_screen.dart` — fluxo MBWay reescrito + `_MBWayWaitingDialog` com polling

## Deploy

- `create-mbway-payment-intent` deployed: Supabase project `ojykpzwqrtusfeakzrna`
- `stripe-webhook` deployed: Supabase project `ojykpzwqrtusfeakzrna`
- Webhook Stripe: eventos `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded` activos
