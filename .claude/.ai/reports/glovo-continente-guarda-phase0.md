# FASE 0 — Glovo Continente Guarda (análise API)

**Data:** 2026-04-21
**Modo:** PROTECÇÃO TOTAL — zero BD, zero mutações
**Campanha:** `glovo-continente-guarda`
**URL da loja:** https://glovoapp.com/pt/pt/guarda/stores/continente-grd1

---

## 1. Identificadores descobertos

| Campo | Valor |
|---|---|
| Store slug | `continente-grd1` |
| **Store ID** | `295687` |
| **Store Address ID** | `470732` |
| Cidade | Guarda |
| City Code | `GRD` |
| Coordenadas | `40.5373, -7.2674` |
| País | PT |

## 2. API confirmada (HTTP 200)

**Base:** `https://api.glovoapp.com`
**Endpoint:** `/v4/stores/295687/addresses/470732/content/main?nodeType=DEEP_LINK&link={sectionSlug}`

**Headers obrigatórios:**
```
glovo-api-version: 14
glovo-app-platform: web
glovo-app-type: customer
glovo-location-country-code: PT
glovo-location-city-code: GRD
glovo-location-latitude: 40.5373
glovo-location-longitude: -7.2674
glovo-language-code: pt
```

**Sem estes headers:** HTTP 400 `DeliveryAddressOutOfCityException`.

## 3. Campos a extrair (Fase 1)

| Campo Glovo | Usamos? | Destino |
|---|---|---|
| `name` | SIM | `products.name` |
| `imageUrl` | SIM | `products.image_url` |
| `GRID.title` (sub-secção) | SIM | `products.category` (ou mapear via taxonomy-mapper) |
| `externalId` / `storeProductId` | SIM | chave de de-dup |
| `price` / `priceInfo` | **NÃO** | preço vem do Continente.pt |

## 4. Estrutura do catálogo (descoberta via SSR + API)

Hierarquia:
- **Secção (sc)** — ex. `mercearia-sc.26976256`
- **Categoria (c)** — ex. `batatas-fritas-e-snacks-c.26976875`
- **Sub-grid (s)** — ex. `batatas-lisas-e-onduladas-s.26976629`
- **Produto** — `PRODUCT_TILE`

Secções principais detectadas: Mercearia, Bebidas, Frutas & Vegetais, Talho & Peixaria, Laticínios, Padaria, Congelados, Higiene, Limpeza, Saúde, Alto em Proteína, Novidades, Bebé, etc.

## 5. Prova: 10 exemplos (categoria "Batatas Fritas e Snacks")

| # | Nome | Categoria | Imagem |
|---|---|---|---|
| 1 | Batata Frita Lisa com Sal Lay's (248 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/image/pim-glovo/69e665cc1037b695a69bb457.jpg` |
| 2 | Batata Frita Lisa Clássica Continente (170 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/050e71c3-ac7a-493a.jpg` |
| 3 | BAT.FRITA LISA LAY'S MATUTANO 45GR | Batatas Fritas e Snacks | `glovo.dhmedia.io/image/pim-glovo/64d0f6e469bece3bf4cf5a14.jpeg` |
| 4 | Batata Frita Lisa Continente (200 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/6b44a575-2bd4-46cf.jpg` |
| 5 | Batata Frita Gourmet Original Lay's (170 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/c6b07a3c-94fb-439e.png` |
| 6 | Batata Frita Ondulada Pack Poupança Continente (250 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/13100785-740f-4bb9.jpg` |
| 7 | Batata Frita Ondulada Sal Ruffles (160 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/a39160f2-8f1e-49c4.png` |
| 8 | Batata Frita Churrasqueira Continente (2×300 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/image/pim-glovo/69e665ab1037b695a69ba0b8.jpg` |
| 9 | Batata Doce Frita Continente (150 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/...sw/31a2c2b4-6cd1-4646.jpg` |
| 10 | Snacks Batata Mystery Flavour Pringles (165 gr) | Batatas Fritas e Snacks | `glovo.dhmedia.io/image/pim-glovo/69bc436444aeffefa9c59b12.jpg` |

*Nota: todos da mesma categoria porque Fase 0 só validou 1 endpoint; na Fase 1 iteramos sobre ~100 categorias descobertas via SSR.*

## 6. Plano Fase 1 (NÃO executado — aguarda OK)

1. Walk no catálogo: `sections → categories → GRIDs → PRODUCT_TILEs` (rate-limit 4,5 s/request).
2. Para cada produto Glovo (por nome):
   - Buscar preço real no Continente.pt via M3 (`Product-Show?pid=` + JSON-LD).
   - Match por nome (lookup em `products` onde `retailer='continente'`).
3. UPDATE vs INSERT:
   - **Existe na BD** → `UPDATE products SET image_url, price, updated_at WHERE id=…` (sem mexer em nome/category).
   - **Não existe** → `INSERT products (..., needs_review=true, source='glovo-continente-guarda-2026-04-21', restaurant_id='continente-guarda')`.
4. **Zero duplicados:** `SELECT 1 FROM products WHERE retailer='continente' AND LOWER(name)=LOWER($1) LIMIT 1` antes de cada INSERT.
5. Logar cada decisão em `.claude/.ai/reports/glovo-continente-guarda-phase1.md`.

## 7. Estado

- ✅ Fase 0 completa
- ⏸  Fase 1 **aguarda OK do Danilo**
- 📦 BD: 0 escritas, 0 leituras (só análise de HTML/API)
