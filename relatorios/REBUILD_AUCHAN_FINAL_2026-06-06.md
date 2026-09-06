# Rebuild Completo Auchan-Guarda — 2026-06-06

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`.
> Decisão do Danilo: apagar Auchan e importar o catálogo Glovo EXATAMENTE (preço, foto, categoria, ordem).
> Esclarecimento do Danilo a meio: "tem q ser igual à Glovo — categorias e ordem e tudo".

## 1. Crawl (Glovo, store 124961 / addr 226966)
- Crawler enriquecido (`scripts/glovo_grocery_crawler.js`): além de id/name/price/img, captura agora **categoria top** (`root`, do slug `-sc.{id}` do deep-link → nome com acentos) e **sub-secção** (`leaf`), e segue `CONTENT_PLACEHOLDER`.
- Resultado: **6.240 produtos**, 0 erros, 0 sem foto/preço/categoria, **21 categorias top** (= as 21 da home Glovo). Preço máx €55,99 (supermercado, 0 tech).

## 2. Backups (rede de segurança)
- `_backup_auchan_pre_rebuild_2026_06_06` (6.238 linhas) ✅ criado antes de qualquer escrita.
- (+ `_backup_auchan_pre_sync_2026_06_06`, `_backup_auchan_tech_deleted_2026_06_05` já existentes.)
- Segurança verificada: única FK a `products` é `product_variants` (CASCADE, 0 variantes na Auchan); **nenhuma FK a orders/order_items/ledger** → DELETE não toca histórico/zonas protegidas.

## 3. DELETE
`DELETE FROM products WHERE restaurant_id='auchan-guarda'` → confirmado **0 restantes**.

## 4. INSERT (upsert PostgREST service role, lotes de 200)
- **6.240 upserted, 0 falhas.**
- Campos: `id='auc-'+storeProductId`, name/photo_url/price/category exatos do Glovo, `is_available=true`, `source='glovo_rebuild_2026_06_06'`, `image_source='glovo_official'`, `needs_photo=false`, `last_updated='2026-06-06'`.

### Categoria — convenção do schema (importante)
Há um trigger `trg_products_set_category_root` que faz `category_root := split_part(category,'/',1)`. As lojas que funcionam (Continente, Auchan antiga) usam `category = category_root = categoria TOP` (plano). Replicado: gravámos `category = categoria top Glovo` (ex.: "Mercearia") → o trigger produz `category_root` igual. Resultado: **21 categorias** = tabs iguais à Glovo. A sub-secção Glovo (ex.: "Leite Meio Gordo") fica preservada na **ORDEM** (ver §Ordem), modelo idêntico ao resto da app.

### Ordem igual à Glovo (pedido explícito do Danilo)
- Nova coluna aditiva **`sort_order`** (migration `add_products_sort_order`), preenchida com a sequência Glovo (categorias na ordem da home + produtos por secção).
- Edição cirúrgica em `lib/stores/restaurant_store.dart`: a query de produtos passou a `.order('sort_order', nullsFirst:false).order('id')`. Mercados seguem a ordem Glovo; parceiros (sort_order NULL) caem no desempate por `id` (determinístico, paginação estável — sem regressão).
- Verificado: ordem das categorias = home Glovo (Frutas e Vegetais → Talho e Peixaria → Charcutaria e Queijos → Padaria e Pastelaria → Laticínios e Ovos → Mercearia → Mercearia Doce → Refeições Frescas → ...).
- ⚠️ Requer **rebuild do APK** para o `.order()` fazer efeito na app.

## 5. Validação final (MCP)
| Métrica | Valor | Critério |
|---|---|---|
| total | **6.240** | ≈6.245 ✅ |
| ativos | 6.240 | = total ✅ |
| sem_foto | **0** | 0 ✅ |
| sem_preço | **0** | 0 ✅ |
| categorias (category_root) | **21** | ≈21 ✅ |
| sort_order nulos | 0 | ✅ |
| preço min/máx | €0,10 / €55,99 | >0, <€100 ✅ |

Busca (`search_products`): "mimosa" → Natas/Leite Mimosa com preços; "leite meio gordo" → Leite Açores €0,87. Funcional com fotos e preços Glovo.

## 6. Produtos das fotos do Danilo (confirmados na DB)
| id | nome | preço |
|---|---|---|
| auc-11885 | LEITE UHT MIMOSA:M/GORDO 1L | €1,00 |
| auc-3010403 | LEITE AUCHAN UHT MEIO GORDO SLIM 1L | €0,86 |
| auc-3704142 | LEITE UHT GRESSO MEIO GORDO 1 L | €0,87 |
| auc-3045094 | LEITE MEIO GORDO AUCHAN:AÇORES 1L | €0,87 |
| auc-3938133 | LEITE UHT M/GORDO MIMOSA MEIO GORDO 4X200ML | €1,68 |

Todos presentes, category_root="Laticínios e Ovos", preços = Glovo.

## 7. Diferenças vs backup
- Novo total: 6.240 · Backup: 6.238.
- **Mantidos (mesmo id): 695 · Novos: 5.545 · Descartados: 5.543.**
- Interpretação: o catálogo antigo era um amálgama (ids `auc-`+UUID de fontes várias, preços stale). Agora é espelho 1:1 da Glovo atual.

## 8. Notas importantes
- **Preço gravado = preço Glovo direto** (Glovo Auchan = "mesmo preço que na loja" = preço-base). O +15% Bora aplica-se em runtime no checkout — fora do âmbito desta sessão.
- **Histórico de pedidos:** order_items guardam `product_id` como texto sem FK; pedidos antigos que referenciem ids antigos ficam com referência não-resolúvel (snapshot do pedido mantém-se). Decisão explícita do Danilo (rebuild total).
- Zonas protegidas (dispatch, pricing_service, Stripe, triggers financeiros, RLS orders/wallets/ledger) **intactas**.

## 9. Próximos passos sugeridos
1. **Rebuild do APK** para activar a ordenação Glovo (`.order('sort_order')`).
2. **Reverter** (se necessário): `DELETE ... ; INSERT ... SELECT * FROM _backup_auchan_pre_rebuild_2026_06_06;` (via MCP).
3. **Intermarché:** fonte Uber inacessível (browser+Node anti-bot) — precisa runner com browser real; não foi tocado.
4. **Cron semanal** de refresh de preços/catálogo via o crawler (a decidir; não configurado nesta sessão).
5. Considerar guardar a sub-secção Glovo (`leaf`) numa coluna própria se a app vier a suportar sub-categorias.
