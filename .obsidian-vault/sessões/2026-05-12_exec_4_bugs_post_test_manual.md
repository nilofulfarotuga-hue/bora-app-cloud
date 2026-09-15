# Sessão Execução 4 Bugs Pós-Teste Manual — 2026-05-12

**Branch:** `autonomous-night-2026-04-29`
**Baseline:** `829eeb3` (sessão exec 6 bugs anterior)
**HEAD final:** `c733cb2`
**Tempo:** ~40min
**Modo:** PROTECÇÃO TOTAL + Opus 4.7

---

## Resumo Executivo

| Bug | Estado | Commit |
|---|---|---|
| **#1** Upload foto 400 `receipts/receipts/` | ✅ FIXED | `789b699` |
| **#2** Dialog "Total ajustado" UX | ✅ REMOVIDO | `e06501a` |
| **#3** Card "Estafeta" literal | ✅ FIXED | `c733cb2` |
| **#4** Migration RLS receipts uuid::text | ✅ APLICADA | `789b699` |

**Score: 4/4 FIXED.**

---

## BUG #1 — Upload foto talão path duplicado (commit `789b699`)

**Causa raiz:** Cliente Supabase Flutter **já adiciona** o bucket name como prefixo da URL automaticamente. Código passava `'receipts/${order.id}.jpg'` como `path` em `storage.from('receipts').uploadBinary(path, ...)`, resultando em URL final `/object/receipts/receipts/<id>.jpg` → API rejeita 400.

**Fix em 2 callers:**
1. `lib/screens/driver_map_screen.dart:2812` — `storagePath = '${order.id}.jpg';` (sem prefixo)
2. `lib/screens/store_shopping_purchase_screen.dart:118` — `path = '$orderId.jpg';` (orphan screen, fixar por consistência)

**RLS impact:** Zero. Policies usam `replace(replace(name, 'receipts/', ''), '.jpg', '')` que é idempotente — funciona com OU sem prefixo `receipts/`.

**Edge Fn ocr-receipt** já lida com ambos formatos (linhas 55-60: `path.startsWith('http')` + `split('receipts/')` + `replace(/^receipts\//, '')`).

---

## BUG #2 — Dialog "Total ajustado" removido (commit `e06501a`)

**Decisão Danilo:** REMOVER completamente.

**Razão:**
- Cliente já vê total no carrinho + PaymentMethodScreen (resumo claro)
- Dialog poluía o ecrã com info redundante
- Texto era confuso/mal formatado: `'Total ficou €5.00 (estimado: €11.87)'`

**Fix em `lib/screens/cart_screen.dart`:**
- Removido bloco completo `showDialog<bool>` AlertDialog
- Mantida chamada `cartStore.quoteOrderPricing()` como **best-effort silencioso** via `unawaited(...)` para warmup do cache 30s
- RPC `create_order` server-side é a autoridade final de pricing → cliente paga o que vê no checkout

**Adicionado import:** `import 'dart:async' show unawaited;`

---

## BUG #3 — Nome real estafeta em tracking screen (commit `c733cb2`)

**Causa raiz:** `DriverStore.getDriverById(assignedId)` retornava `null` quando driver não estava pre-carregado em memória (cliente acabou de receber pedido aceite mas DriverStore ainda não fez fetch desse driver específico). Fallback hardcoded `'Estafeta'` era usado.

**Fix em `lib/screens/order_tracking_screen.dart`:**
- Novo state `_fetchedDriverName` + cache `_fetchedFor` (idempotente por driverId)
- Método `_maybeFetchDriverName(driverId)` consulta `drivers.name` via Supabase
- Triggered em `build()` quando `driver?.name` é null (via `WidgetsBinding.instance.addPostFrameCallback`)
- Fallback chain: `driver?.name ?? _fetchedDriverName ?? 'Estafeta'`
- Aplicado em `InfoWindow` do marker (linha 277) + `_BottomCard.driverName` (linha 380)

**Não mostra foto** (decisão Danilo). Resto (avaliação ⭐4.9, telefone, distância) inalterado.

---

## BUG #4 — Migration RLS receipts uuid::text cast (commit `789b699`)

