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

---

# ADDENDUM — Add-on "FONTE = VERDADE" (mesma sessão, 2026-06-05)

Confirmado que a fonte é **Auchan GUARDA** (Glovo `auchan-grd`, header "Guarda › Supermercados › Auchan"). A árvore de categorias do Glovo Auchan Guarda é **100% supermercado — zero categorias de eletrónica/tech**. Logo, produtos tech na DB vieram do scrape errado de auchan.pt e não são vendáveis pela loja física.

## Produtos removidos por não estarem na fonte Guarda
Modo **seguro**: `is_available=false` + nova coluna `removal_reason='not_in_source_glovo_guarda'` (migration `add_products_removal_reason`). **NÃO houve DELETE** — reversível e auditável. DELETE definitivo só após validação do Danilo.

| Categoria original | Removidos |
|---|---|
| Tecnologia E Eletrodomésticos | 26 (estavam **ativos**: iPhone 16 €889, Galaxy S25 Ultra €934, portátil Asus €699, trotinete Segway €699, câmara Canon €509…) |
| Som | 14 |
| Smartphones | 11 |
| Smartwatches E Smartbands | 10 |
| Periféricos | 10 |
| Informática | 8 |
| Impressoras E Tinteiros | 4 |
| Acessórios Telemóveis | 4 |
| Gaming | 4 |
| Câmaras / Domótica / Redes Wifi / Mobilidade Urbana | 2 cada |
| Monitores / Armazenamento / Imagem E Som / Telemóveis E Wearables | 1 cada |
| (sem categoria) Auscultadores Bluetooth | 1 |
| **TOTAL** | **104** |

> Apenas 26 estavam **ativos** (visíveis ao cliente) — o resto já estava `is_available=false`. Todos ficaram stampados com `removal_reason` para auditoria.

### Anomalias >€100 não-tech — investigadas, MANTIDAS (não eram erros)
- Presunto Inteiro Ibérico Cebo 50% Auchan Collection 24 meses — €219 (perna inteira premium, legítimo)
- Patas Caranguejo Real Cozidas Congeladas/kg — €140 (preço/kg legítimo)
- Carabineiro Moçambique 8/12 Congelado/kg — €120 (preço/kg legítimo)
> O €219 em "Charcutaria & Queijos" referido no add-on **não é erro** — é uma perna de presunto inteira.

## Categorias consolidadas (duplicados → canónico)
| De (duplicado) | Para (canónico) |
|---|---|
| Fruta · Legumes · Frutas E Legumes Produtos Locais | **Frutas & Legumes** |
| Padaria · Pastelaria | **Padaria & Pastelaria** |
| Charcutaria · Queijaria | **Charcutaria & Queijos** |
| Bebidas E Garrafeira · Vinhos & Espirituosas | **Bebidas** |
| Laticínios | **Laticínios & Ovos** |

Mantida a convenção "&" (consistente com as outras lojas Bora — não troquei por "e" para não dessincronizar o catálogo geral). Categorias **visíveis ao cliente: ~26 → 16**.

> Não consolidei mapeamentos ambíguos (Higiene genérica, Alimentação/Gastronomia, Bio/Sem Glúten/Sem Lactose, Casa/Jardim/Papelaria) — exige ver produto a produto ou a fonte completa. Renomes cosméticos single-categoria (Bebé→"Bebé e Criança", Animais→"Animais de Estimação") deixados como estão (não são duplicados).

## Métricas finais (pós add-on, MCP)
```
total=6342 · ativos=4186 · removidos_fonte=104 · categorias_visiveis=16
ativos_sem_preco=0 ✅ · ativos_html_quebrado=0 ✅
```
STOP rule (<70% da fonte): não acionada — só 104 removidos (~1,6%); consolidação não desativou nada.

## Pendente para o follow-up (scraper Glovo completo)
- Remoção **product-level** de itens alimentares ausentes na fonte (precisa do catálogo Glovo completo — não dá só por categoria).
- Fotos reais das ~2998 sem foto.
- Ordem das categorias igual à fonte + eventuais renomes para nomes exactos do Glovo.

## Zonas protegidas
Intactas. Apenas dados de catálogo (`products`) da loja `auchan-guarda` + 1 coluna aditiva `removal_reason`. Nenhuma alteração a dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger.
