# AUDITORIA IMAGENS FICTÍCIAS — 6 MERCADOS

Fase 2 do [PLAN_MERCADOS_2026-04-18](PLAN_MERCADOS_2026-04-18.md)
Gerado: 2026-04-18
Modo: read-only (Supabase MCP)
Ordem canónica: `ceo-ai` → `market-harvester` (spec) → **auditoria** (aqui) → limpeza (sessão dedicada)

---

## 1. SUMÁRIO EXECUTIVO

**5 em 6 mercados têm imagens fictícias em grande escala.** Mercadona é o único mercado limpo.

| Mercado            | Total | Contaminadas (`dup≥50 + badges`) | % contaminada | Tipo predominante |
|--------------------|------:|---------------------------------:|--------------:|-------------------|
| mercadona-guarda   | 5.011 |    0                             | 0 %           | —                 |
| continente-guarda  | 4.832 | 1.440 badges + 589 cross-mercadona + 290 dup_internal = **2.319** | **48 %** | Badges PVPR/Superprice do próprio Continente |
| pingodoce-guarda   | 3.101 | 586 badges + 1.037 cross-continente + 757 cross-mercadona = **2.380** | **77 %** | Fotos copiadas de Continente + Mercadona |
| lidl-guarda        | 3.002 | 731 badges + 1.285 cross-continente + 470 cross-mercadona = **2.486** | **83 %** | Fotos copiadas de Continente + Mercadona |
| auchan-guarda      | 3.003 | 557 badges + 967 cross-continente + 816 cross-mercadona = **2.340** | **78 %** | Fotos copiadas de Continente + Mercadona |
| intermarche-guarda | 3.004 | 571 badges + 965 cross-continente + 811 cross-mercadona = **2.347** | **78 %** | Fotos copiadas de Continente + Mercadona |

Total de linhas suspeitas nos 5 mercados: **≈ 11.872** (contagem conservadora apenas com duplicação ≥ 5 ou badges).

---

## 2. PADRÕES DETECTADOS

### Padrão A — **Badges como foto de produto** (certeza 100 %)
O scraper do Continente capturou imagens de badges ("PVPR", "Superprice") em vez das fotos dos produtos. Essas URLs aparecem em 5 mercados.

URLs fictícias confirmadas (apagar de toda a DB):

```
https://www.continente.pt/dw/image/v2/BDVS_PRD/on/demandware.static/-/Sites-continente-Library/default/dw3ccef5e3/images/badges/pvpr/col/pvpr.png?sw=112&sh=88&sm=fit
https://www.continente.pt/dw/image/v2/BDVS_PRD/on/demandware.static/-/Sites-continente-Library/default/dwbf737c26/images/badges/superprice/col/superprice.png?sw=112&sh=88&sm=fit
```

Impacto:
- Continente: 1.438 linhas (1.226 pvpr + 213 superprice)
- Lidl: 731 linhas (664 + 67)
- Pingo Doce: 586 linhas (525 + 61)
- Intermarché: 572 linhas (512 + 60)
- Auchan: 559 linhas (497 + 62)
- **Total: 3.886 linhas com badge como foto**

Sinal técnico universal: URL contém `/badges/` ou `sw=112` combinado com `sh=88`.

### Padrão B — **Fotos do Continente copiadas para 4 outros mercados** (267 URLs distintas, ~4.254 linhas)
Exemplos (aparecem em 4 mercados simultaneamente com contagens quase idênticas — sinal de scraper que falhou e reusou as mesmas imagens):
```
.../5127455-topshot.jpg  (Auchan 101, Intermarché 99, Pingo Doce 100, Lidl 66)
.../4099241-hero.jpg     (Auchan 70,  Intermarché 70, Pingo Doce 72)
.../7122561-frente.jpg   (Auchan 62,  Intermarché 60, Pingo Doce 61, Lidl 60)
```

**Interpretação BR §27.2 revista:** só é fictícia se o match `(nome_normalizado, marca, unidade)` falhar. Uma foto Continente de Coca-Cola 1.5L **pode** ser legítima se o produto correspondente também for Coca-Cola 1.5L. A limpeza definitiva precisa do `market-harvester` com step de match.

**Acção sugerida:** tratar como "suspeita" — não apagar cegamente. Passar pelo match canónico antes de decidir.

### Padrão C — **Fotos da Mercadona copiadas para 5 mercados** (~230 URLs distintas, ~3.232 linhas)
Mesma lógica do padrão B aplicada ao CDN `prod-mercadona.imgix.net`. Requer match antes de decidir.

