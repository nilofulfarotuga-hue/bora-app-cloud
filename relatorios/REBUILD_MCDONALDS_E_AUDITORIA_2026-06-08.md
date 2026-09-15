# McDonald's REBUILD + AUDITORIA BK/KFC (Guarda)

**Data:** 2026-06-08 · **Branch:** autonomous-night-2026-04-29 · **Fonte:** Glovo Guarda
**Preço:** `preço_DB = ROUND(preço_glovo / 1.15, 2)` → cliente Bora paga exactamente o Glovo (non-partner +15% runtime).

---

## ✅ ESTADO FINAL — 4 fast-food de Guarda

| Restaurante | Antes | **Depois** | Cats | sem_foto | sem_preço | com_sort | Médio (€) | Estado |
|---|---:|---:|---:|:--:|:--:|---:|---:|---|
| **KFC** | 176 | **176** | 16 | 0 | 0 | 176 | 8.12 | ✅ auditado, 0 drift |
| **Burger King** | 160 | **169** | 11 | 0 | 0 | 169 | 6.84 | ✅ re-rebuilt (drift +15) |
| **McDonald's** | 119 | **98** | 9 | 0 | 0 | 98 | 5.16 | ✅ rebuilt (estava fechado) |
| **Pizza Hut** | 78 | **78** | 9 | 0 | 0 | **0** | 9.58 | 🚫 OCULTO — intacto |

`com_sort=0` no Pizza Hut **prova que não foi tocado** (os rebuilds definem sort_order; PH não tem). `is_online=false`+`is_active_admin=false` confirmados.

---

## SECÇÃO 1 — AUDITORIA BK + KFC (drift desde a sessão anterior)

Método: re-harvest do Glovo (`.ai_rest_harvest.js`) → comparação id-a-id vs DB (`.ai_rest_audit.js`): novos / removidos / preço-diff.

### KFC — `kfc-guarda` ✅ PERFEITO (0 drift)
- **Glovo agora: 176 · DB: 176 · novos: 0 · removidos: 0 · preço-diff: 0**
- Decisão: **aceitar, NÃO re-rebuild**. 100% idêntico ao Glovo.

### Burger King — `burgerking-guarda` ✅ RE-REBUILT
- **Glovo agora: 169 · DB: 160 · novos: 12 · removidos: 3 · preço-diff: 0** → diff total **15** (>5, ≤20) → **re-rebuild** (regra A4).
- **Drift legítimo:** BK lançou a linha **Long Chicken** e retirou o **Big King**.
  - **+12 novos (Long Chicken):** Menu Long Chicken (+Anéis Cebola) · Long Chicken® / Spicy / Tuga / Tuga c/ Chouriço · Menu Completo Long Chicken · Long Vegetal / Menú Vegetal Spicy (em Frango e outros, Hambúrgueres, Vegetal, Menus Completos)
  - **−3 removidos:** Menu Big King® · Big King® Frango Menu · Big King®
- Re-build: backup `_backup_bk_pre_reaudit_2026_06_08` (160) → DELETE+INSERT **169** (÷1.15). Categorias e ordem inalteradas (11 secções).

---

## SECÇÃO 2 — McDonald's `mcdonalds-guarda` ✅ REBUILD COMPLETO

### Investigação "Glovo permite agendar loja fechada?"
Na sessão anterior a loja estava `open:false` e o content devolvia banner *"Não há lista de produtos…"*. **Nesta sessão a loja estava ABERTA** (`open:true`) → catálogo servido normalmente, **fallback não foi necessário**.
- **Resposta à pergunta do Danilo:** quando a loja está **fechada**, o Glovo **NÃO** serve o catálogo via API (`?scheduled=true` e `/v4/main` também vazios — testado na sessão anterior). O "agendar" do Glovo só aparece no cliente **com a loja a aceitar pré-encomendas**; para estas lojas fast-food o catálogo só está acessível **em horário aberto**. **Solução prática: crawlar em horário de funcionamento** (foi o que aconteceu agora).

