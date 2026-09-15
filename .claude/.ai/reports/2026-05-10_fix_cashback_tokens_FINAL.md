# Cashback 1% removido + Tokens read fix — Relatório FINAL

**Data:** 2026-05-11
**Branch:** autonomous-night-2026-04-29
**Project:** ojykpzwqrtusfeakzrna (EU-West-1)
**Pedido referência:** CAA3A9 (`caa3a96b-774a-4f27-a094-01cf0366261b`)
**Cliente teste:** Danilo (`c9fccf85-03ee-4efc-83bf-613f211a78ff` / `nilofulfarotuga@gmail.com`)

---

## Causa raiz (final)

**BUG 1 — Cashback 1% indevido**
Trigger `trg_award_cashback` (AFTER UPDATE OF status) + função `fn_award_cashback_on_delivery()` + setting `platform_settings.cashback_pct=0.01` creditavam 1% em `wallet_transactions` em qualquer pedido entregue. Regra **nunca aprovada**.

**BUG 2 — Tokens "0" na UI**
- DB: cliente c9fccf85 tinha **748 tokens activos**, 12 rows, 0 used, 0 expired. `get_user_tokens(uid)` retorna `748` correctamente.
- `wallet_get_balance` tratava o retorno como JSONB (`->>'balance'`) mas era `INTEGER`. Cast falhava → `EXCEPTION WHEN OTHERS` silencioso → `tokens_balance=0`.
- Os 4 call sites Flutter usavam `(response as int?) ?? 0`, sensível a `double` serializado pelo PostgREST.

---

## SQL aplicado

Migration: [`supabase/migrations/20260510120000_fix_cashback_remove_and_tokens_read.sql`](../../../supabase/migrations/20260510120000_fix_cashback_remove_and_tokens_read.sql)

```sql
DROP TRIGGER IF EXISTS trg_award_cashback ON public.orders;
DROP FUNCTION IF EXISTS public.fn_award_cashback_on_delivery();
DELETE FROM public.platform_settings WHERE key = 'cashback_pct';

CREATE OR REPLACE FUNCTION public.wallet_get_balance(p_user_id uuid)
RETURNS jsonb …
  -- ANTES: SELECT COALESCE((public.get_user_tokens(v_target)->>'balance')::int, 0) …
  -- DEPOIS:
  v_tokens := COALESCE(public.get_user_tokens(v_target), 0);
…
```

Aplicada via `mcp__claude_ai_Supabase__apply_migration` → `{"success":true}`.

---

## Re-validação MCP (Validation Gate)

```sql
SELECT
  wallet_get_balance('c9fccf85'::uuid) ->> 'tokens_balance' AS tokens_balance_after_fix,
  (SELECT count(*) FROM pg_trigger WHERE tgname='trg_award_cashback') AS cashback_trigger_count,
  (SELECT count(*) FROM pg_proc WHERE proname='fn_award_cashback_on_delivery') AS cashback_func_count,
  (SELECT count(*) FROM platform_settings WHERE key='cashback_pct') AS cashback_setting_count;
```

| Campo | Antes | Depois |
|---|---|---|
| `tokens_balance` (cliente teste) | `"0"` | **`"748"`** ✅ |
| `trg_award_cashback` count | 1 | **0** ✅ |
| `fn_award_cashback_on_delivery` count | 1 | **0** ✅ |
| `platform_settings.cashback_pct` count | 1 | **0** ✅ |

---

## Ficheiros alterados (Flutter)

Todos: cast `(response as int?) ?? 0` → `(response as num?)?.toInt() ?? 0`.

- [`lib/screens/profile_screen.dart:1187`](../../../lib/screens/profile_screen.dart#L1187) — Token Balance Row
- [`lib/screens/payment_method_screen.dart:69`](../../../lib/screens/payment_method_screen.dart#L69) — cart token discount
- [`lib/screens/driver_earnings_screen.dart:69`](../../../lib/screens/driver_earnings_screen.dart#L69) — driver earnings
- [`lib/stores/driver_store.dart:67`](../../../lib/stores/driver_store.dart#L67) — fetchTokenBalance

`flutter analyze`: **55 issues** todos pré-existentes (deprecation infos / unused warnings). **0 erros novos** introduzidos por estas edições.

---

## business_rules.md — secções tocadas

- **§32.4** — nota add: fórmula `ROUND(price×3)` validada operacional em CAA3A9 (€21.18 → 64 tokens). Alinhamento docs ↔ código continua TODO sessão dedicada.
- **§32.6 (novo)** — Cashback automático 1% removido (2026-05-11). Sem backfill, sem estorno.
- **§32.7 (novo)** — `wallet_get_balance` leitura tokens corrigida + status BUG-7E-B-005 (likely-fixed) e BUG-7E-B-007 (CLOSED) + nota dos 4 call sites Flutter fortalecidos.
- **§32.8** — renumeração da antiga §32.5 ("Bug crítico 5A-1 corrigido em 5A-2"). Sem cross-refs externos a §32.5; renumeração segura.

---

## Status BUGs anteriores

- **BUG-7E-B-005 (tokens factor ×20):** likely-fixed em 7-FIX 2026-05-07 (factor ×2). Reconfirmado em 2026-05-11 — fórmula `ROUND(price×3)` operacional, 64 tokens em CAA3A9.
- **BUG-7E-B-007 (add_tokens silent fail):** **CLOSED**. Silent fail real era na **leitura** (`wallet_get_balance`), não na escrita. `add_tokens` saudável.

---

## Áreas proibidas — nenhuma tocada

Confirmado: `create_order`, `pricing_*`, `finalize_storeshopping_purchase`, `wallet_apply_post_delivery_adjustment`, Stripe/MBWay/refund/cancel-order-*, dispatch-engine, notify-driver, `enforce_financial_immutability`, `wallet_credit_refund_split` (refund 80/20) — **todos intactos**. Os 17 triggers em `orders` apenas lidos; só `trg_award_cashback` removido (era trigger autónomo, não dos 17 do core).

---

## TODOs sessão futura

- **§32.4 fórmula tokens** — alinhar `ROUND(price×3)` (= 30 tokens/€10 = 300%) vs doc "3%" (= 0.30 tokens/€10). Decisão de negócio Danilo.
- **Admin tokens screen** — já existe (`lib/screens/admin/admin_tokens_screen.dart`). Não foi criada UI nova. Confirmar cobertura em sessão futura.
- **Auditoria UI** após teste manual: confirmar que cliente vê 748 tokens no profile + cart agora.

---

## FASE 4 — Teste manual (pedido para Danilo)

1. Criar pedido novo (cliente real, não demo) → aceitar → entregar.
2. Verificar via app:
   - Profile "Token Balance Row" mostra saldo **>0**.
   - Wallet/cart mostra `tokens_balance` correctamente.
   - **SEM** entrada `cashback` nova em `wallet_transactions` para esse pedido.
3. Via MCP:
   ```sql
   SELECT amount, source_order_id FROM bora_tokens WHERE source_order_id = '<novo_uuid>';
   SELECT count(*) FROM wallet_transactions
     WHERE kind='cashback' AND created_at > NOW() - INTERVAL '15 minutes';
   ```
   Esperado: 1 row tokens (ROUND(subtotal×3) min 1) + 0 cashback novos.

---

## Pergunta admin

Existe `lib/screens/admin/admin_tokens_screen.dart` — **não criar nada novo**.
Confirmação solicitada ao Danilo se essa screen cobre o necessário.
