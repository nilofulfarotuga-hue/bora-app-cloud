# Market Data Sync Noturno — Auchan + Intermarché · 2026-06-06

> Sessão autónoma overnight (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`
> Validado via `prompt-blindado-validator`. Backups criados ANTES de qualquer escrita:
> `_backup_auchan_pre_sync_2026_06_06` (6238) · `_backup_intermarche_pre_sync_2026_06_06` (3004).

## 1. Fontes acessíveis
| Fonte | Browser tool | Node (server-side) | Resultado |
|---|---|---|---|
| **Glovo Auchan Guarda** | ✅ (mas CORS na API) | ✅ **API decifrada** | **catálogo completo extraído** |
| Uber Eats (Intermarché) | ❌ bloqueado | ❌ "Header overflow" (anti-bot) | **inacessível** |
| intermarche.pt / auchan.pt | ❌ bloqueado | — | inacessível |

### Breakthrough técnico — API Glovo (reutilizável)
A skill `market-data-sync` era um **scaffold sem adapters** (pasta `adapters/` inexistente; colunas erradas `image_url`/`price_cents`). Implementei um crawler real:
- Endpoint catálogo: `GET https://api.glovoapp.com/v3/stores/124961/addresses/226966/content?nodeUrl=/collections/{scId}` (200).
- Subcoleções: `COLLECTION_TILE.action.data.path` → `/v4/stores/.../content/main?nodeType=DEEP_LINK&link=...`.
- `PRODUCT_TILE.data` → `storeProductId`, `name`, `price`, `imageUrl` (CDN real `glovo.dhmedia.io/global-catalog-glovo/...`).
- **Match DB↔Glovo: `products.id = 'auc-' + storeProductId`** (confirmado: auc-3375255 ↔ 3375255, preços idênticos).
- Crawler guardado em `.claude/skills/market-data-sync/scripts/glovo_grocery_crawler.js`.

Crawl Auchan: **150 coleções, 1953 produtos únicos, 0 erros, 0 placeholders** (imagens `global-catalog` são por-produto).

## 2. Auchan — antes/depois
| Métrica | Antes | Depois |
|---|---|---|
| Total | 6238 | 6238 |
| Ativos | 4186 | 4186 |
| Sem foto | 2998 | **2977** (−21) |
| Fotos reais Glovo aplicadas | — | **21** (`image_source='glovo_real_name'`) |
| Ativos sem preço | 0 | 0 |
| Produtos adicionados | — | 0 |
| Produtos removidos | — | 0 (STOP rule, ver §4) |

### 🚨 ACHADO CRÍTICO — catálogo DB divergiu da Glovo atual
- Glovo Auchan Guarda **hoje = 1953 produtos**. DB tem **4186 ativos**.
- **Só 269/4186 (6,4%)** dos ativos da DB partilham `storeProductId` com a Glovo atual.
- Por **nome** normalizado, só **21** dos 2998 sem-foto coincidem com a Glovo.
- **1684** produtos Glovo **não existem** na DB.
- **3917 (93,6%)** ativos da DB **não existem** na Glovo atual.

**Interpretação:** o catálogo Auchan na DB (provável scrape antigo/maior, ou auchan.pt) **deixou de espelhar** a loja Glovo Guarda real. Por isso a Glovo **não consegue fornecer fotos** para os 2977 sem-foto — esses produtos simplesmente já não estão no Glovo Guarda. As fotos reais só cobrem produtos que continuam no catálogo Glovo (e esses, em geral, já tinham foto).

## 3. Intermarché — não executado
Uber Eats inacessível (browser bloqueado + Node "Header overflow" anti-bot). Sem storeId nem API pública viável. **Fase B impossível neste ambiente.** Os 3 perfimes (€120/€80/€80) **continuam por verificar**. Catálogo Intermarché inalterado (total 3004, sem-foto 1864).

## 4. Validação cruzada / remoções — STOP rule acionada (correto)
- Ativos-não-na-fonte = **3917 (93,6%)** → **excede 50%** e cobertura (6,4%) <60% → **remoções SALTADAS** automaticamente pelos gates do script. Apagar seria destruir 93,6% do catálogo com base numa fonte que pode ser um snapshot menor. **Decisão diferida ao Danilo.**
- Inserts (fonte-não-na-DB) = **1684** → **reportados, NÃO aplicados** (faltava categoria por-produto + a divergência exige decisão humana de resync).

## 5. Placeholders
**0 placeholders** detetados/rejeitados (Glovo global-catalog usa imagem única por produto). As 21 fotos aplicadas são reais e específicas.

## 6. Estado final de qualidade
| Loja | % com foto | Match c/ fonte | Notas |
|---|---|---|---|
| Auchan | 52,3% (3261/6238) | 6,4% por id (catálogo divergiu) | +21 fotos reais; resync pendente |
| Intermarché | 38% (inalterado) | — | fonte Uber inacessível |

## 7. Próximos passos sugeridos (decisão do Danilo)
1. **Decidir o resync Auchan:** o catálogo DB (4186) vs Glovo atual (1953). Opções: (a) **rebuild** do zero a partir dos 1953 Glovo (catálogo menor mas 100% real + fotos), perdendo 2233 produtos "extra"; (b) manter o catálogo atual e aceitar que ~2977 não terão foto Glovo; (c) procurar fotos noutra fonte (auchan.pt via scraper dedicado não-bloqueado).
2. Para **Intermarché**, a única via é um runner com browser real + evasão anti-bot da Uber (fora deste ambiente) ou um feed/API parceira.
3. O **crawler Glovo** (`scripts/glovo_grocery_crawler.js`) está pronto para reusar em qualquer loja Glovo Guarda (basta store/addr id).

## Regra admin
A edição de produto individual existe no admin, mas **não há import/undo em massa por loja** (CSV/bulk). Para um resync desta escala seria útil — registado como melhoria.

## Reversibilidade
Tudo reversível: 21 UPDATEs de foto (image_source='glovo_real_name'); 0 remoções; 0 inserts. Backups completos em `_backup_*_pre_sync_2026_06_06`. Zonas protegidas (dispatch/pricing/Stripe/triggers/RLS) **intactas**.
