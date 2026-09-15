# Auditoria do Crawler Glovo Auchan — 2026-06-06

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · **read-only na DB** (zero UPDATE/INSERT/DELETE).
> Validado via `prompt-blindado-validator`. Branch `autonomous-night-2026-04-29`.

## Resposta directa às 4 perguntas

### 1. O crawler tinha bug? Qual?
**SIM — bug grave de cobertura.** Não era paginação por token. A árvore Glovo grocery tem **3 níveis**:
`categoria (sc.id) → subcategoria/leaf (c.id) → secções (s.id)`.

Num leaf, **só a 1ª secção vem inline** (GRID com PRODUCT_TILEs). As restantes secções vêm como **`CONTENT_PLACEHOLDER`** com um `data.contentUri` próprio:
`/v4/stores/124961/addresses/226966/content/partial?component=section&id={sectionId}`.

O crawler antigo seguia os `COLLECTION_TILE` (subcategorias) mas **ignorava os `CONTENT_PLACEHOLDER`** → apanhava apenas ~12 produtos da 1ª secção de cada leaf e perdia todas as outras secções. **Não havia erro nem 404** — falha silenciosa (por isso "0 erros, queue drenada a 0" mascarava o problema).

Outras hipóteses verificadas e **descartadas**:
- Paginação por `nextPageToken`/`cursor`/`offset`/`hasMore`: **inexistente** (procurado, 0 ocorrências).
- Tabs internas: as subcategorias **são** os `COLLECTION_TILE`, que já eram seguidos.
- Dedup agressiva: dedup por `storeProductId` está **correta** (ids únicos; variantes/tamanhos têm ids distintos).
- O "25 produtos por leaf" anterior estava inflado: eram **12 PRODUCT_TILE + 12 PERSEUS_EVENT** (eventos de tracking que também contêm `storeProductId`). A contagem real por `type==='PRODUCT_TILE'` é a correcta.

### 2. Quantos produtos a Glovo Auchan Guarda tem REALMENTE?
**6.245 produtos** (únicos, todos com foto real, preços €0,10–€55,99 — tudo de supermercado, 0 erros, queue drenada a 0). Crawl corrigido: **~512 fetches, 0 erros**.

O **1.953** anterior estava errado: faltavam **4.292 produtos (69%)**. A Auchan da Guarda **NÃO é uma loja pequena** — tem catálogo completo de supermercado.

### 3. Número novo após correcção
**6.245** (vs 1.953 antigo). Fix aplicado em `scripts/glovo_grocery_crawler.js`: seguir `CONTENT_PLACEHOLDER.data.contentUri` + `MAX` 2000→6000.

### 4. Recomendação para o Danilo
Comparação **read-only** do catálogo Glovo real (6.245) vs DB (`auchan-guarda`, 6.238 total / 4.186 ativos):

| Medida | Valor |
|---|---|
| Ativos DB que estão na Glovo (por id) | 687 (16,4%) |
| ... + por nome | 770 (18,4%) |
| Sem-foto DB que a Glovo agora supre | 47 / 2.977 |
| Produtos Glovo que **não** estão na DB | **5.558** |
| Ativos DB que **não** estão na Glovo | 3.416 (81,6%) |

**Interpretação honesta:** os dois catálogos têm tamanho parecido (~6.2k) mas **só ~18% se sobrepõem** por id+nome. Causas: (a) os `storeProductId` na DB (scrape antigo) **rotacionaram** na Glovo; (b) a DB tem muitos itens de **balcão/peixaria/talho por kg** ("Camarão Costa Kg", "Pargo Amanhado Kg") com nomes que não casam com os listados Glovo. Staples comuns existem em ambos (banana: 49 na Glovo; iogurte: 116).

**Recomendação: REBUILD é agora a opção forte** (ao contrário da sessão anterior, onde 1.953 implicaria encolher o catálogo). Razões:
- Glovo dá **6.245 produtos reais, 100% com foto, com preço-base actual** (a DB tem 2.977 sem foto e prove­nience incerta).
- Resolve de uma vez o problema das fotos (a tentativa via match falha porque os item-sets divergem).
- IDs ficam consistentes (`auc-{storeProductId}` actual).

**Como fazer o rebuild (sessão dedicada de ESCRITA, não esta):**
1. **Enriquecer o crawler** para capturar a **categoria por produto** (o caminho da coleção) — actualmente só guarda name/price/img/id. Necessário para popular `category_root` nos INSERTs.
2. Importar os 6.245 como linhas novas (`auc-{storeProductId}`, preço-base = preço Glovo, foto real, categoria da fonte).
3. Retirar (soft-delete `is_available=false`, `removal_reason='replaced_by_glovo_rebuild'`) os antigos não presentes no novo set. **Nunca DELETE.**
4. Manter backups (`_backup_auchan_pre_sync_2026_06_06` já existe).
5. **NÃO** fazer "hybrid merge" (importar os 5.558 por cima dos 6.238 actuais) → criaria ~11k linhas com duplicação massiva. Rebuild limpo é melhor que merge.

> Alternativa conservadora: manter a DB e aceitar 2.977 sem foto. Mas dado que a Glovo cobre o catálogo completo com fotos, o rebuild dá muito melhor qualidade pelo mesmo tamanho.

## Evidência técnica (reprodutível)
- Leaf `fruta-fresca`: 12 PRODUCT_TILE inline + 4 CONTENT_PLACEHOLDER (secções não carregadas). Placeholder `id=23934730` ("Laranja, Clementina e Limão") via `content/partial` → +7 produtos. **Multiplicado por centenas de leaves = +4.292.**
- Mercearia top: 20 produtos + 130 COLLECTION_TILE (subcategorias, já seguidas) — sem placeholders ao nível top.
- Sem campos de paginação por token em nenhuma resposta.

## Estado
- DB **intacta** (read-only). 0 escritas.
- Crawler corrigido e re-testado (6.245, 0 erros).
- Decisão de rebuild fica para o Danilo + sessão de escrita dedicada.
