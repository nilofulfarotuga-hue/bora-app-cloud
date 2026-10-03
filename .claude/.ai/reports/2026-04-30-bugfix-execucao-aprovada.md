# Bug Fix Session — Execução Aprovada (2026-04-30)

> **Branch:** autonomous-night-2026-04-29 (pushed)
> **Stripe:** LIVE (pk_live, MBWay LIVE Novo Banco)
> **Commits:** 4 (2b011fd, 21b419d, 56b3247, 137701a)
> **Bugs reportados:** 10 + 3 descobertos durante análise
> **Resolvidos:** 12/13 (BUG 5 pendente repro)

---

## Tabela bug-a-bug

| # | Bug | Severidade | Status | Commit |
|---|-----|-----------|--------|--------|
| 1 | Order criada antes pagamento | CRÍTICO | ✅ resolvido | 21b419d (F2) |
| 2 | Saldo wallet visual ≠ DB | ALTO | ✅ resolvido | 137701a (F4) |
| 3 | Refund Stripe falha em órfãos | CRÍTICO | ✅ resolvido | 2b011fd (F1) |
| 4 | Sino notificações invisível | MÉDIO | ✅ resolvido | 137701a (F6) |
| 5 | Busca abre dropdown gorjetas | MÉDIO | ⏸ aguarda repro Danilo | — |
| 6 | Estafeta preso "Confirmar compra" | ALTO | ✅ resolvido | 56b3247 (F3) |
| 7 | Driver map sem partner pin | MÉDIO | ✅ resolvido | 137701a (F6) |
| 8 | Texto "80% vai estafeta" | BAIXO | ✅ resolvido | 137701a (F6) |
| 9 | Google Pay não funciona | ALTO | ✅ mitigado (escondido + setup doc) | 137701a (F5) |
| 10 | Token estafeta não creditado | ALTO | ✅ desbloqueado por F3 | 56b3247 |
| NEW-1 | refund_amount sem refund | ALTO | ✅ resolvido | 2b011fd (F1) |
| NEW-2 | cancel_reason aceita lixo | MÉDIO | ✅ resolvido | 137701a (F6) |
| NEW-3 | Constraint refund_consistency | ALTO | ✅ aplicado | 2b011fd (F1) |

---

## Causa raiz BUG 6 (T3.1 documentado)

**Mismatch de guards UI ↔ backend:**
- `driver_map_screen.dart:1336-1345` mostra botão em `driverAccepted | pickedUp | onTheWay`
- `order_store.dart:1307-1310` rejeitava silenciosamente em `driverAccepted` (só aceitava `pickedUp | onTheWay`)
- Comentário do próprio código (linhas 1328-1331) confirmava intenção de finalizar EM `driverAccepted`
- Resultado: `return false` silencioso → snackbar genérico → estafeta preso 36h (Order `6746d61f-...`)

Fix: novo método `finalizePurchaseWithReason()` retorna `String?` com razão específica + alarga guard para incluir `driverAccepted`.

---

## Decisão metadata vs payment_drafts (T2.1)

Sample MCP de 55 orders últimos 14 dias:
- avg cart items JSON: 366 chars
- p95: 842 chars
- max: 1040 chars

Stripe metadata: max 500 chars/key. p95 já ultrapassa.
**Decisão:** `payment_drafts` table (TTL 30min, RLS owner-read, pg_cron */5min cleanup).
Stripe PI metadata guarda só `draft_id` (UUID 36 chars, dentro do limite).

---

## DB changes (Supabase MCP)

### Migration 20260430250000_refund_consistency_orphan_cleanup
- Limpa 6 fantasmas refund_amount sem refund_method
- CHECK constraint `refund_consistency`
- Marca 3 órfãs noite 30/04 como `cancelled_no_charge`

### Migration 20260430260000_payment_drafts_gating
- Tabela `payment_drafts` (10 cols, RLS, 2 índices)
- RPC `quote_order_pricing(jsonb) → jsonb`
- RPC `create_order(jsonb) → jsonb` v4 (flag `payment_already_confirmed`)
- pg_cron `cleanup_payment_drafts` agendado */5min
- RPC `admin_list_orphans() → table(...)`

### Recovery prod
- Order `6746d61f-...` marcada cancelled (BUG 6 stuck 36h)

---

## Edge Functions deployed

| Função | Versão | Verify JWT | Modo |
|---|---|---|---|
| cancel-order-with-choice | v2 | true | F1 BUG 3 + NEW-1 |
| client-cancel-order | v10 | true | F1 + F6 NEW-2 |
| refund | v13 | true | F1 BUG 3 + 409 charge_missing |
| create-payment-intent | v20 | false | F2 dual-mode (legacy + new draft) |
| finalize-order-from-intent | v1 | true | F2 NEW |
| stripe-webhook | v16 | false | F2 dual route (draft_id vs order_id) |