### Padrão D — **Duplicação interna Continente** (33 URLs × 5+ reps = 290 linhas)
URLs Continente repetidas no próprio Continente em 5+ linhas sugerem fotos "pai" reaproveitadas para variantes (possivelmente legítimo) ou defaults (fictício). Requer inspecção manual.

---

## 3. COMPORTAMENTO POR FOSSA

| Métrica                          | Mercadona | Continente | Pingo Doce | Lidl  | Auchan | Intermarché |
|----------------------------------|----------:|-----------:|-----------:|------:|-------:|------------:|
| `small_thumbs` (sw=112/sh=88)    | 0         | 1.438      | 586        | 731   | 559    | 572         |
| `badges_total`                   | 0         | 1.440      | 586        | 731   | 559    | 572         |
| `cross_continente`               | 0         | —          | 1.394      | 1.593 | 1.316  | 1.311       |
| `cross_mercadona`                | —         | 589        | 1.062      | 674   | 1.121  | 1.114       |

A quase-igualdade entre `small_thumbs` e `badges_total` confirma que **praticamente todos os thumbnails 112×88 são badges** (não fotos reais de produto).

---

## 4. RECOMENDAÇÕES PARA FASE 3 (limpeza, sessão dedicada)

Em ordem de prioridade e certeza:

### Acção 1 — **Apagar badges imediatamente** (sem risco)
```sql
UPDATE products
SET photo_url = NULL
WHERE photo_url ILIKE '%/badges/%' OR photo_url ILIKE '%sw=112%' AND photo_url ILIKE '%sh=88%';
```
Impacto estimado: **3.886 linhas** → marcadas como `needs_photo = true` (campo a adicionar).

### Acção 2 — **Apagar URLs com 50+ reps no mesmo mercado** (quase certeza de fictício)
```sql
WITH bad AS (
  SELECT restaurant_id, photo_url FROM products
  WHERE restaurant_id IN ('continente-guarda','pingodoce-guarda','lidl-guarda','auchan-guarda','intermarche-guarda')
    AND photo_url IS NOT NULL
  GROUP BY restaurant_id, photo_url
  HAVING COUNT(*) >= 50
)
UPDATE products p SET photo_url = NULL
FROM bad WHERE p.restaurant_id = bad.restaurant_id AND p.photo_url = bad.photo_url;
```
Impacto estimado: ≈ 5.367 linhas adicionais.

### Acção 3 — **Cross-leak com match** (requer `market-harvester`)
Para `cross_continente` e `cross_mercadona` com 2–49 reps: correr match `(nome_normalizado, marca, unidade)` contra a fonte original. Se match falhar → apagar. Caso contrário → manter como L2 legítimo.

### Acção 4 — **Adicionar colunas** (migration, sessão dedicada)
```sql
ALTER TABLE products ADD COLUMN needs_photo boolean DEFAULT false;
ALTER TABLE products ADD COLUMN photo_source text; -- 'L1','L2','L3','L4_bing','L4_google'
```

---

## 5. RISCO E REVERSIBILIDADE

- Acção 1: **irreversível sem backup**. Pré-requisito: snapshot `pg_dump` da tabela `products` antes de executar.
- Acção 2: **irreversível sem backup**. Pré-requisito: mesmo snapshot.
- Acção 3: segura, só apaga o que falhar no match.
- Acção 4: reversível (`DROP COLUMN`).

**Todas as acções de escrita ficam para a sessão de Fase 3** — não executadas nesta sessão (restrição original da tarefa: "NÃO apagar produtos da DB").

---

## 6. ZONAS PROTEGIDAS BR §25.3

Nenhuma acção acima toca em: `pricing_service.dart`, `driver_capacity_service.dart`, `finalizePurchase`, triggers `bora_tokens`, Stripe ou `dispatch-engine`. ✅

---

## 7. PRÓXIMOS PASSOS

1. Sessão dedicada de **Fase 3 (limpeza)** com `guardian` antes de `executor`:
   - `pg_dump products` → backup.
   - Acções 1 + 2 + 4.
   - `system_validator` pós-limpeza.
2. Sessão de **Fase 4 (harvest)** um mercado de cada vez (Continente → Pingo Doce → Lidl → Auchan → Intermarché):
   - `market-scraper` para L1.
   - `market-harvester` para L2→L4.
   - Atingir 5.000 produtos (BR §27.2).
3. Sessão de **Fase 5 (automação)**:
   - Edge function `update-products`.
   - `pg_cron` semanal (BR §27.1).
   - Tabela `product_image_budget` + alertas.

---

*Gerado pelo `ceo-ai` + auditoria read-only via Supabase MCP. Nenhuma escrita executada.*
