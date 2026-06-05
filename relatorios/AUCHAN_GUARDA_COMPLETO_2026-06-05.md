# Auchan-Guarda — Relatório Final de Sessão · 2026-06-05

> Sessão autónoma (Opus 4.8) · branch `autonomous-night-2026-04-29`
> Ver auditoria detalhada em `AUDITORIA_AUCHAN_2026-06-05.md`.

## Fonte escolhida
**Glovo** (`auchan-grd`, store 124961 / addr 226966). Uber Eats inacessível (domínio bloqueado pelo browser). Glovo tem catálogo completo da Auchan.
Nota pricing: Glovo Auchan = "mesmo preço que na loja" → **não** subtrair 15% se um dia se recalcular preço a partir do Glovo.

## Antes / Depois

| Métrica | Antes | Depois |
|---|---|---|
| Total produtos | 6.342 | 6.342 |
| Sem preço | 0 ✅ | 0 ✅ |
| HTML partido (entidades reais) | 2.311 | **0 ✅** |
| Com foto | 3.344 (52,7%) | 3.344 (52,7%) |
| Sem foto | 2.998 | 2.998 |
| Categorias (category_root) | 56 | 56 |

## Resultados concretos
- **HTML entities: 100% limpos** (objetivo principal cumprido — era o bug visível em `category_root` tipo "Tecnologia E Eletrodom&eacute;sticos" → agora "…Eletrodomésticos"). 13 entidades, ~2.311 linhas, em name/category/category_root/description.
- **Fotos: 0 líquidas** — backfill via donor foi tentado (chegou a 81,6%) e **revertido** por gerar placeholders genéricos (ver auditoria). Decisão de integridade: melhor 2.998 vazias e honestas do que 1.739 imagens repetidas/erradas na grelha.
- **Preços: 0 alterados** — já estavam 100% preenchidos; sem evidência de duplo-markup.
- **Produtos adicionados/removidos: 0** — requer catálogo-fonte completo (scraper).

## Métricas finais (MCP)
```
total=6342 · sem_preco=0 · com_foto=3344 · sem_foto=2998 · html_quebrado=0 · categorias=56
```
Busca validada (`search_products`): `ban`, `agu`, `iogur`, `detergent` → todos devolvem resultados relevantes com nomes acentuados corretos.

## Critérios de sucesso do prompt
| Critério | Alvo | Resultado |
|---|---|---|
| sem_preco = 0 | ✅ | **0 ✅** |
| html_quebrado = 0 | ✅ | **0 ✅** |
| sem_foto < 50 | ✅ | **2.998 ❌** (não atingido — ver abaixo) |
| Total ~ fonte | — | inalterado (sem add/remove) |

## Porque sem_foto não foi a <50 (honestidade)
As 2.998 sem foto incluem 1.169 que um cleanup **anterior** removeu deliberadamente (`cleared_cross_mismatch` 918 + `cleared_badge` 251) por serem cross-loja erradas. A única forma fiável de as preencher é com **fotos reais da fonte Glovo**, que exige o scraper Playwright com network-intercept (`market-data-sync`) — a API Glovo está bloqueada por CORS no browser interativo e o catálogo tem ≈600 coleções. Tentar via DOM-scraping ad-hoc nesta sessão revelou-se frágil (a tab fechou a meio).

## PRÓXIMO PASSO recomendado (follow-up dedicado)
Correr `market-data-sync` para `auchan-guarda` com **fonte = Glovo** (store 124961 / addr 226966):
1. Extrair `{nome, photo_url real, preço}` por coleção (Playwright + intercept de `api.glovoapp.com`).
2. Match por name-key (lower + sem acentos + sem unidades/marca) → UPDATE `photo_url` (URL externo, **não** descarregar) + `needs_photo=false` só quando a foto for específica do produto (rejeitar URLs partilhados por N≥3 produtos = placeholder).
3. INSERT dos produtos da fonte ausentes na DB; soft-delete (`is_available=false`) dos que faltarem na fonte com confiança <80%.
4. Validar `sem_foto < 50` e `html_quebrado=0` no fim.

## Regra admin
A gestão de produtos por loja já existe no admin. Não foi identificada lacuna nova de painel.

## Zonas protegidas
Intactas. Apenas dados de catálogo da loja `auchan-guarda` foram tocados.
