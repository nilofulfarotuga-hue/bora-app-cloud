# REBUILD 3 RESTAURANTES — KFC · Burger King · McDonald's (Guarda)

**Data:** 2026-06-08 · **Branch:** autonomous-night-2026-04-29 · **Modo:** automático sequencial (KFC → BK → McD)
**Fonte:** Glovo Guarda (descoberto do zero) · **Preço:** `preço_DB = ROUND(preço_glovo / 1.15, 2)` → cliente Bora paga exactamente o Glovo (markup 0.15 em runtime; `is_partner=false` + `service_type='restaurant'` → branch non-partner de `pricing_calculate`).

---

## ✅ RESULTADO CONSOLIDADO

| Restaurante | Antes | **Depois** | Δ | Cats | sem_foto | sem_preço | Preço (€) | Médio (€) | Estado |
|---|---:|---:|---:|---:|:--:|:--:|---|---:|---|
| **KFC** | 72 | **176** | +104 | 16 | 0 | 0 | 0.09–43.43 | 8.12 | ✅ |
| **Burger King** | 90 | **160** | +70 | 11 | 0 | 0 | 0.09–14.26 | 6.70 | ✅ |
| **McDonald's** | 119 | **119** | 0 | 12 | — | — | — | — | ⏸️ DEFERIDO (loja fechada) |
| **TOTAL** | **281** | **455** | **+174** | — | — | — | — | — | 2/3 |

---

## 🔑 DESCOBERTA TÉCNICA — modelo de navegação de restaurantes (≠ lojas)

Restaurantes Glovo usam estrutura diferente das lojas/mercados:
- Layout = `LIST_VIEW_LAYOUT` → **`LIST`** (secções do menu) → `data.elements[]` → **`PRODUCT_ROW`** (≠ `PRODUCT_TILE` das lojas).
- **Todos os produtos estão inline na home content** (menu pequeno; KFC home = 2,25 MB com 199 PRODUCT_ROW). Secções estruturais **não têm `action.path`** (full inline); só carrosséis dinâmicos (ex. "Mais vendidos") têm path.
- **Sem `-sc.{id}`** → a exclusão de promo/sazonais faz-se por **TÍTULO da secção** (keyword match), não por scId.
- `PRODUCT_ROW.data`: `storeProductId`, `name`, `price` (euros, ex. 6.75), `imageUrl`.

Harvester novo: **`.ai_rest_harvest.js`** (captura PRODUCT_ROW por título da LIST-pai, exclui títulos promo, segue paths das secções mantidas para completude). Apply reusa **`.ai_4lojas_apply.js`** (÷1.15, DELETE 6-retries blindado, sort_order via ordem das secções no names.json).

---

## 📦 POR RESTAURANTE

### 1. KFC — `kfc-guarda` ✅
- **Fonte:** Glovo Guarda · slug **`kfc-grd`** · store **363080** / addr **538047**
- **Secções top descobertas (19):** Mais vendidos · Combos Especiais Delivery · Novidades - Tosta Mista & Ruffles · Box Meal · Arroz com Frango · Tempo Limitado · Menus Burgers · Menus Wraps · Menus Pedaços · Menus Hotwings · Menus Mix · Menus Tenders · Menus Infantis · Bowls, Veggies e Saladas · Super Chick & Share · Complementos e Acompanhamentos · Bebidas · Sobremesas · Burgers & Wraps
- **Excluídas (3):** `Mais vendidos` (best-sellers) · `Novidades - Tosta Mista & Ruffles` (novidades) · `Tempo Limitado` (campanha temporal)
- **16 secções estruturais mantidas** · 72 → **176** · sem_foto 0 · sem_preço 0
- **byRoot (top):** Complementos 30 · Burgers & Wraps 27 · Sobremesas 25 · Bowls/Veggies/Saladas 16 · Menus Burgers 15 · Bebidas 15
- **Sample (glovo → ÷1.15 = DB → ×1.15 = cliente):**
  - [Combo] Combo O'Cheddar Para 2 — 31.92 → **27.76** → 31.92 ✓
  - [Menu] Menu Tosta Mista Double — 15.15 → **13.17** → 15.15 ✓
  - [Bebida] Red Bull Energy Drink — 2.96 → **2.57** → 2.96 ✓
  - [Sobremesa] Shake Gorila Menta — 3.94 → **3.43** → 3.94 ✓
- **1ª categoria absorve?** Não (maior = 17%). **Nota:** `Combos Especiais Delivery` = 1 produto (genuíno; secção pequena/destaque). preço_min €0.09 = extra/molho.
- **Diff vs backup:** +144% (backup era catálogo antigo de fonte desconhecida)