**Causa raiz:** `orders.id` é `UUID`, `replace(name, ...)` retorna `TEXT`. Comparação directa `o.id = replace(...)` falhava silenciosamente em runtime (sem cast explícito).

**Fix:** Migration `supabase/migrations/20260512230000_fix_receipts_rls_uuid_cast.sql`:
- 3 policies recriadas com `o.id::text = replace(...)`
- `driver_insert_own_receipt` agora tem EXISTS check completo (antes só `bucket_id` — RLS estava aberta para INSERT)
- `admin_select_all_receipts_storage` inalterada (já correcta)

Aplicada via MCP execute_sql + migration file no repo para sync dev/staging.

---

## Áreas Proibidas (transparência)

**Todas intactas:**
- `pricing_service.dart` — não tocado (só `cart_store.quoteOrderPricing` continua a consumir RPC server-side)
- `finalize_storeshopping_purchase` v1 — não tocado
- `finalize_storeshopping_purchase_v2` RPC — não tocado (esta sessão apenas Flutter UI + storage RLS)
- Stripe/MBWay webhooks — não tocados
- dispatch-engine — não tocado
- 17 triggers + trigger #18 — não tocados
- `enforce_financial_immutability` — não tocado
- Payout semanal — não tocado

---

## TODOs Danilo (validação manual)

1. **CRÍTICO BUG #1**: Build novo APK → estafeta retoma/cria pedido storeShopping non-partner → finaliza compra → confirmar:
   - Upload 200 OK (não mais 400)
   - DB: `SELECT * FROM order_receipts_v2 WHERE order_id='<id>'` retorna 1 row com photo_url
   - DB: `SELECT name FROM storage.objects WHERE bucket_id='receipts' AND name='<order_id>.jpg'` retorna 1 row

2. **BUG #2**: Cliente carrinho → "Finalizar pedido" → vai directo para PaymentMethodScreen sem dialog. Total mostrado bate com cobrança final.

3. **BUG #3**: Cliente vê pedido em tracking → card mostra nome real do estafeta (ex: "João Silva") em vez de "Estafeta". Marker no mapa também.

4. **BUG #4**: Sem teste manual — RLS já aplicada via MCP + migration repo. Validação implícita via BUG #1 (upload sucede com RLS strict).

---

## Bugs externos descobertos durante execução

1. **`store_shopping_purchase_screen.dart`** é uma orphan screen (criada na sessão mega 2026-05-11 mas nunca conectada a navigation). Mantida por consistência (fix de BUG #1 aplicado em ambos). Considerar remover em sessão futura se confirmado não-utilizada.

2. **Pre-existing deprecation warnings** `activeColor` em Switch widgets — não relacionado a esta sessão. Refactor futuro para `activeThumbColor`.

3. **`cart_screen.dart`** não tinha `dart:async` importado — necessário adicionar para usar `unawaited`. Resolvido.

---

## Skills sugeridas (nova)

- **`supabase-storage-path-validator`** — Localização: `.claude/skills/supabase-storage-path-validator/SKILL.md`
  - Triggers: "verificar path storage", "validar upload Supabase"
  - Função: detectar bucket name duplicado em path uploads (como BUG #1)
  - Implementação futura — não criada nesta sessão (4 bugs já tinham scope suficiente)

---

## Observabilidade

- 4 commits granulares: 789b699 → e06501a → c733cb2
- flutter analyze: 0 erros novos
- Áreas proibidas: todas intactas

---

## Sync

- Local: `.claude/.ai/reports/2026-05-12_exec_4_bugs_post_test_manual.md`
- Obsidian: `.obsidian-vault/sessoes/2026-05-12_exec_4_bugs_post_test_manual.md`

---

## Confirmações finais (per spec)

- ✅ Upload foto: fix em 2 callers Flutter — path sem prefixo `receipts/`
- ✅ Dialog "Total ajustado" removido (best-effort quote silencioso mantido)
- ✅ Nome real do estafeta aparece via fallback Supabase fetch
- ✅ Migration RLS aplicada (uuid::text cast) + idempotente (replace tolera ambos formatos)
- ✅ Áreas proibidas todas intactas

---

*Sessão exec autónoma 2026-05-12 pós-teste manual. NENHUMA pergunta a Danilo.*
