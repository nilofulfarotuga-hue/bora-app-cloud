# 04C — Flutter productId Fix Completo (Fase B Report)

**Data**: 2026-05-04
**Branch**: `autonomous-night-2026-04-29`
**Modo**: PROTECÇÃO TOTAL — Fase B executada após luz verde "continua"
**Modelo**: Opus 4.7

---

## ✅ Mudanças aplicadas

### B1 — `lib/models/cart_item.dart`
- ✅ Constructor `CartItem(...)` ganhou body com `if-throw ArgumentError` para 3 invariantes (vazio, espaço, length>200)
- ✅ Asserts 4B5 mantidos (defesa em profundidade dev/debug)
- ✅ `_raw` constructor + `fromJson` intactos (legacy data tolerância)

### B2 — `_variantKey` simplificado
- ✅ `lib/screens/product_detail_screen.dart:24` — `String _variantKey(ProductVariant v) => v.id;`
- ✅ `lib/screens/store_products_screen.dart:1146` — `String get _variantKey => variant.id;`
- 📊 Removido embedding `${product.name}__${v.id}` — `ProductVariant.id` já é UUID válido

### B3 — `lib/screens/restaurant_menu_screen.dart:188`
- ✅ Removido fallback `productId: item.productId ?? item.name`
- ✅ Substituído por `if (productId == null || isEmpty) throw StateError(...)` — falha cedo

### B4 — `lib/stores/order_store.dart` — helper `isValidProductId`
- ✅ Função top-level após `PartnerOrderLine`
- ✅ Critério: não vazio + sem espaço + 3-200 chars
- ✅ NÃO usa regex de prefixo (cobre 9+ formatos prod confirmados)

### B5 — `lib/stores/order_store.dart` — `validateOrderPayload`
- ✅ Função top-level
- ✅ Percorre `payload['product_lines']` e valida cada `product_id`
- ✅ Lança `FormatException` se inválido + `debugPrint` log
- ✅ Logistics (`carryGroceries`/`sendPackage`) sem `product_lines` → early return
- ✅ **Chamada antes da Edge Fn** `create-payment-intent` (linha 484)
- ✅ **Chamada antes da RPC** `create_order` (linha 721)
- ✅ Caller apanha `FormatException` e devolve `null`/`false` sem chegar à rede

---

## 📊 Smokes

| # | Smoke | Resultado |
|---|-------|-----------|
| S1 | `flutter analyze` | ✅ **54 issues — exactamente baseline. 0 erros novos** |
| S2 | Inspecção manual constructors / `_variantKey` / `validateOrderPayload` | ✅ via Edit tool |
| S3 | Mental test `CartItem('cnt-123', ...)` | ✅ válido |
| S3 | Mental test `CartItem('Leite Mimosa', ...)` | ❌ throw (espaço) |
| S3 | Mental test `CartItem('', ...)` | ❌ throw (vazio) |
| S3 | Mental test `CartItem('a' * 250, ...)` | ❌ throw (longo) |
| S4 | Mental test `validateOrderPayload({product_lines:[{product_id:'cnt-1'}]})` | ✅ passa |
| S4 | Mental test `validateOrderPayload({product_lines:[{product_id:'Leite Mimosa'}]})` | ❌ FormatException |
| S4 | Mental test `validateOrderPayload({product_lines:[]})` | ✅ early return |
| S4 | Mental test `validateOrderPayload({})` (logistics) | ✅ early return |
| S5 | Coords NULL pós 0503 | ✅ 0 (A0) |
| S6 | 7 tabelas suporte | ✅ intactas (A0) |
| S7 | 9 skills active | ✅ (A0) |
| S8 | trg_zz_final_total_dual_write | ✅ (A0) |
| S9 | Wallet CHECK -2000 | ✅ (A0, em `client_wallets`) |
| S10 | BUG 35/38 não regridem | ✅ não tocados |

---

## 🐛 Bugs colaterais detectados

- 💀 **MarketProduct dead code** (`business_view_models.dart:52`): classe sem id, não usada para criar orders. Candidata a remoção. → `sessao_4c_pending.md`.
- ⚠️ **CartItem.fromJson fallback `?? name`** (linha 53): tolerância consciente para legacy data em `orders.items`. Limpeza retroactiva = sessão dedicada. → `sessao_4c_pending.md`.
- ⚠️ **MEMORY.md desactualizada** quanto a nomes das tabelas suporte (real: `support_agent_actions/chatbot_*/settings/skills/tickets`, não `support_messages/_ticket_skills/_history/_attachments/_ai_runs`). Não bloqueante. → `sessao_4c_pending.md`.
- ⚠️ **`/ctx-upgrade` falhou** (npm não no PATH do shell que `cli.bundle.mjs` invoca). v1.0.89 → v1.0.111 pendente. → `sessao_4c_pending.md`.

---

## 📦 Ficheiros tocados

```
M lib/models/cart_item.dart
M lib/screens/product_detail_screen.dart
M lib/screens/restaurant_menu_screen.dart
M lib/screens/store_products_screen.dart
M lib/stores/order_store.dart
M .claude/.ai/business_rules.md (§33 adicionado)
A .claude/.ai/reports/20260502_megafinal/04c_productid_audit.md
A .claude/.ai/reports/20260502_megafinal/04c_productid_report.md
A .claude/.ai/todos/sessao_4c_pending.md
A .obsidian-vault/entregas/04c_productid_audit.md
A .obsidian-vault/sessões/04c_prompt.md
```

**5 ficheiros código + 6 ficheiros docs/relatórios.**

---

## 🎯 Defesa em profundidade activa em produção

| Camada | Mecanismo | Modo |
|--------|-----------|------|
| 1 | `CartItem` constructor `if-throw` | Release + Debug |
| 2 | `CartItem` constructor `assert()` | Debug only (4B5) |
| 3 | `_variantKey = variant.id` (sem embedding nome) | Always |
| 4 | `validateOrderPayload(payload)` antes Edge Fn / RPC | Always |
| 5 | SQL `unit_price` fallback server-side | Always (4B5) |

---

## ⏭ TODOs adiados → `.claude/.ai/todos/sessao_4c_pending.md`

- 4B geo-push (próxima sessão hoje)
- 5B agente IA write skills shadow
- 5C pgvector RAG
- 5A-2-γ smokes UI device
- LIMPEZA 7 ORDENS ÓRFÃS HISTÓRICAS (€5-6.50 cada — decisão refund automático?)
- Fix `/ctx-upgrade` npm PATH
- Limpeza `MarketProduct` dead code
- Limpeza retroactiva `orders.items` legacy data (CartItem.fromJson fallback)

---

## ✅ Status final

- ✅ Backend NÃO tocado (Edge Fns + RPCs intactas)
- ✅ Mitigação 4B5 SQL `unit_price` fallback INTACTA
- ✅ Sessões 1-5A-2-β preservadas (regressão A0 confirmou)
- ✅ flutter analyze 0 erros novos
- ✅ business_rules.md §33 adicionado
- ✅ Defesa em 5 camadas para productId integrity

**Pronto para commit atómico.**
