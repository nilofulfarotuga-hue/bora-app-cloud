# 04C — Audit Flutter productId Fix (Fase A)

**Data**: 2026-05-04
**Branch**: `autonomous-night-2026-04-29`
**Modo**: Read-only audit (Fase B aguarda luz verde)
**Estimativa Fase B**: 2-3h
**Pré-validação MCP**: ✅ confirmada (Claude.ai 2026-05-04)

---

## 📊 Resumo executivo

Bug é **muito mais pequeno** do que a memória inicial sugeria:

- **3 call sites de escrita confirmados com bug** (não 30+, não 107)
- **1 único ponto de RPC `create_order`** — perfeito para defesa única `validateOrderPayload`
- **Fix é HÍBRIDO**: validation no constructor de `CartItem` (Opção A) + 3 edits cirúrgicos (Opção B)
- **Split α/β NÃO necessário**
- **4-5 ficheiros tocados na Fase B**

---

## ✅ A0 — Regressão MCP Sessões 1-5A-2-β

| Item | Esperado | Real | Status |
|------|----------|------|--------|
| Tabelas suporte (public) | 7 | 7 reais (nomes diferentes) | ✅ |
| RPCs suporte SQL | 6 | 3 SQL + 2 Edge Fns | ⚠️ ver nota |
| support_skills active | 9 | 9 | ✅ |
| Coords NULL pós 0503 | 0 | 0 | ✅ |
| Wallet CHECK -2000 | exists | `client_wallets.free_balance_cents >= -2000` | ✅ |
| trg_zz_final_total_dual_write | 1 | 1 | ✅ |
| extra_charge_settled_via column | 1 | 1 | ✅ |
| create_order overloads | 1 | 1 | ✅ |
| pricing_calculate 6-arg overloads | 1 | 1 | ✅ |

### Nomes reais das 7 tabelas suporte (public)
`support_agent_actions`, `support_chatbot_messages`, `support_chatbot_quota`, `support_chatbot_sessions`, `support_settings`, `support_skills`, `support_tickets`

> ⚠️ Memória/prompt assumiu `support_messages`, `support_ticket_skills`, `support_ticket_history`, `support_attachments`, `support_ai_runs` — esses nomes **não existem**. Não é regressão; é divergência de naming. Recomenda-se actualizar memória `MEMORY.md`.

### RPCs SQL suporte (public)
`admin_kpi_avg_ticket`, `admin_resolve_ticket`, `file_support_ticket`

### Edge Functions suporte (ACTIVE)
`support-submit-ticket` v1, `support-chatbot` v1

> ⚠️ Memória/prompt esperava 6 RPCs SQL. Real são 3 SQL + 2 Edge Fns (5 total). Diferença pode ser RPCs renomeadas durante 5A-1 ou inline em Edge Fns. Não bloqueia 4C.

### Conclusão A0
✅ **Nenhuma regressão real**. Todas as estruturas críticas para Sessão 4C intactas.

---

## 🧠 A1 — Classes Product (4 encontradas)

| # | Classe | Ficheiro | id field | fromMap/factory | Risco |
|---|--------|----------|----------|-----------------|-------|
| 1 | `ProductVariant` | `lib/models/product_variant.dart:1` | `String` (required) | `fromSupabase(data)` → `data['id']` | ✅ OK |
| 2 | `PartnerProduct` | `lib/models/partner_product.dart:3` | `String` (required) | sem fromMap próprio (construído inline) | ✅ OK |
| 3 | `MenuItem` | `lib/models/business_view_models.dart:1` | `String?` **NULLABLE** | `fromMap(map)` → `map['productId']` | ⚠️ nullable |
| 4 | `MarketProduct` | `lib/models/business_view_models.dart:52` | **SEM CAMPO** | sem fromMap | 💀 dead code |

### MarketProduct
- Apenas `name` + `price`. **Não tem id** → impossível enviar productId real.
- Usado **zero** vezes para construir orders. É display puro de fake_data.
- **Não é fonte do bug** (mas é dead code candidato a remoção em sessão futura).

### MenuItem.productId nullable
- `lib/utils/business_mapper.dart:24-28` constrói com `productId: product.id` (Bug-B fix 2026-04-30 — comentário no código).
- Mas `restaurant_menu_screen.dart:188` tem fallback `item.productId ?? item.name` → 🐛 **bug latente** (se MenuItem.productId for null por qualquer razão, name vai como productId).

---

## 🧠 A1b — Deserializadores (todos correctos na fonte)

| Origem | Linha | productId source | Status |
|--------|-------|------------------|--------|
| `RestaurantStore.loadProductsFromSupabase` | 249 | `data['id']` | ✅ |
| `RestaurantStore` clones | 357, 397, 522 | passthrough id | ✅ |
| `ProductVariant.fromSupabase` | 14 | `data['id']` | ✅ |
| `MenuItem.fromMap` | 31 | `map['productId']` | ✅ |
| `BusinessMapper.buildRestaurantMenu` | 24 | `product.id` | ✅ (Bug-B fix) |
| `_resolveProduct` em store_products_screen | 1499 | `row['id']` | ✅ |