---

## Smoke tests (Supabase MCP + flutter analyze)

✅ 0 fantasmas refund_amount sem refund_method
✅ Constraint refund_consistency activa
✅ payment_drafts table + 10 cols + 2 índices + RLS
✅ pg_cron job agendado e visível em `cron.job`
✅ 3 RPCs novas verificadas (`quote_order_pricing`, `admin_list_orphans`, `create_order` v4 com flag)
✅ Trigger `trg_award_tokens_on_delivery` confirmado em prod (driver +50/+40, client ROUND(price*3))
✅ `quote_order_pricing` testado: carryGroceries 2.5km → €6 customer_total
✅ `admin_list_orphans` retorna 3 órfãs F1 (cancelled_no_charge)
✅ `flutter analyze` 0 erros nos ficheiros tocados (3 info pré-existentes)
✅ Branch pushed → origin/autonomous-night-2026-04-29

---

## Comandos rollback por fase

### Fase 1 — refund guards
```sql
ALTER TABLE orders DROP CONSTRAINT IF EXISTS refund_consistency;
git revert 2b011fd
```
Edge Fns: redeploy versões anteriores via Supabase Dashboard se necessário.

### Fase 2 — payment gating
```sql
SELECT cron.unschedule('cleanup_payment_drafts');
DROP FUNCTION IF EXISTS public.quote_order_pricing(jsonb);
DROP FUNCTION IF EXISTS public.admin_list_orphans();
DROP TABLE IF EXISTS public.payment_drafts CASCADE;
-- create_order v4 → recriar v3 manualmente
```
```bash
git revert 21b419d
```

### Fase 3 — driver fix
```bash
git revert 56b3247
```
DB: nada a reverter (apenas marcou order preso como cancelled, ação one-shot).

### Fase 4-6 — UI polish
```bash
git revert 137701a
```
Edge Fn `client-cancel-order` v10 → redeploy v9 se reason validation causar issues.

---

## Pedidos a Danilo

### Imediato
1. **Repro BUG 5** — descrever passos ou screenshot do "campo busca abre dropdown gorjetas". Sem isto, fix é especulativo.
2. **Confirmar Stripe Dashboard** — Google Pay activado? Domain verified? SHA-1 registado?
3. **Testar fluxo card LIVE** — pedido real para validar Fase 2 end-to-end (orphan elimination + draft → finalize).

### Médio prazo
4. **Reactivar Google Pay** após setup (doc em `.claude/.ai/decisions/2026-04-30-google-pay-setup.md`).
5. **Wire admin_orphan_payments_screen.dart** ao admin_dashboard_screen.dart (próxima passagem).

---

## Bugs novos encontrados durante execução

Nenhum bug novo descoberto além dos 3 já documentados na análise (NEW-1, NEW-2, NEW-3). Estes 3 foram corrigidos em F1 + F6.

---

## ctx doctor

```
✅ Plugin enabled
✅ PreToolUse hook
✅ SessionStart hook
✅ Hook script exists
✅ FTS5 / SQLite native module
✅ Server initialization
⚠ npm v1.0.89 → latest v1.0.103 (correr /context-mode:ctx-upgrade)
⚠ Performance: NORMAL (Bun não instalado, 3-5x boost disponível)
- Language coverage: 4/11 (TypeScript runtime ausente — opcional)
```

`ctx-stats`: MCP context-mode tools não loaded nesta sessão. CLI standalone só inicia o servidor MCP. Após `/context-mode:ctx-upgrade` para v1.0.103 o tool `ctx_stats` deve ficar disponível.

---

## Estado branch + push

```
137701a fix(ui+payments): wallet display + Google Pay hide + map pickup pin + bell + tip text + cancel reason validation
56b3247 fix(driver): unblock confirm purchase + clear error feedback
21b419d fix(payment): gate order creation behind payment confirmation + admin orphans panel
2b011fd fix(refund): guard PI without charge + refund_amount consistency + cleanup orphans
736eedb fix(build): partner_dashboard activeThumbColor → activeColor (anterior à sessão)
```

**Pushed:** `origin/autonomous-night-2026-04-29`

---

## Próxima sessão

1. Aguardar feedback Danilo após teste manual real.
2. Repro BUG 5 quando enviado.
3. Wire admin orphans screen ao dashboard se Danilo aprovar.
4. Reactivar Google Pay quando setup Stripe Dashboard estiver completo.