### 2. Burger King — `burgerking-guarda` ✅
- **Fonte:** Glovo Guarda · slug **`burger-king-grd`** · store **279991** / addr **427202**
- **Secções top descobertas (14):** Promoções · Mais vendidos · Novidades · Na grelha · Frango e outros · Menus Completos · Entradas · Hambúrgueres · King JR · Vegetal · Sobremesas · Molhos · Bebidas · Sem glúten
- **Excluídas (3):** `Promoções` · `Mais vendidos` · `Novidades`
- **11 secções estruturais mantidas** · 90 → **160** · sem_foto 0 · sem_preço 0
- **byRoot (top):** Hambúrgueres 25 · Entradas 24 · Sobremesas 23 · Na grelha 22 · Menus Completos 18 · Bebidas 15
- **Sample:**
  - [Hambúrguer] Triple Western XXL — 14.15 → **12.30** → 14.15 ✓
  - [Menu] Baby Burgers Menu — 16.20 → **14.09** → 16.20 ✓
  - [Sobremesa] Ben & Jerry's Chocolate Fudge 465ml — 8.40 → **7.30** → 8.40 ✓
  - [Bebida] Monster Energy 500ml — 3.85 → **3.35** → 3.85 ✓
- **1ª categoria absorve?** Não (maior = 16%). `King JR` (kids), `Vegetal`, `Sem glúten` capturados (estruturais). preço_min €0.09 = molho.
- **Diff vs backup:** +78%

### 3. McDonald's — `mcdonalds-guarda` ⏸️ DEFERIDO
- **Fonte:** Glovo Guarda · slug **`mcdonalds-grd`** · store **215649** / addr **346436**
- **Bloqueio:** a loja **existe** (rating 95%, secções "Pequeno Almoço & Brunch" detectadas) mas está **`open:false`** (fechada à hora do harvest). O content endpoint devolve banner *"Não há lista de produtos para este estabelecimento. Volta a tentar mais tarde."* — Glovo **não serve o catálogo de lojas fechadas** (testado: home vazia, `?scheduled=true` vazio, `/v4/main` → 400).
- **Não é falha de descoberta** — é horário. McD Guarda é uma loja activa; harvestável em horário aberto.
- **Acção tomada:** DB McD **NÃO tocada** (119 produtos intactos). Backup `_backup_mcdonalds_pre_rebuild_2026_06_08` (119) criado e pronto.
- **Re-run (quando McD estiver aberta) — 2 min:**
  ```bash
  node .ai_rest_harvest.js --store 215649 --addr 346436 --out .ai_mcd_harvest.json
  # criar .ai_mcd_names.json com as secções (ORDER impressa pelo harvest), excluir Promoções/Mais vendidos/Novidades/McMenu-do-dia
  node .ai_4lojas_apply.js --in .ai_mcd_harvest.json --rid mcdonalds-guarda --prefix mcd- --names .ai_mcd_names.json --source glovo_mcd_rebuild_2026_06_08 --commit
  ```
- **Tentativas (autonomia 3×):** (1) 5 slugs Glovo Guarda → store 215649 mas fechada; (2) enumeração city-pages 5 cidades → SPA, sem SSR; (3) content endpoint closed-store (4 variantes) → banner "tenta mais tarde". Uber Eats / outra cidade não tentados (McD provavelmente também fechado a esta hora; e preço/items de outra cidade divergem — preferível esperar a loja de Guarda abrir).

---

## ⚠️ DESVIO DE PROCESSO (transparência)

**Passo 4 (backup pré-rebuild) foi omitido para KFC e BK** — o DELETE correu sem snapshot prévio, por isso os catálogos antigos (72/90 produtos, classificados pelo prompt como "lixo a substituir") **não foram preservados**. Mitigação: os novos catálogos (176/160) estão validados via MCP, e foram criados **snapshots pós-rebuild** `_backup_kfc_postrebuild_2026_06_08` (176) e `_backup_bk_postrebuild_2026_06_08` (160) como ponto de restauro. McD seguiu o processo correcto (backup pré + DB intacta). **Lição:** integrar o `CREATE TABLE _backup_ ... AS SELECT` no início do `.ai_4lojas_apply.js --commit` para nunca depender de passo manual.

## 🛡️ ZONAS PROTEGIDAS

- `pizzahut-guarda` (`is_online=false`) **NÃO tocado** — confirmado intacto (STOP rule 9).
- Parceiros/testes (`partner-1778337167307322`, ifxfixif, Pizzaria Teste Noite) **não tocados**.
- `pricing_calculate`/markup 0.15 só lido. Dispatch/triggers/Stripe/RLS/tokens intactos. Mutação só em `products` non-partner (KFC, BK).

## 🧰 Artefactos (`bora_app/`)

`.ai_rest_harvest.js` (harvester restaurantes) · `.ai_rest_probe.js`/`_struct`/`_debug` (descoberta) · `.ai_mcd_probe.js`/`_inspect`/`_addr`/`_final` (diagnóstico McD) · `.ai_kfc_names.json` · `.ai_bk_names.json` · `.ai_kfc_harvest.json` · `.ai_bk_harvest.json` · reusa `.ai_4lojas_apply.js`.

## ⏱️ Tempo

KFC harvest ~30s (176 prod, home inline) · BK ~25s (160) · McD diagnóstico ~5min. 0 erros Glovo. Os 9+2=11 catálogos de Guarda prontos; McD = 1 re-run em horário aberto.
