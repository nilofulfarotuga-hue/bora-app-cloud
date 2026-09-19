# 2026-05-08 — Sessão 7 MEGAFINAL — Mudanças de regras

## Regras adicionadas/ajustadas

### §3.2 Limite de Dinheiro (cash €40)

**Antes**: documentação genérica "Máximo €40,00 por pedido".
**Depois**: explicitada a setting `platform_settings.max_cash_amount_cents=4000`
e nome do trigger `orders_enforce_cash_limit`.

Sem mudança de comportamento. Apenas documentação.

### §2.6 Bag fee storeShopping (€0.10/saco)

**Antes**: regra documentada genericamente sem validação prod.
**Depois**: nota com validação prod 2026-05-08 — 4 orders últimos
30d com `cents_per_bag=10.00` exacto.

BUG-7E-B-003 reclassificado FALSE POSITIVE.

### §48 (NOVO) — Sessão 7 MEGAFINAL

Documenta as 6 migrations aplicadas em prod via MCP, RLS
hardening (BLOCO 2), storage hardening (BLOCO 3) e cron cleanup
(BLOCO 4).

Inclui:
- §48.1 BUGs 001/003/006 closed
- §48.2 Migrations aplicadas (lista 6 + TODO 7-α sync local)
- §48.3 BLOCO 2 RLS (4 sub-blocos)
- §48.4 BLOCO 3 Storage (avatars 4 policies + order-photos
  privatizado + moddatetime move)
- §48.5 BLOCO 4 Cron (7 unscheduled, 11 preservados)
- §48.6 BUGs status pós-sessão (todos 6 CLOSED ✅)
- §48.7 Pendentes (5F-β-β, 7-α, 7E-C, 7E-D)
- §48.8 Decisão arquitectural — Opção A MCP directo

### Setting nova

`platform_settings.cancel_fee_before_dispatch_cents = 150` (€1.50)
— migration `fix_bug_006_stripe_cancel_fee_setting`.

## Decisões fechadas

- **BUGs 001/003/006**: CLOSED.
- **BUGs 004/005/007**: confirmados CLOSED desde 2026-05-07
  (7-FIX). Frase obsoleta "OPEN explícito" do prompt original
  ignorada; status correcto do repo prevaleceu.
- **§48 nova** (em vez de inline em §47, que é fechada de 7-FIX
  2026-05-07).
- **Cash €40 e bag €0.10 já correctos no .md** — só notas
  inline, sem alterar valores.
- **Discrepância repo-local↔prod**: aceite para esta sessão
  pontual; sync local é TODO 7-α.

## Migrations aplicadas em prod via MCP (6)

```
20260508084132 fix_bug_006_stripe_cancel_fee_setting
20260508091407 bloco_2a_drop_backups_enable_rls_3_tables
20260508091529 bloco_2b_fix_6_rls_user_metadata_to_is_admin
20260508091707 bloco_2c_views_security_definer_to_invoker
20260508092014 bloco_2d_fix_messages_restaurants_with_check_true
20260508092347 bloco_3_storage_buckets_moddatetime
```

## Validação

- ✅ `flutter analyze`: 55 issues (baseline mantido — sem regressão).
- ✅ Pré-validação Claude.ai checks 1-4 PASS.
- ✅ Pós-validação Claude Code checks 5-8 PASS.

## Trabalho pendente (não bloqueante)

- **7-α** — sync `supabase/migrations/` locais via `supabase db pull`.
- **5F-β-β** — refactor Edge Fn `stripe-webhook` ler
  `cancel_fee_before_dispatch_cents` da setting.
- **business_rules.ts** (frontend code) — alinhar
  `CASH_MAX_ORDER_VALUE_EUR=30 → 40` em sessão dedicada futura.
