---
name: market-data-sync
description: >
  Skill universal para sincronizar catálogo de produtos de qualquer loja
  (supermercados, farmácias, restaurantes) para a base de dados Bora.
  Recebe nome da loja + restaurant_id + fonte (Glovo / Uber Eats / manual),
  extrai produtos + imagens da fonte (SEM preço), e busca o preço real no
  site oficial da loja via extensão Chrome. UPDATE se produto já existe
  (lookup por name normalizado), INSERT se novo (com needs_review=true e
  is_available=false até ter preço). ZERO duplicados garantidos por
  normalização (lowercase + trim + sem acentos). Triggers:
  "sincronizar produtos do Continente Guarda", "importar Glovo Continente",
  "buscar preços do Pingo Doce", "sync Uber Eats Mercadona",
  "actualizar catálogo da loja X", "market-data-sync".
metadata:
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Market Data Sync — Skill Universal

## Propósito

Sincronizar o catálogo de produtos de **qualquer loja** (supermercado, farmácia, restaurante) para a tabela `products` da BD Bora, sem duplicados e sem perder histórico de preços.

**Funciona para qualquer loja** — basta indicar nome + `restaurant_id` + fonte.

---

## Inputs Obrigatórios

| Campo | Tipo | Exemplo |
|-------|------|---------|
| `store_name` | string | "Continente Guarda" |
| `restaurant_id` | uuid | `8f3a...` (existe em `restaurants`) |
| `source` | enum | `glovo` \| `uber_eats` \| `manual` |
| `source_store_id` | string | `continente-grd1` (slug Glovo) ou URL Uber |
| `price_source` | enum | `continente` \| `pingo_doce` \| `auchan` \| `mercadona` \| `lidl` \| `intermarche` \| `manual` |

Lojas e fontes suportadas → ver [references/lojas.md](references/lojas.md).

---

## Fluxo de Execução (5 fases)

### Fase 0 — Validação
1. Confirmar `restaurant_id` existe na BD (SELECT 1 FROM restaurants).
2. Confirmar `store_name` corresponde ao `restaurant_id` (avisar se diferente).
3. Verificar `price_source` está em `lojas.md` (caso contrário, abortar).
4. Backup do catálogo actual:
   ```sql
   CREATE TABLE products_backup_<store>_<YYYYMMDD>
   AS SELECT * FROM products WHERE restaurant_id = '<id>';
   ```
5. STOP → pedir aprovação ao Danilo (MODO PROTECÇÃO TOTAL).

### Fase 1 — Extracção da Fonte (Glovo / Uber Eats)
- Scraping via Playwright/Puppeteer com **rate limit 4,5s ± jitter** (ver `regras.md`).
- Extrair por produto: `name`, `image_url`, `category_glovo`, `description` (opcional).
- **NÃO extrair preço da fonte** — preços de Glovo/Uber são inflacionados (taxa 30-40%).
- Output: `tmp/extracted_<store>_<YYYYMMDD>.json` (não commitado).
- Checkpoint a cada 200 produtos.

### Fase 2 — Normalização & Lookup
Para cada produto extraído:
1. Normalizar nome:
   ```
   norm(name) = lowercase(strip_accents(trim(name)))
   ```
2. Mapear `category_glovo` → categoria canónica Bora (22 secções, ver `regras.md`).
3. Lookup na BD:
   ```sql
   SELECT id FROM products
   WHERE restaurant_id = '<id>'
     AND lower(unaccent(trim(name))) = '<norm_name>'
   LIMIT 1;
   ```
4. **Name-guard ≥ 0.3** — se Levenshtein normalizado > 0.3 com candidato, tratar como novo (não fazer match agressivo).

### Fase 3 — Busca de Preço Real (site oficial)
- Para cada produto:
  - Procurar no site da loja (continente.pt, pingodoce.pt, etc.) usando o método confirmado em `lojas.md`.
  - Continente: método **M3 confirmado** (search API + extracção via extensão Chrome).
  - Rate limit: 4,5s ± jitter.
  - Se não encontrar: marcar `price_lookup_failed = true` no JSON intermédio.
- Output: `tmp/priced_<store>_<YYYYMMDD>.json`.

### Fase 4 — Aprovação Manual
1. Gerar relatório resumo:
   - Total extraídos
   - Total com match (UPDATE)
   - Total novos (INSERT, `needs_review=true`)
   - Total sem preço (`is_available=false`)
   - Diff de preços (% médio, top 10 maiores variações)
2. Salvar em `.claude/.ai/reports/market-data-sync-<store>-<YYYYMMDD>.md`.
3. STOP → aguardar aprovação explícita do Danilo.

### Fase 5 — Aplicar à BD
- **UPDATE** se produto existe:
  ```sql
  UPDATE products SET
    image_url = COALESCE(NULLIF(image_url, ''), '<new_image>'),
    price_cents = <new_price>,
    last_synced_at = now(),
    sync_source = '<source>'
  WHERE id = '<existing_id>';
  ```
- **INSERT** se novo:
  ```sql
  INSERT INTO products (restaurant_id, name, image_url, taxonomy_section,
                        needs_review, is_available, sync_source, created_at)
  VALUES ('<id>', '<name>', '<image>', '<canonical>', true, false, '<source>', now());
  ```
- Soft-delete só se Danilo aprovar explicitamente um produto removido.

---

## Regras de Ouro

1. **ZERO duplicados** — lookup sempre por nome normalizado.
2. **ZERO preços inflacionados** — preço SEMPRE do site oficial, nunca de Glovo/Uber.
3. **Backup obrigatório** antes de qualquer UPDATE/INSERT.
4. **Rate limit 4,5s ± jitter** em qualquer scraping.
5. **Aprovação explícita** do Danilo entre Fase 0 → 1 e Fase 4 → 5.
6. **Checkpoint a cada 200 produtos** — se cair, retoma do último.
7. **Novos produtos** = `needs_review=true` + `is_available=false` até ter preço.
8. **Categorias canónicas** = 22 secções fixas (ver `regras.md`).

---

## O Que Esta Skill NÃO Faz

- NÃO toca em ficheiros `.dart`.
- NÃO faz `DELETE` físico (só soft-delete via `is_active=false` e só com aprovação).
- NÃO usa preços de Glovo/Uber Eats como fonte de preço final.
- NÃO faz deploy de Edge Functions.
- NÃO modifica esquema da BD (nem migrations).

---

## Ficheiros Relacionados

- [references/lojas.md](references/lojas.md) — lista de lojas + fontes suportadas
- [references/regras.md](references/regras.md) — rate limits, name-guard, 22 categorias canónicas
- [scripts/sync_template.js](scripts/sync_template.js) — template Node.js reutilizável

---

## Triggers (auto-invocação)

- "sincronizar produtos do <loja>"
- "importar Glovo <loja>"
- "importar Uber Eats <loja>"
- "buscar preços do <loja>"
- "actualizar catálogo da <loja>"
- "market-data-sync"
- "sync de produtos"

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
