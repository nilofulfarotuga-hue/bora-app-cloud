# AUDITORIA + RE-REBUILD FAST-FOOD (variantes de tamanho) — Guarda

**Data:** 2026-06-08 · **Branch:** autonomous-night-2026-04-29 · **Fonte:** Glovo Guarda
**Preço:** `preço_DB = ROUND(preço_glovo / 1.15, 2)` → cliente paga = Glovo.

---

## 🔍 SECÇÃO 1 — DIAGNÓSTICO DO HARVESTER v1

**Premissa do prompt (harvester perde produtos por não seguir paths) — VERIFICADA E REFUTADA.**

Investigação (`.ai_rest_debug.js` + `.ai_mcd_deep.js`):
1. **As secções LIST do McD NÃO têm `action.path`** (`pathFull=-` em todas as 9 estruturais; só "Mais vendidos", excluída, tem path). → Não há sub-páginas por seguir. O v1 **já capturava os 146 PRODUCT_ROW inline** (98 únicos após excluir promo + dedup).
2. **McD=98 vs KFC=176 NÃO é bug** — é diferença estrutural real: o **KFC lista cada tamanho de combo como linha própria** (Box Meal, Menus Burgers/Wraps/Pedaços…), enquanto o **McD usa 1 linha + seletor de tamanho dentro do item** (campo `attributeGroups`).
3. **A "falta" real = variantes de TAMANHO** dentro de `attributeGroups`, que o v1 ignorava. Estes vêm **completos e com preços no payload da home** (`priceImpact`), grupo `"Selecione o Tamanho"`:
   - `McMenu® Big Mac®` €7,90 → Médio (+0) / **Grande (+1,90)**
   - `Coca-Cola Pequena` → Média / Grande
   - (Grupos de *escolha* — bebida/acompanhamento — e *extras* — molho/complemento — NÃO são variantes; ficam de fora.)

**Comparação com `glovo_grocery_crawler.js` (mercados):** os mercados usam `COLLECTION_TILE`/`CONTENT_PLACEHOLDER` recursivos (categorias com milhares de produtos em sub-páginas). Restaurantes usam `LIST` inline (menu pequeno, tudo na home) — por isso o crawler de mercados não se aplica; o gap dos restaurantes é variantes, não recursão.

**Decisão do Danilo (AskUserQuestion):** *"Expandir só TAMANHOS"* — 1 produto por tamanho real; não expandir escolhas/extras.

---

## 🔧 SECÇÃO 2 — HARVESTER v2 (`.ai_rest_harvest_v2.js`)

v1 intacto (histórico). v2 = v1 + **expansão de variantes de tamanho**:
- Para cada PRODUCT_ROW, lê os `attributeGroups` cujo nome contém **"tamanho"/"size"**.
- Cada opção com `priceImpact != 0` → **novo produto**: `id={storeProductId}-s{attrId}`, `price = base + priceImpact` (Glovo €, depois ÷1,15 no apply).
- **Naming limpo:** retira a palavra de tamanho final do nome base e acrescenta `(Tamanho)` → `Coca-Cola Pequena` + Média = **`Coca-Cola (Média)`**; `McMenu® Big Mac®` + Grande = **`McMenu® Big Mac® (Grande)`**. Limpa labels Glovo ("Grande (Large)"→"Grande", "Grande P"→"Grande").
- NÃO expande grupos de escolha (bebida/acompanhamento) nem extras (molho/complemento).

---

## 📊 SECÇÃO 3 — AUDITORIA v2 + RE-REBUILDS

| Restaurante | v1/DB | base v2 | +variantes | **total v2** | Decisão |
|---|---:|---:|---:|---:|---|
| **McDonald's** | 98 | 98 | **+33** | **131** | RE-REBUILD (variantes) |
| **Burger King** | 169 | 173 | 0 | **173** | RE-REBUILD (+4 drift; 0 size groups) |
| **KFC** | 176 | 176 | 0 | **176** | re-aplicado (idêntico; 0 size groups) |

**Insight:** só o McD tem grupos de tamanho in-item → +33 variantes. KFC e BK **já listam tamanhos como linhas** (0 variantes expandidas) — confirma que estavam completos. BK ganhou +4 produtos (drift natural do Glovo desde a sessão anterior, em secções existentes).

Todos: backup `_backup_{loja}_pre_audit_2026_06_08` (98/169/176) → DELETE (6 retries blindados) + INSERT ÷1,15. sem_foto=0, sem_preço=0, com_sort=100%.

### Variantes capturadas (McD, exemplos)
- **Combos:** McMenu® Big Mac® €7,90 + **(Grande) €9,80**; McMenu Big Arch €13 + (Grande) €14,90
- **Bebidas (3 tamanhos):** Coca-Cola Pequena **€1,90** · Coca-Cola (Média) **€2,00** · Coca-Cola (Grande) **€2,10** (idem Coca-Cola Zero, Fanta Zero, Fuze Tea…)

### Sample com ÷1,15 (glovo → ÷1.15 = DB → ×1.15 = cliente)
| Produto | cat | glovo | DB | cliente |
|---|---|---:|---:|---:|
| McMenu® Big Mac® | Sanduíches e McMenu | 7,90 | **6,87** | 7,90 ✓ |
| McMenu® Big Mac® (Grande) | Sanduíches e McMenu | 9,80 | **8,52** | 9,80 ✓ |
| Coca-Cola (Média) | Bebidas | 2,00 | **1,74** | 2,00 ✓ |
| Coca-Cola (Grande) | Bebidas | 2,10 | **1,83** | 2,10 ✓ |
| Happy Meal® Chicken McNuggets® | Happy Meal | 6,10 | **5,30** | 6,10 ✓ |
| McFlurry® Daim e Caramelo | Sobremesas | 3,90 | **3,39** | 3,90 ✓ |

McCafé: McD Guarda não tem secção McCafé dedicada no Glovo (cafés ficam em Bebidas/Sobremesas). Pequeno-Almoço: continua time-gated (~06–10h30) — follow-up matinal.

---

## 📋 SECÇÃO 4 — CONSOLIDADO (4 fast-food Guarda)

| Restaurante | Antes | **Depois** | Categorias | Estado |
|---|---:|---:|---:|---|
| **McDonald's** | 98 | **131** | 9 | ✅ +33 variantes tamanho |
| **Burger King** | 169 | **173** | 11 | ✅ +4 drift (0 variantes) |
| **KFC** | 176 | **176** | 16 | ✅ exacto (0 variantes) |
| **Pizza Hut** | 78 | **78** | 9 | 🚫 OCULTO — **intacto** (`com_sort=0` prova) |

## 🛡️ Zonas protegidas
`pizzahut-guarda` (`is_online=false`+`is_active_admin=false`) **NÃO tocado** (com_sort=0). Parceiros/testes intactos. `pricing_calculate` só lido. Dispatch/triggers/Stripe/RLS/tokens intactos. Mutação só em `products` non-partner.

## 🧰 Artefactos
`.ai_rest_harvest_v2.js` (harvester + variantes tamanho) · `.ai_mcd_deep.js` (investigação attributeGroups) · `.ai_{mcd,bk,kfc}_v2.json` · reusa `.ai_4lojas_apply.js`. Backups `_backup_{mcdonalds,bk,kfc}_pre_audit_2026_06_08`.
