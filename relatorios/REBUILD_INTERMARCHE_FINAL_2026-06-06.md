# Rebuild Intermarché-Guarda — Tentativa + Breakthrough Uber · 2026-06-06

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL · **DB NÃO foi tocada** (ver decisão §3).
> Danilo: "vira-te, tu consegues". Resultado: o que era "impossível" (Uber) está **90% resolvido**.

## 1. Estratégias tentadas (1–7)
| # | Estratégia | Resultado |
|---|---|---|
| 1 | **Glovo** Intermarché Guarda | ❌ Não tem. 6 supermercados (auchan, continente, prio + 3 lojas hashed address-gated não-identificáveis sem morada); "intermarche" ausente |
| 2/3 | **Uber Eats API** | ✅ **ACESSO RESOLVIDO** (ver §2) — o grande avanço |
| 4 | Playwright Stealth | não necessário (API direta funcionou no acesso) |
| 5 | **Wolt** Guarda | ❌ Wolt não opera na Guarda (0 venues no feed `restaurant-api.wolt.com`) |
| 6 | intermarche.pt | ❌ 403 (já sabido) |
| 7 | Outros agregadores | n/a (Uber é a fonte com Intermarché) |

## 2. Uber Eats — o que foi DESBLOQUEADO (antes dito "impossível")
1. **Header-overflow anti-bot resolvido:** a homepage rebentava o parser de Node; a fix é `maxHeaderSize: 131072` em `https.request`. Todas as chamadas à API passam a 200.
2. **Localização (bloqueio real):** o feed/loja exige cookie `uev2.loc` com `reference` = **place_id REAL do Google**. Resolvi "Guarda" via Google Places (GOOGLE_MAPS_API_KEY do projeto) → place_id `ChIJU8b2j8T6PA0RADWQ5L3rAAQ` → cookie válido.
3. **Feed Guarda:** `getFeedV1` → 462KB, lista as lojas. **Intermarché Guarda existe:** `storeUuid = a0fe1ff9-4042-55a3-9a28-ae1d84b93576` (title `pt_intermarche`).
4. **Catálogo (esqueleto):** `getStoreV1` → 260KB com **44 categorias** (Charcutaria, Frutas e Legumes, Álcool, Bebidas, Sobremesas, Casa…) + **~75 produtos featured**. Item = `{uuid, title, price (cêntimos), imageUrl, subsectionUuid, isAvailable}`.

Artefacto funcional guardado: `scripts/uber_eats_probe.js`.

## 3. O bloqueio que resta (1 passo) + porque NÃO fiz rebuild
- Para os **~3000 produtos completos** é preciso carregar cada uma das 44 secções via `getCatalogPresentationV2`. Esse endpoint devolve **sempre "Pedido inválido" (400)** com TODAS as combinações testadas de params (`{storeUuid, sectionUuid, subsectionUuids[]}`, +`pageInfo`, +`vertical:GROCERY`, subsecção única, swaps). >4 tentativas, mesma causa → STOP rule.
- **getStoreV1 só dá 75 itens.** Fazer rebuild com 75 produtos **degradaria** a DB (que tem **2962** ativos). A regra é explícita: *"não deixar a DB num estado pior"*. Por isso **não criei backup, não apaguei, não inseri nada** — a Intermarché fica como está.

## 4. Como FINALIZAR (próxima sessão, rápido)
O endpoint catV2 só precisa do **body exato**, que se captura em **1 minuto**:
1. Abrir a loja Intermarché Guarda no browser (Uber Eats), DevTools → Network.
2. Fazer scroll numa categoria → aparece o request `getCatalogPresentationV2`.
3. Copiar o **Request Payload** (JSON) → colar em `uber_eats_probe.js`.
4. Iterar as 44 `sections` (como o crawler Glovo itera coleções), extrair `{uuid,title,price,imageUrl}` por secção.
5. Rebuild idêntico à Auchan: backup → DELETE → INSERT `int-uber-{uuid}`, **preço = preço_uber × 0.85** (Uber tem markup → "−15%" = preço-base), `photo_url` = imageUrl Uber, `category`/`category_root` = título da secção, `sort_order` = ordem das secções.

## 5. Métricas (inalteradas — DB intacta)
`intermarche-guarda`: total=3004, ativos=2962, sem_foto=1864 — **sem alterações nesta sessão**.

## 6. Recomendações ao Danilo
1. **Melhor opção:** capturar o 1 request catV2 (passo §4) e correr o rebuild — Uber JÁ está acessível, é só este detalhe. Posso terminar em 1 sessão com esse payload.
2. Alternativa sem captura manual: serviço de scraping (Apify/Bright Data ~$50/mês) que já lida com o catV2 da Uber.
3. Ou modo "ajudante" (como Lidl/Mercadona) se Intermarché não for prioritário.

## 7. Zonas protegidas
Intactas. Nenhuma escrita na DB. Apenas leitura de APIs externas + 1 script novo + relatório.
