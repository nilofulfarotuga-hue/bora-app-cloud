# Rebuild Intermarché-Guarda — EXECUTADO (Uber Eats) · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`.
> Rebuild feito com o cURL do Danilo. Sequência idêntica à Auchan (commit d690de3).

## 1. Estratégia vencedora: Uber Eats API
- `getStoreV1` → 44 sections (categorias) **durante horário da loja (09:00–19:30 PT)**.
- `getCatalogPresentationV2` (body `storeFilters{sectionUuids,sectionTypes:["COLLECTION"],shouldReturnSegmentedControlData}` + `pagingInfo`) → produtos por secção, paginado.
- Item: `{uuid, title, price (cêntimos), imageUrl}`. Loja `a0fe1ff9-…`. Localização: place_id Google + headers `x-uber-target-location-*`. Header overflow: `maxHeaderSize`.
- Scripts: `uber_eats_intermarche_crawler.js` + `uber_apply_rebuild.js`.

## 2. Sequência executada
1. **Crawl** → 5.824 produtos, 42 categorias, 0 sem foto/preço, 2 imagens-placeholder rejeitadas.
2. **Backup** `_backup_intermarche_pre_rebuild_2026_06_06` (3.004 linhas) ✅.
3. **DELETE** `intermarche-guarda` → 0 ✅.
4. **INSERT** (upsert PostgREST, lotes 200) → **5.824 ok, 0 falhas**.

## 3. Métricas antes/depois (MCP)
| Métrica | Antes | Depois |
|---|---|---|
| Total | 3.004 | **5.824** |
| Ativos | 2.962 | **5.824** |
| Sem foto | 1.864 (62%) | **19** (placeholders rejeitados; 99,7% com foto) |
| Sem preço | 0 | **0** |
| Categorias | 13 | **42** (= sections Uber) |
| sort_order | — | 100% (ordem das sections Uber) |
| Preço min/máx | — | €0,25 / €71,39 |

## 4. 5 produtos sample
| Nome | Preço | Categoria |
|---|---|---|
| PorSi - Pão de Forma com Côdea, 820g | €1,75 | Mais vendidos |
| Banana | €1,39 | Mais vendidos |
| Frango Inteiro Grande | €2,89 | Mais vendidos |
| Perna de Frango com Costa | €2,29 | Mais vendidos |
| Gira - Óleo alimentar, garrafa de 1 l | €1,79 | Mais vendidos |

## 5. Categorias (ordem Uber)
Mais vendidos, Produtos em alta, Sobremesas, Charcutaria, Casa e Estilo de vida, Álcool, Bebidas sem álcool, Frutas e Legumes, … (42 no total, via `sort_order`).

## 6. ⚠️ Conhecido: 483 nomes (8%) com `�` — fix queued
A API Uber devolve texto **double-encoded em CP1252** (bug de locale). A recuperação byte-a-byte funciona, MAS os 2 primeiros crawls guardaram o JSON via `toString('utf8')`, que **dropou** os bytes de alguns acentos minúsculos (í, ç) antes de eu os recuperar → 483 nomes ficaram com `�` (ex.: "L�quido"=Líquido, "Alian�a"=Aliança). Preços/fotos/categorias **não afetados**.
- **Crawler já CORRIGIDO** nesta sessão: `recoverMojibake()` faz recuperação ao nível do byte do Buffer raw (lone 0x81→Á, [C3 83 C2 AD]→í, etc.). Validado na lógica.
- **A loja fechou** (>19:30 PT) a meio → não deu para re-crawl limpo agora.
- **FIX (5 min, durante 09:00–19:30 PT):** `node scripts/uber_eats_intermarche_crawler.js --out u.json` → `node scripts/uber_apply_rebuild.js u.json intermarche-guarda` (upsert UPDATE, sem DELETE) → nomes 100% limpos.

## 7. ⚠️ Regra de preço — a confirmar
Gravado **preço Uber direto (cêntimos/100, SEM −15%)** conforme decisão revista do Danilo. Sinal de alerta: Uber "Mimosa M/Gordo 1L" = €1,15 vs Glovo Auchan €1,00 (~15% acima) — **pode indicar markup Uber** (lojas diferentes, inconclusivo). Se confirmar markup, aplicar ×0,85 (bulk UPDATE simples; reversível).

## 8. Reversão
`DELETE … ; INSERT … SELECT * FROM _backup_intermarche_pre_rebuild_2026_06_06;` (via MCP).

## 9. Zonas protegidas
Intactas. Só `products` de `intermarche-guarda` + backup. Sem toques em dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger.