> **A fonte está OK. O bug está nos call sites de cart-add que IGNORAM o id e usam chaves sintéticas.**

---

## 🧠 A2 — CartItem (mitigação 4B5 confirmada)

`lib/models/cart_item.dart`:
- ✅ Asserts (linhas 22-26): vazio, espaço, length<200 — **dev/debug only**
- 🐛 `fromJson` linha 53: fallback `?? name` para legacy data persistida em `orders.items` pré-Bug-B fix (`_raw` constructor sem asserts).
- ⚠️ Em release: asserts strip → 0 defesa run-time.

---

## 🧠 A3 — Call sites productId (categorização)

**Total productId/product_id matches**: ~50-60 (não 107 como sugerido em memória).

### 🐛 ESCRITA com BUG (3 confirmados)

| # | Ficheiro | Linha | productId source actual | Por quê é bug |
|---|----------|-------|--------------------------|---------------|
| 1 | `lib/screens/product_detail_screen.dart` | **28** | `_variantKey(v)` = `'${product.name}__${v.id}'` | Embute nome do produto na chave (espaços + texto) |
| 2 | `lib/screens/store_products_screen.dart` | **872** | `_variantKey` = `'${productName}__${variant.id}'` | Idem |
| 3 | `lib/screens/store_products_screen.dart` | **1149** | `_variantKey` = `'${productName}__${variant.id}'` | Idem |
| 4 | `lib/screens/restaurant_menu_screen.dart` | **188** | `item.productId ?? item.name` | Fallback nome quando MenuItem.productId é null |

> **4 sítios, não 3** — confirmei `store_products_screen` tem 2 ocorrências do mesmo padrão `_variantKey` (linhas 872 e 1149).

### ✅ ESCRITA correcta (passthrough OK)
- `product_detail_screen.dart:50` — `widget.product.id`
- `store_products_screen.dart:1066` — `widget.product.id`
- `restaurant_menu_screen.dart:460` — `product.id`
- `partner_products_screen.dart:51` — `product.id`
- `driver_map_screen.dart:1071` — `i.productId` (passthrough do CartItem)
- `driver_map_screen.dart:2141` — `'extra_${timestamp}'` (sentinela legítima)
- `reorder_service.dart:61` — `it.productId` (passthrough OrderModel.items)
- `cart_store.dart:302/392/478` — passthrough `item.productId`
- `order_store.dart:428/624/1732` — passthrough `item.productId`
- `business_mapper.dart:25` — `product.id` (Bug-B fix 2026-04-30)
- `admin_catalog_screen.dart:186/218/249` — `p['id']`
- `admin_partner_detail_screen.dart` — `productId` parameter (passthrough)

### 🎯 ÚNICO ponto de RPC `create_order`
`lib/stores/order_store.dart:714`:
```dart
await supabase.rpc('create_order', params: {'p_input': rpcInput});
```
+ canal alternativo via Edge Fn `create-payment-intent` (`order_store.dart:474` no payload `cart_input`).

→ **2 sítios para chamar `validateOrderPayload`**: linhas 474 e 714 do `order_store.dart`.

### LEITURA / DISPLAY (sem fix)
- ~30+ matches em `partner_call_driver_screen`, comments, dropdowns, etc.

---

## 🧠 A4 — Trace amostra (5 sítios traçados)

| Call site | Backwards trace | Conclusão |
|-----------|-----------------|-----------|
| `product_detail_screen:28` | `_variantKey(v)` design errado — embute `product.name` deliberadamente | 🐛 fix em call site |
| `store_products_screen:872` | `_variantKey` getter design errado | 🐛 fix em call site |
| `store_products_screen:1149` | `_variantKey` getter (provavelmente outra classe) design errado | 🐛 fix em call site |
| `restaurant_menu_screen:188` | `MenuItem.productId` é nullable + fallback `?? item.name` | 🐛 remover fallback |
| `business_mapper:24` | `product.id` correcto (PartnerProduct id real DB) | ✅ |

> **Bug NÃO está em fromMap nenhum.** Bug está em call sites que deliberadamente criam productId sintético embutindo o nome.

---

## 🧠 A5 — Logging strategy (✅ feito)

`grep -rn 'Sentry\|crashlytics' lib/ pubspec.yaml` → **AUSENTES**.
→ B5 usa `debugPrint(...)` (já standard no codebase).

---

## 📋 A6 — Análise impacto (Fase B)

