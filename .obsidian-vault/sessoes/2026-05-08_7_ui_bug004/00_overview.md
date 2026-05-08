# Sessão 7-UI-BUG004 — Overview (2026-05-08)

## Sumário

Encerramento do ciclo BUG-7E-B-004 (driver cancela `pickedUp`):
- **Backend já FIXED em 7-FIX (2026-05-07)** — migration
  `20260507223338_fix_7e_b_bug_004_driver_cannot_cancel_pickedup`. RPC
  `driver_cancel_order` recusa pós-pickedUp com
  `support_required:true`.
- **UI agora FIXED em 7-UI-BUG004 (esta sessão)** — Flutter detecta
  o flag e abre bottom sheet com 2 botões (contactar suporte / ligar).

## Cenário aplicado

**Cenário B** (A0.2) — `SupportChatScreen` já existia mas não aceitava
pre-fill. Adicionado parâmetro opcional `initialMessage` (não-disruptivo:
init flow tem só greeting, sem state machine ou subscriptions afectadas).
`support-chatbot` Edge Fn v8 (PROTECTED) **não foi tocado**.

## Estado

✅ **CLOSED** — backend + UI completos.

## BUGs 7E-B (estado pós-sessão)

| BUG | Severidade | Sessão close | Tipo |
|---|---|---|---|
| 001 | LOW | 7 MEGAFINAL | Doc fix |
| 003 | LOW | 7 MEGAFINAL | FALSE POSITIVE |
| 004 | HIGH | **7-FIX backend + 7-UI-BUG004 UI** | Migration + Flutter UI |
| 005 | HIGH | 7-FIX | Migration |
| 006 | MEDIUM | 7 MEGAFINAL | Setting + migration |
| 007 | HIGH | 7-FIX | Migration |

6/6 fechados em todas as camadas. App seguro para launch.

## Não modificado (zonas protegidas)

- `pricing_service.dart`
- `dispatch-engine`
- triggers `bora_tokens`
- código Stripe (Edge Fn `stripe-webhook`)
- `OrderStore.finalizePurchase`
- Edge Functions de produção (`support-chatbot` v8, `stripe-webhook`)
- Cron jobs
- Fixes BUG-005/007 (já aplicados em 7-FIX)
- `admin_cancel_order` (RPC separada, fora deste scope)
- Sessão 6 ratings infra
- Framework E2E 7E-A/7E-B
- 21 skills active

## Validação

- `flutter analyze`: **55 issues** (baseline preservada — A0.7 reportou
  55, intermediário foi 56 após refactor com `unnecessary_cast`,
  corrigido para 55 final).
- T37 backend smoke continua a passar (`support_required is True`).
- Validação manual UI: ver `02_validation_manual.md`.
