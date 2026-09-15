# Cashback 1% indevido + Tokens "0" na UI — Relatório FASE 1+2 (read-only)

**Data:** 2026-05-10
**Branch:** autonomous-night-2026-04-29 · HEAD: 4e7a8d3
**Pedido referência:** caa3a96b-774a-4f27-a094-01cf0366261b (CAA3A9 · €21.18)
**Cliente teste:** c9fccf85-03ee-4efc-83bf-613f211a78ff
**Status:** ⚠️ AGUARDA OK DO DANILO VIA CLAUDE.AI ANTES DA FASE 3

---

## A0 — Estado git inicial

- Branch: `autonomous-night-2026-04-29`
- HEAD: `4e7a8d3 test: maestro E2E coverage — 24 flows + shared sub-flows`
- Sujos pré-existentes (habituais, não relacionados): `.claude/settings.json`, `.github/hooks/context-mode.json*`, `.maestro/config.yaml`, `supabase/.temp/cli-latest`
- Untracked: `.claude/.ai/_analyze_*.txt`, `.claude/.ai/reports/20260502_megafinal/03b_consent_infra_analise.md`

---

## A. CAUSA RAIZ — BUG 1 (CASHBACK 1% INDEVIDO)

**É creditado por:** trigger `trg_award_cashback` (AFTER UPDATE OF status quando `status='delivered'`) → função `fn_award_cashback_on_delivery()` (SECURITY DEFINER, owner postgres).

A função lê `platform_settings.cashback_pct` (default `0.01`) e credita via `wallet_credit_generic(..., 'cashback', ...)`.

Evidência directa nas `wallet_transactions` do cliente c9fccf85 (últimos 2 dias):

| amount_cents | kind     | reason                                  | related_order_id |
|--------------|----------|-----------------------------------------|------------------|
| 21           | cashback | Cashback 1.00% pedido caa3a96b...       | CAA3A9           |
| 21           | cashback | Cashback 1.00% pedido cd0719cc...       | …                |
| 32           | cashback | Cashback 1.00% pedido 3fe36ed5...       | …                |
| 21, 29, 31, 30, 20 | cashback | … (vários)                       | …                |

`platform_settings`:
- `cashback_pct = 0.01` ← regra ERRADA (Danilo confirmou que não existe)
- `client_token_award_pct = 3` (informativo, mas trigger usa ROUND(price×3) hardcoded)

**FORA das áreas proibidas:** trigger autónomo, função autónoma. Não toca `finalize_storeshopping_purchase`, `create_order`, webhook Stripe, refund, dispatch.

---

## B. CAUSA RAIZ — BUG 2 (TOKENS = 0 NA UI)

**Tokens FORAM creditados na DB.** O bug NÃO está na escrita — está na leitura.

### Evidência DB (estado correcto):

Pedido CAA3A9 → `bora_tokens`:
- Cliente c9fccf85: **64 tokens** (`ROUND(21.18 × 3) = 64` ✓), expira 2026-07-09
- Driver 519d0782: 40 tokens

Saldo total cliente c9fccf85: **748 tokens activos** (12 rows, 0 used, 0 expired).
`get_user_tokens('c9fccf85'::uuid)` retorna **748** ✓ (testado via MCP).

### Bug na leitura:

`wallet_get_balance` (RPC usado em `lib/services/wallet_service.dart`) faz:

```sql
SELECT COALESCE((public.get_user_tokens(v_target)->>'balance')::int, 0) INTO v_tokens;
```

Mas `get_user_tokens(uuid) RETURNS INTEGER` — não JSONB. O operador `INTEGER ->> 'balance'` lança exception → cai no `EXCEPTION WHEN OTHERS THEN v_tokens := 0` silencioso → UI mostra **0**.

Confirmado via MCP: `wallet_get_balance('c9fccf85'::uuid) ->> 'tokens_balance'` retorna `"0"`.

### Sítios afectados (consumidores `wallet_get_balance`):
- `lib/services/wallet_service.dart:17` — usado por wallet_history_screen, payment_method_screen (cart), profile_screen (wallet card), etc.
- `lib/screens/profile_screen.dart:1186` usa `get_user_tokens` directo — esse ecrã DEVE mostrar 748 (a "Token Balance Row"). Confirmar com Danilo se o ecrã onde viu "0" é wallet/cart e não o tokens card do profile.

---

## C. CONEXÃO COM BUG-005 / BUG-007 (OPEN HIGH)

- **BUG-005 ("tokens factor ×20")**: não reproduzível com estado actual. Trigger usa `ROUND(NEW.price * 3)` mín 1, batendo certo nos 64 tokens para €21.18. Provavelmente já fixado em sessão anterior. **Acção:** marcar como **likely-fixed, requires verification** — não baseado neste fix.
- **BUG-007 ("add_tokens silent fail")**: o `add_tokens` está saudável (INSERT … ON CONFLICT (source_order_id, role) DO NOTHING). Insere correctamente. Bug original era provavelmente "valores não aparecem na UI" — o que mapeia para o BUG 2 actual. **Acção:** este fix do `wallet_get_balance` **FECHA BUG-007** (alterar status para fixed).

---

## D. PROPOSTA DE CORREÇÃO (ANTES vs DEPOIS — texto, nada aplicado)

**Migration sugerida:** `supabase/migrations/20260510120000_fix_cashback_remove_and_tokens_read.sql` (UTF-8 sem BOM, comentários PT-PT).