### Ficheiros a tocar (4-5)
1. `lib/models/cart_item.dart` — adicionar validation run-time no constructor (throw ArgumentError)
2. `lib/screens/product_detail_screen.dart` — `_variantKey` deve usar `v.id` puro (não embutir nome)
3. `lib/screens/store_products_screen.dart` — 2 sítios `_variantKey`, mesma fix
4. `lib/screens/restaurant_menu_screen.dart` — remover `?? item.name` fallback
5. `lib/stores/order_store.dart` — adicionar helper `validateOrderPayload` + chamadas nas linhas 474 e 714

### Risco
**BAIXO**:
- Mitigação SQL 4B5 unit_price fallback fica activa server-side
- Asserts dev/debug 4B5 ficam (defesa em profundidade)
- Sem refactor adicional fora do scope
- Bug está em paths bem identificados

### Rollback
`git revert <commit>` — fix é cirúrgico em 4-5 ficheiros.

---

## 📋 A7 — Decisão Opção A vs B

**HÍBRIDA (recomendada)**:
- ✅ Opção A parcial: `CartItem` constructor adiciona validation `if-throw` em release
- ✅ Opção B (cirúrgica): 4 sítios `_variantKey`/fallback corrigidos
- ✅ Defesa adicional: `validateOrderPayload` helper antes de cada `create_order` invocation (2 sítios)

**Por quê não Opção A pura?**
A "fonte" não é fromMap; é design errado de `_variantKey`. Para variants, `ProductVariant.id` já é UUID — usar esse directamente. Para casos sem variant, usar `product.id`. Não há um único fromMap para corrigir.

---

## 📋 A8 — Decisão split α/β

**Split NÃO necessário**: apenas 4 sítios precisam fix cirúrgico. Fase B inteira numa sessão.

---

## 📋 A9 — Smokes plan (Fase B)

| # | Smoke | Ferramenta |
|---|-------|------------|
| S1 | `flutter analyze` → 0 erros novos (baseline 54) | bash |
| S2 | Inspecção manual `CartItem` constructor + `_variantKey` + `validateOrderPayload` | manual |
| S3 | Mental test `CartItem(id:'cnt-123')` ✅ vs `CartItem(id:'Leite')` ❌ throw | mental |
| S4 | Mental test `validateOrderPayload` payload válido ✅ vs payload com nome longo ❌ throw | mental |
| S5-S10 | Regressão: coords NULL=0, 7 tabelas, 9 skills, trg, wallet, BUG 35/38 | MCP |

---

## 📋 A10 — Skill identification

Nenhuma skill nova identificada nesta Fase A. Todas as operações cobertas por skills existentes (`ceo-ai`, `simplify`, `auto-rules-sync`).

---

## ⏭ Bugs colaterais detectados

🐛 **MarketProduct dead code** (`business_view_models.dart:52`): classe sem id, usada para nada. Candidata a remoção em sessão housekeeping.

🐛 **CartItem.fromJson fallback `?? name`** (linha 53): tolerância consciente para legacy data em `orders.items`. Não corrigir nesta sessão (rebenta histórico). Limpeza retroactiva = sessão dedicada (item TODO).

⚠️ **Memória `MEMORY.md` desactualizada** quanto a nomes das tabelas suporte e contagem de RPCs SQL — recomenda-se actualizar quando Sessão 5A-1 retrospectiva final for feita.

⚠️ **`/ctx-upgrade` falhou** (npm não no PATH). v1.0.89 → v1.0.111 pendente. Adicionado a `sessao_4c_pending.md`.

---

## 📦 Lista exacta de mudanças propostas (Fase B)

```
B1. lib/models/cart_item.dart
    + validation if-throw no constructor (em release)
    + manter asserts 4B5 (dev/debug)
    + (NÃO tocar fromJson._raw — legacy compatibility)

B2. lib/screens/product_detail_screen.dart
    - _variantKey(v) = '${product.name}__${v.id}'
    + _variantKey(v) = v.id  // ProductVariant.id é UUID

B3. lib/screens/store_products_screen.dart  (2 sítios)
    - _variantKey = '${productName}__${variant.id}'
    + _variantKey = variant.id  // ProductVariant.id é UUID

B4. lib/screens/restaurant_menu_screen.dart
    - productId: item.productId ?? item.name
    + productId: item.productId ?? (throw StateError('MenuItem sem productId: ${item.name}'))
    OU MenuItem.productId não-nullable + tornar required + actualizar fromMap

B5. lib/stores/order_store.dart
    + bool isValidProductId(String id) helper
    + void validateOrderPayload(Map payload) helper
    + chamada validateOrderPayload(cartInput) ANTES de linha 474 (Edge Fn payment intent)
    + chamada validateOrderPayload(rpcInput) ANTES de linha 714 (RPC create_order)
```

---

## ⛔ STOP — Aguardar luz verde Danilo para Fase B

Resposta esperada:
- `OK FASE B` — proceder com B1→B5 + smokes + relatório + commit + sync
- `OK B1+B5 PRIMEIRO` — fix mínimo (CartItem validation + validateOrderPayload), B2-B4 sessão futura
- `STOP` — não prosseguir