### Fonte e descoberta
- **Glovo Guarda** · slug **`mcdonalds-grd`** · store **215649** / addr **346436** (loja real de Guarda — ids ficam de Guarda, não há problema de cidade).
- **Categorias top descobertas (12):** Mais vendidos · Novidades · Europoupança · Sanduíches e McMenu · Happy Meal · Saco de Transporte · Sobremesas · Saladas, Veggies & outros mais · Acompanhamentos e molhos · Bebidas · Sanduiche individual · Items Individuais
- **Excluídas (3):** `Mais vendidos` (best-sellers) · `Novidades` (novidades) · `Europoupança` (promo poupança)
- **9 secções estruturais mantidas.**

### Métricas
- 119 (caótico) → **98** · sem_foto 0 · sem_preço 0 · 9 cats · com_sort 98 · €0,09–13,22 · médio €5,16
- backup `_backup_mcdonalds_pre_rebuild_2026_06_08` (119) ✓ (criado na sessão anterior; lição backup respeitada)
- **byRoot:** Sanduíches e McMenu 22 · Items Individuais 18 · Sobremesas 14 · Bebidas 13 · Acompanhamentos e molhos 10 · Saladas/Veggies 8 · Sanduiche individual 7 · Happy Meal 5 · Saco de Transporte 1
- 1ª categoria = 22% (< 80%) — sem absorção de carrossel.

### Sample (glovo → ÷1.15 = DB → ×1.15 = cliente)
- [McMenu] McMenu® Big Mac® — 7,90 → **6,87** → 7,90 ✓
- [Happy Meal] Happy Meal® Chicken McNuggets® — 6,10 → **5,30** → 6,10 ✓
- [Sobremesa] McFlurry® Daim e Caramelo — 3,90 → **3,39** → 3,90 ✓
- [Acompanhamento] 20 Chicken McNuggets® — 10,30 → **8,96** → 10,30 ✓
- [Bebida] Lipton Pêssego Zero Pequeno — 2,10 → **1,83** → 2,10 ✓

### ⚠️ Nota: SEM Pequeno-Almoço (limitação horária do Glovo)
O Glovo McD **só expõe a secção Pequeno-Almoço/McMorning durante o horário de breakfast** (~06h–10h30). À hora do crawl (loja aberta, fora do breakfast) essa secção **não existe no menu Glovo** → não foi possível capturar. **Follow-up:** re-harvest de manhã (06h–10h) para acrescentar o breakfast. Os 98 produtos = menu Glovo actual completo (sem breakfast time-gated). 119→98 = substituição de catálogo caótico antigo (duplicados/stale) pelo catálogo exacto do Glovo.

### Limpeza
Categoria `"Bebidas "` do Glovo tinha espaço final → `.ai_4lojas_apply.js` agora faz `.trim()` no category_root/category (também protege KFC/BK em futuras corridas).

---

## SECÇÃO 3 — CONSOLIDADO

| | Estado |
|---|---|
| **KFC** | ✅ 176 — auditado, 0 drift, igual ao Glovo |
| **Burger King** | ✅ 169 — re-rebuilt c/ linha Long Chicken |
| **McDonald's** | ✅ 98 — rebuilt do Glovo (breakfast pendente AM) |
| **Pizza Hut** | 🚫 78 — oculto (`is_online=false`/`is_active_admin=false`), **intacto** |

**Os 4 fast-food de Guarda estão fiéis ao Glovo.** Único follow-up: re-harvest matinal do McD para o Pequeno-Almoço.

## 🛡️ Zonas protegidas
`pizzahut-guarda` não tocado (com_sort=0 prova). Parceiros/testes intactos. `pricing_calculate`/markup só lidos. Dispatch/triggers/Stripe/RLS/tokens intactos. Mutação só em `products` non-partner (BK, McD).

## 🧰 Artefactos
`.ai_rest_audit.js` (comparador novo) · `.ai_mcd_names.json` · `.ai_mcd_harvest.json` · `.ai_bk_audit.json` (=novo BK) · `.ai_kfc_audit.json` · `.ai_4lojas_apply.js` (+`.trim()`). Backups `_backup_bk_pre_reaudit_2026_06_08`(160) · `_backup_mcdonalds_pre_rebuild_2026_06_08`(119).
