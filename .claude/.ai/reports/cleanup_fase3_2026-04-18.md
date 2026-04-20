# RELATÓRIO FASE 3 — LIMPEZA DB IMAGENS FICTÍCIAS

Executado: 2026-04-18
Orquestrador: `ceo-ai`
Status: ✅ **Fase 3 concluída**
Âmbito: `restaurant_id IN (mercadona, continente, pingodoce, lidl, auchan, intermarche)-guarda`

---

## 1. OPERAÇÕES EXECUTADAS (ordem cronológica)

| # | Operação | Rows afectadas | Método |
|---|---|---:|---|
| 1 | Backup completo `products` → `products_backup_2026_04_18` | 22.264 | `CREATE TABLE AS TABLE` |
| 2 | `ALTER TABLE products ADD COLUMN image_source text` | — | DDL |
| 3 | `ALTER TABLE products ADD COLUMN needs_photo boolean DEFAULT false` | — | DDL |
| 4 | Marcar Mercadona L1 (fonte canónica) | 5.011 | UPDATE |
| 5 | Marcar Continente L1 (URLs do próprio CDN) | 2.803 | UPDATE |
| 6 | Apagar badges pvpr/superprice/thumbs 112×88 | **3.888** | UPDATE photo_url = NULL |
| 7 | Match L2 canónico (nome normalizado + URL) | 16 | UPDATE image_source = 'L2_*' |
| 8 | Limpar cross-leaks Mercadona/Continente sem match | 10.158 | UPDATE photo_url = NULL |
| 9 | Marcar Pingo Doce L1 (próprio CDN) | 59 | UPDATE |
| 10 | Match L2_pingodoce | 5 | UPDATE |
| 11 | Limpar cross-leaks Pingo Doce sem match | 18 | UPDATE photo_url = NULL |

**Total photo_url limpos (cleared)**: **14.064** (3.888 badges + 10.176 mismatches).
**Total image_source classificado**: 21.953 / 22.264 (99,9 %).

---

## 2. ANTES vs DEPOIS

### Antes (estado pré-limpeza)

| Mercado            | Total  | Com foto | Fotos únicas |
|--------------------|-------:|---------:|-------------:|
| mercadona-guarda   | 5.011  | 5.011    | 3.805        |
| continente-guarda  | 4.832  | 4.832    | 2.519        |
| pingodoce-guarda   | 3.101  | 3.101    | 558          |
| lidl-guarda        | 3.002  | 3.002    | 406          |
| auchan-guarda      | 3.003  | 3.003    | 505          |
| intermarche-guarda | 3.004  | 3.004    | 504          |
| **TOTAL 6 mercados** | **21.953** | **21.953** | 8.297 |

### Depois (pós-Fase 3)

| Mercado            | Total  | Com foto | L1    | L2  | `needs_photo` |
|--------------------|-------:|---------:|------:|----:|--------------:|
| mercadona-guarda   | 5.011  | 5.011    | 5.011 | 0   | 0             |
| continente-guarda  | 4.832  | 2.804    | 2.803 | 1   | 2.028         |
| pingodoce-guarda   | 3.101  | 64       | 59    | 5   | 3.037         |
| lidl-guarda        | 3.002  | 0        | 0     | 0   | 3.002         |
| auchan-guarda      | 3.003  | 5        | 0     | 5   | 2.998         |
| intermarche-guarda | 3.004  | 5        | 0     | 5   | 2.999         |
| **TOTAL 6 mercados** | **21.953** | **7.889** | **7.873** | **16** | **14.064** |

### Delta

- Fotos válidas: 21.953 → **7.889** (-64 %)
- Fotos fictícias removidas: **14.064** (100 % marcadas `needs_photo = true`)
- Zero rows apagadas (apenas `photo_url = NULL`)
- Match L2 legítimos detectados: apenas **16** (confirma que cross-leaks eram massivamente fictícios)

---

## 3. SEMÂNTICA DO `image_source`

| Valor | Significado |
|---|---|
| `L1` | Foto do CDN do próprio mercado, com nome do produto coerente |
| `L2_mercadona` / `L2_continente` / `L2_pingodoce` | Foto partilhada legitimamente (match canónico por `(nome_normalizado, photo_url)`) |
| `cleared_badge` | Foto era badge PVPR/Superprice (thumbnail 112×88) — apagada |
| `cleared_cross_mismatch` | Foto era cross-leak de outro mercado mas o nome do produto não bate — apagada |
| NULL | Linha sem foto antes da limpeza ou não processada (311 linhas = restaurantes/fast-food, fora do âmbito) |

---

## 4. SANITY CHECKS

| Check | Esperado | Actual | Status |
|---|---|---|---|
| Backup rows == pre-clean rows | 22.264 | 22.264 | ✅ |
| Rows apagadas permanentemente | 0 | 0 | ✅ |
| Badges restantes | 0 | 0 | ✅ |
| Fotos não classificadas (mercados-alvo) | 0 | 0 | ✅ |
| `needs_photo = true` | = fotos cleared | 14.064 | ✅ |
| Preços afectados | 0 | 0 (mantém 2 sem preço Mercadona pré-existentes) | ✅ |

---

## 5. ZONAS PROTEGIDAS BR §25.3 — INTACTAS

- `lib/services/pricing_service.dart` — não tocado
- `lib/dispatch/driver_capacity_service.dart` — não tocado
- `lib/stores/order_store.dart::finalizePurchase` — não tocado
- Triggers `bora_tokens`, `trg_award_tokens_on_delivery` — não tocados
- Stripe payment code — não tocado
- `supabase/functions/dispatch-engine/index.ts` — não tocado

Apenas `public.products` foi mutada + backup em `public.products_backup_2026_04_18`.

---

## 6. ROLLBACK

Em caso de necessidade:

```sql
BEGIN;
TRUNCATE products;
INSERT INTO products SELECT * FROM products_backup_2026_04_18;
ALTER TABLE products DROP COLUMN IF EXISTS image_source;
ALTER TABLE products DROP COLUMN IF EXISTS needs_photo;
COMMIT;
```

Ficheiros/memória que sobreviveriam ao rollback:
- `.claude/.ai/reports/cleanup_fase3_2026-04-18.md` (este relatório)
- `.claude/.ai/business_rules.md` (§27 actualizado)
- `.claude/.ai/skills/market-harvester.md`

---

## 7. PRÓXIMOS PASSOS (Fase 4 — sessão dedicada)

1. Por cada mercado (ordem canónica BR §27.1 Seg→Sáb):
   - `market-scraper` corre L1 sobre `needs_photo = true`.
   - `market-harvester` aplica L2 → L3 → L4 (Bing → Google CSE).
   - Orçamento L4 observado (€50/mês tecto).
   - Objectivo: atingir ≥ 5.000 produtos com foto por mercado (BR §27.2).
2. Fase 5: Edge function `update-products` + pg_cron (sessão dedicada).

---

*Gerado automaticamente pelo `ceo-ai` após execução autónoma de Fase 3. Backup preservado. 0 rows perdidas.*
