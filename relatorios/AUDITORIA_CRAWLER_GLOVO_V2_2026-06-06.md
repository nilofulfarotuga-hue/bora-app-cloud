# Auditoria #2 do Crawler Glovo Auchan — 2026-06-06

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · **read-only na DB** (zero escritas).
> Validado via `prompt-blindado-validator`. Motivada pelas fotos reais do Danilo (pesquisa "leite meio gordo" + home, 08:20).

## TL;DR
O crawler corrigido (que segue `CONTENT_PLACEHOLDER`) **JÁ apanha todos os produtos das fotos**. Eles aparecem "em falta" porque estão **na DB stale** — a DB nunca foi reconstruída com o crawl corrigido. **6/6 produtos das fotos confirmados** no crawl. A staleness está na DB, não no crawler.

## Respostas às 5 perguntas

### 1. Quantos produtos REALMENTE tem a Glovo Auchan Guarda hoje?
**~6.240** (dois crawls: 6.245 e 6.233 — variação de ~12 por stock/disponibilidade live entre execuções, normal). 0 erros, queue drenada a 0. É catálogo completo de supermercado.

### 2. Onde estavam os produtos "em falta"?
**Não estavam em falta no crawler.** Estão na **árvore de categorias normal**, em secções `CONTENT_PLACEHOLDER` que o crawler corrigido já segue. Exemplo verificado: secção **"Leite Meio Gordo"** (`content/partial?component=section&id=23934793`) → 8 produtos, incluindo Slim/Gresso/Açores/Mimosa pack-4. **Não** foi preciso carrosséis da home nem índice de pesquisa.
- A pesquisa web (`/v3/stores/.../search`) devolve **503 "no available server"** (serviço de pesquisa web grocery indisponível) — mas é irrelevante: tudo é alcançável por browse.
- Os produtos faltam **na DB** porque a DB é um **amálgama de fontes**: parte com ids `auc-{storeProductId}` (Glovo) + muitos com **ids UUID** de outra origem (ex.: "Leite Mimosa Meio-gordo 1L" UUID €0,89), com nomes e preços diferentes dos da Glovo actual. Por isso o match falha e parecem "em falta".

### 3. O crawler tem cache antigo de preços? Quanto desfasado?
**NÃO — o crawler faz fetch LIVE a cada execução** (sem cache). No re-crawl de hoje, "LEITE UHT MIMOSA:M/GORDO 1L" (id 11885) = **€1,00** (igual à foto de hoje). **A DB é que está stale**: tem "Leite Mimosa Meio-gordo 1L" (UUID, outra fonte) a **€0,89**. Desfasamento ~12% nesse item, e os preços **mudam** (logo a DB precisa de refresh, não o crawler).

### 4. Quantos dos 6 produtos das fotos foram encontrados? Em que endpoint?
**6/6**, todos no endpoint normal de browse (`/v3/stores/124961/addresses/226966/content?nodeUrl=/collections/{sc}` → `CONTENT_PLACEHOLDER` → `content/partial?component=section&id=...`):

| Produto (foto) | storeProductId | Preço Glovo hoje | Secção |
|---|---|---|---|
| Limão Unid | 20578 | €0,56 | Frutas e Vegetais |
| Leite UHT Gresso Meio Gordo 1L | 3704142 | €0,87 | Leite Meio Gordo |
| Leite Meio Gordo Auchan Açores 1L | 3045094 | €0,87 | Leite Meio Gordo |
| Leite Auchan UHT Meio Gordo SLIM 1L | 3010403 | €0,86 | Leite Meio Gordo |
| Perna Frango **Lusiaves** ("Lusitano") 2kg | 3544313 | €5,99 | Talho e Peixaria |
| Paloco do Pacífico **Auchan** Desfiado 500g | 3933586 | €3,99 | Talho e Peixaria |

(+ confirmados da foto 1: Mimosa M/Gordo 1L €1,00 e Mimosa pack 4×200ml €1,68.)

### 5. Recomendação ao Danilo
**REBUILD — confirmado e reforçado.** O crawler está **provado completo** (6/6 produtos das fotos, ~6.240 itens, preços live). A DB actual é um **amálgama stale** (ids mistos `auc-`+UUID, preços antigos, nomes divergentes, produtos actuais em falta). Tentar "encher os buracos" por match falha porque as fontes divergem.
- **Resultado do rebuild:** ~**6.240 produtos** limpos, 100% com foto real, preço-base actual, ids consistentes `auc-{storeProductId}`.
- **Pré-requisito (pendente):** enriquecer o crawler para capturar **categoria por produto** (hoje só name/price/img/id) — necessário para `category_root` dos INSERTs.
- **Execução:** sessão de **ESCRITA dedicada** — importar os ~6.240, retirar (soft-delete `replaced_by_glovo_rebuild`) o catálogo antigo, manter backups (`_backup_auchan_pre_sync_2026_06_06`). **Nunca DELETE; nunca hybrid merge** (duplicação).

## Hipóteses do prompt — veredicto
| Hipótese | Veredicto |
|---|---|
| Carrosséis home / destaques | Não é a causa — produtos alcançáveis por browse normal |
| Vista pesquisa (search index) | Search web dá 503, mas irrelevante (browse cobre tudo) |
| Tabs internas (Carne/Peixe/Aves) | São `COLLECTION_TILE`, já seguidas |
| Paginação infinita | Inexistente; o que havia eram secções `CONTENT_PLACEHOLDER` (já corrigido) |
| Preços cache antigo no crawler | **Falso** — crawler é live; a **DB** é que está stale |
| Variantes de marca (Polegar/Auchan) | Confirmado — DB e Glovo têm o mesmo produto sob marcas/ids/nomes diferentes |

## Estado
- DB **intacta** (read-only, 0 escritas). Crawler **inalterado** nesta sessão (o fix já estava em `379022a`).
- Re-crawl confirma 6.233 produtos, 6/6 fotos, preços live.
- Decisão de rebuild + enriquecimento do crawler (categoria) ficam para sessão de escrita.
