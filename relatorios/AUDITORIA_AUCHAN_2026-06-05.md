# Auditoria Auchan-Guarda — 2026-06-05

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · branch `autonomous-night-2026-04-29`
> Validado via `prompt-blindado-validator` (BLOCO 1–6 ✅) antes de executar.

## Passo 0 — Decisão da fonte

| Fonte | Estado | Catálogo Auchan Guarda |
|---|---|---|
| **Glovo** | ✅ disponível | `/pt/pt/guarda/stores/auchan-grd` — store **124961** / address **226966**; catálogo completo da loja (≈600 subcategorias, toda a árvore Auchan) |
| Uber Eats | ❌ inacessível | `ubereats.com` bloqueado pela extensão Claude in Chrome ("Navigation to this domain is not allowed") |

**Decisão: GLOVO.** É a única fonte acessível e tem o catálogo completo da Auchan.

> ⚠️ **Achado relevante de pricing:** a página Glovo Auchan exibe *"Mesmo preço que na loja"*. Ou seja, ao contrário do pressuposto do prompt, o Glovo Auchan **não embute markup próprio** — o preço Glovo ≈ preço auchan.pt. Implicação: se algum dia se recalcular preço a partir do Glovo Auchan, **não** se deve subtrair 15% (não há markup do Glovo a remover). O preço-base na DB continua a ser o preço de loja; os 15% do Bora são aplicados em runtime por `pricing_calculate`.

## Estado inicial (confirmado via Supabase MCP)

| Métrica | Valor |
|---|---|
| Total produtos | 6.342 |
| Sem preço | 0 ✅ |
| Sem foto | 2.998 (47%) ⚠️ |
| HTML partido (name/category/category_root) | 2.311 |
| Sem categoria | 1 |
| Categorias (category_root) | 56 |
| Preço min / máx | €0,11 / €1.349,99 |

## Auditoria — conclusões

### 1. HTML entities (Passo 2.3) — RESOLVIDO
13 entidades distintas presentes em `name`/`category`/`category_root`:
`&atilde; &ccedil; &aacute; &oacute; &eacute; &uacute; &otilde; &ecirc; &iacute; &agrave; &acirc; &ocirc; &ordm;`.
Decodificadas todas. **0 entidades reais restantes.** (Os `&` restantes são ampersands legítimos: "Frutas & Legumes", "Laticínios & Ovos", etc.) `search_normalized` re-normalizou via trigger.

### 2. Fotos (Passo 2.1) — investigado, sem solução segura via DB
Os 2.998 sem foto decompõem-se em:
- **918** `image_source = cleared_cross_mismatch` — foto removida por um **cleanup anterior** (match cross-loja considerado errado).
- **251** `image_source = cleared_badge` — foto removida (badge).
- **1.829** genuinamente sem foto (sem label cleared).

Tentativa de backfill via doadores (Pingo Doce / Intermarché / Continente) por `search_normalized` exato + 2º passe por name-key (sem unidades/marca): chegou a 81,6% com foto. **Revertido na íntegra** após descobrir que as fotos doadoras são **placeholders genéricos de categoria** (1 imagem para 73 queijos, 55 vinhos, 53 pães, 48 leites…). Frequência global dos URLs doadores: 1.370 fills usavam URLs partilhados por 10+ produtos; **nenhum** era único global. Manter teria enchido a grelha de imagens repetidas/erradas — pior que vazio. A reversão alinha com a decisão do cleanup anterior (`cleared_cross_mismatch`).

➡️ **Fotos reais só podem vir da fonte (Glovo/auchan.pt).** A API de conteúdo Glovo está bloqueada por CORS no contexto da página, e o catálogo tem ≈600 coleções — harvesting fiável é trabalho do scraper dedicado (`market-data-sync`, Playwright + network intercept), não desta sessão de browser interativo.

### 3. Preços (Passo 2.2) — sem alteração
`sem_preco = 0` já antes da sessão. Não há evidência de duplo-markup. Verificar 6.342 preços contra site/Glovo exige scrape completo (fora de alcance seguro). **Nenhum preço foi alterado.**

### 4. Produtos a adicionar/remover (Passo 2.4/2.5) — diferido
Requer o catálogo-fonte completo (scraper). Não executado nesta sessão.

## Mudanças aplicadas nesta sessão
- ✅ Decode HTML entities em `auchan-guarda` (1 UPDATE, ~2.311 linhas) → html_quebrado 0.
- ↩️ Backfill donor aplicado e **revertido** (1.829 produtos voltaram a `photo_url=NULL`, `needs_photo=true`, `image_source='reverted_donor_placeholder'`).

## Zonas protegidas — intactas
Nenhuma alteração a dispatch, pricing_service, Stripe, triggers financeiros, RLS de orders/wallets/ledger. Apenas dados de catálogo (`products`) da loja `auchan-guarda`.