### D.1 — BUG 1 (cashback)

```sql
-- ANTES: trigger e função creditam 1% em wallet em cada pedido delivered
-- DEPOIS: trigger e função removidos. Setting platform_settings.cashback_pct removido.

DROP TRIGGER IF EXISTS trg_award_cashback ON public.orders;
DROP FUNCTION IF EXISTS public.fn_award_cashback_on_delivery();
DELETE FROM public.platform_settings WHERE key = 'cashback_pct';
```

Notas:
- `_notify_on_cashback` (trigger de notificação em `wallet_transactions`) PODE ficar — não dispara sem inserts cashback novos. Manter (não é o cashback bug).
- `wallet_credit_generic` aceita `'cashback'` no enum mas isso é OK — usado pela admin grants futuras. Não tocar.
- Refund 80/20 (`wallet_credit_refund_split`) NÃO é tocado — fica intacto.

### D.2 — BUG 2 (tokens read)

```sql
-- ANTES: wallet_get_balance trata get_user_tokens (INTEGER) como JSONB → cai em catch → 0
-- DEPOIS: usa o INTEGER directamente

CREATE OR REPLACE FUNCTION public.wallet_get_balance(p_user_id uuid DEFAULT NULL::uuid)
…
  -- Substituir bloco:
  BEGIN
    SELECT COALESCE(public.get_user_tokens(v_target), 0) INTO v_tokens;
  EXCEPTION WHEN OTHERS THEN
    v_tokens := 0;
  END;
…
```

Mantém `SECURITY DEFINER`, `STABLE`, `search_path public`, JWT-role check, contrato JSONB de saída inalterado.

### D.3 — business_rules.md

- Remover qualquer menção de cashback 1% (se existir). Grep mostrou que o documento foca-se em refund 80/20 e tokens — **nenhuma menção explícita a cashback 1%** encontrada. Apenas adicionar nota em §32.4: cashback 1% foi **removido** em 2026-05-10.
- §4.2 (tokens) já diz "Cliente: 3% do valor em tokens" e §32.4 já documenta a discrepância `ROUND(price×3)` (que = 30% effective, não 3%). **Sugestão Danilo:** decidir nesta sessão ou em sessão dedicada? Por agora, **não tocar a fórmula** — só o read-path bug.

---

## E. ÁREAS PROIBIDAS — Confirmação

**NÃO TOCADAS:**
- `create_order` RPC
- `pricing_*` / `quote_order_pricing`
- `finalize_storeshopping_purchase`
- `wallet_apply_post_delivery_adjustment`
- Stripe/MBWay/create-payment-intent/stripe-webhook/refund/cancel-order-*
- `dispatch-engine`
- `notify-driver`
- 17 triggers em `orders` — **apenas lidos**. A correcção remove **apenas** `trg_award_cashback` (não está nos 17 originais — é trigger de cashback isolado).
- `enforce_financial_immutability`
- `supabase/.temp`
- Regra wallet refund 80/20

**Sem backfill. Sem estorno. Sem mudança em finalize/create_order.**

---

## F. PERGUNTAS PARA O DANILO (resposta no Claude.ai)

1. **OK para FASE 3** (aplicar migration D.1 + D.2 + commit + push)? ⚠️ Validation Gate
2. Onde viste o "tokens=0"? Ecrã de wallet/cart (consumidor de `wallet_get_balance`) OU o "Token Balance Row" do profile (consumidor de `get_user_tokens` directo)? Se foi o segundo, há **outro bug** que ainda não detectei.
3. Fórmula `ROUND(price×3)` mín 1 fica como está (= 64 tokens para €21.18)? Ou queres mudar para `ROUND(price × client_token_award_pct/100) = ROUND(21.18×0.03) = 1` token?
4. Admin panel: existe `admin_tokens_screen.dart`. **Já tens** UI admin para gerir tokens — confirmar se cobre o que precisas. Para verificar, listar a screen no relatório final.
5. BUG-005 (tokens ×20): marcar como **likely-fixed** com nota "verificado em 2026-05-10, fórmula `ROUND(price×3)` operacional, 64 tokens creditados em CAA3A9"?

---

## G. PLANO FASE 3 (só após OK)

1. Criar migration `20260510120000_fix_cashback_remove_and_tokens_read.sql` (Write tool, UTF-8 sem BOM)
2. `mcp__claude_ai_Supabase__apply_migration` no project ojykpzwqrtusfeakzrna
3. Re-validar via MCP:
   - `wallet_get_balance('c9fccf85'::uuid)->>'tokens_balance'` → deve retornar `"748"`
   - `SELECT 1 FROM pg_trigger WHERE tgname='trg_award_cashback'` → 0 rows
   - Setting `cashback_pct` ausente
4. `flutter analyze` → 0 erros novos
5. business_rules.md: nota em §32.4 + opcional remoção de §1%
6. 3 commits separados (cashback removal · tokens read fix · docs)
7. Push autonomous-night-2026-04-29
8. Relatório final em `.claude/.ai/reports/2026-05-10_fix_cashback_tokens.md` + espelho Obsidian

---

## H. PEDIDO DE TESTE FINAL (FASE 4)

Após FASE 3 aplicada, Danilo cria pedido novo de teste → entrega → executar queries de verificação (tokens creditados na DB + wallet_get_balance retorna correctamente + 0 entradas cashback novas).
