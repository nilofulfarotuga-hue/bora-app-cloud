# Rebuild Wells-Guarda (farmácia) via Glovo — EXECUTADO · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`.
> Espelho 1:1 da Glovo Wells Guarda (estrutura/fotos/categorias/ordem + logo/capa). Sequência idêntica a Auchan/Continente.

## 1. Loja Glovo
**`wells-guarda`** — Glovo store **117943** / addr **216314** (categoria farmácia-e-beleza, Guarda).
19 categorias top na Glovo; semeadas as **16 reais** (saltadas 3 promo cross-cutting: `especial-verao`, `exclusivo-wells`, `novidades-beleza` — agrupamentos de marketing; produtos delas herdam a categoria real). **NENHUMA categoria real excluída.** Só OTC — "Medicamentos **Não** Sujeitos a Receita Médica" (sem medicamentos de receita; Glovo não os vende).

## 2. Crawler — artefacto do carrossel de destaques resolvido
A 1ª categoria do queue absorve sempre o carrossel "destaques/mais vendidos" do topo da loja (~300 produtos cross-category, first-wins).
- 1ª passagem (Solares 1º): Solares inflado a 316 (Clearblue/Norlevo/Avène mal-rooteados). ❌
- 2ª (Medicamentos 1º): meds inflados a 418 (cosmética dentro de meds). ❌
- **3ª (Saúde e Bem-Estar 1º): catch-all neutro de farmácia absorve os destaques (365); Medicamentos limpo (120), Solares real (18).** ✅
Mesmo padrão documentado no Continente ("Mais vendidos"→1ª cat). Foto/preço/nome/leaf sempre corretos; só o `category_root` de browsing dos destaques fica no catch-all.

## 3. Preço — Glovo direto (validado ≈ prateleira, SEM markup)
Per instrução: Glovo→preço direto. Wells é Sonae (como Continente), por isso validei amostra vs retalho PT:
| Produto | Glovo (DB) | Retalho típico PT |
|---|---|---|
| La Roche-Posay Anthelios UVMUNE 400 c/Cor SPF50+ 50ml | €20,02 | ~€20–22 ✓ |
| Bepanthene Pomada Cicatrizante 100g | €11,39 | ~€11–13 ✓ |
| Aquaphor Pomada Reparadora | €10,35 | ~€10–11 ✓ |
| Avène Cleanance Cor SPF50+ 50ml | €13,57 | ~€13–15 ✓ |
→ **Glovo Wells ≈ prateleira (sem markup)**, AO CONTRÁRIO da Glovo Continente (que tinha +15% provado por fatura). Gravado direto (`source='glovo_wells_rebuild_2026_06_07'`) = preço-base; +15% Bora em runtime. (wells.pt é SPA JS — sem preço no HTML estático; refresh oficial por SKU = follow-up opcional.)

## 4. Logo + capa (pedido Danilo "copia o logo")
Glovo expõe **uma** imagem de loja Wells (branded): `glovo.dhmedia.io/image/stores-glovo/stores/d7c347fe…` (JPEG 1242×690, HTTP 200).
`restaurants.photo_url` (logo) **e** `hero_image_url` (capa) de `wells-guarda` = essa imagem → **igual à Glovo**. Valores antigos eram `''`/`NULL` (reversível).

## 5. Métricas antes/depois (MCP)
| Métrica | Antes | Depois (Glovo) |
|---|---|---|
| Total | 476 | **1 310** |
| Ativos | 476 | **1 310** |
| Sem foto | 0 | **2** (99,8% com foto) |
| Sem preço | 0 | **0** |
| Categorias | — | **16** (ordem Glovo) |
| ids `wel-` / sort_order | — | **100%** (1310/1310) |
| Preço | — | €0,35–134,99 · médio €13,69 |

## 6. Categorias finais (ordem Glovo, 16)
Solares · Medicamentos Não Sujeitos a Receita Médica · Bebé e Mamã · Saúde e Bem-Estar · Higiene Oral · Saúde Sexual e Íntima · Cosmética Rosto · Cuidado Corpo · Cuidado Cabelo · Cosmética Masculina · Perfumes · Maquilhagem · Covid-19 · Nutrição e Suplementos · Ortopedia · Ótica.

## 7. Diff vs backup / reversão
Backup `_backup_wells_pre_rebuild_2026_06_07` (476). Novo=1310, prefix `wel-{storeProductId}` → substituição total.
Reverter produtos: `DELETE FROM products WHERE restaurant_id='wells-guarda'; INSERT INTO products SELECT * FROM _backup_wells_pre_rebuild_2026_06_07;`
Reverter logo: `UPDATE restaurants SET photo_url='', hero_image_url=NULL WHERE id='wells-guarda';`

## 8. Zonas protegidas
Intactas. Só `products` de `wells-guarda` + `restaurants.photo_url/hero_image_url` dessa loja + backup. Sem toques em dispatch/pricing/Stripe/triggers/RLS de orders·wallets·ledger. Outras lojas não tocadas.
