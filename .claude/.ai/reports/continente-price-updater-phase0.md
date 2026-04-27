# Continente Price Updater — FASE 0 (PROBE)

Data: 2026-04-21
Fonte: continente.pt (site público)
BD: Supabase `products` WHERE `restaurant_id='continente-guarda'` AND `is_available=true`

## 1. Resumo dos 4 métodos testados

| Método | Endpoint | Status | Veredicto |
|---|---|---|---|
| M1 SFCC Search-Show q=* | `/on/.../Search-Show?q=*&format=ajax` | 200 (HTML, 2.2 MB) | Devolve HTML, não JSON. Paginação por 48, teria de scrapar páginas; viável mas ineficiente |
| M1 SFCC Search-Show cgid | `/on/.../Search-Show?cgid=col-mercearia` | **500 Error** | Não funciona |
| M2 category SSR `/mercearia/` | `/mercearia/` | 200 (HTML, 2.2 MB) | Não expõe `__NEXT_DATA__`; apenas `product-tile` com JSON entity-encoded |
| M2 `/pesquisa/?q=<term>` | `/pesquisa/?q=leite` | 200 (84 tiles) | Viável como fallback por nome |
| M3 **Product-Show?pid=** | `/on/.../Product-Show?pid=<pid>` | **200 + JSON-LD com preço** | ✅ **VENCEDOR** — 100% coverage em 10/10, preço limpo |
| M4 `/api/products`, `/api/search`, `/graphql` | — | **410 Gone** | Endpoints removidos, não existem |

## 2. Método Vencedor — M3

**Endpoint:** `https://www.continente.pt/on/demandware.store/Sites-continente-Site/pt_PT/Product-Show?pid=<PID_7_DIGITOS>`

**Extracção:** bloco `<script type="application/ld+json">` contém schema.org `Product` com `offers.price` numérico.

**Exemplo de payload relevante:**
```json
{
  "@type": "Product",
  "name": "Gel de Banho Silk Velvet Dove",
  "offers": { "@type": "Offer", "price": 1.79, "priceCurrency": "EUR" }
}
```

**Vantagens:** endpoint directo, preço oficial actual, rápido (~1 resposta/produto), funciona com PID.

## 3. Cobertura estimada na BD

| Indicador | N.º |
|---|---|
| Total produtos Continente activos | **5.436** |
| Com `photo_url` com PID extraível (`/NNNNNNN-`) | 4.567 |
| Com `id` no formato `cnt-<pid>` | 1.796 |
| **Com PID derivável (união)** | **4.577** (84,2%) |
| Sem PID (requer fallback por nome via M2) | 859 (15,8%) |

## 4. Amostra real — 10 produtos (BD vs Site)

| PID | Nome | BD €  | Site € | Δ | Nota |
|---|---|---|---|---|---|
| 5597092 | Alfinetes de Segurança Prima | 2,7000 | 2,70 | 0,00 | igual |
| 2191365 | Requeijão de Vaca Santiago | 1,7900 | 1,79 | 0,00 | igual |
| 8020201 | Pera Rocha Desidratada Continente | 0,9949 | 0,99 | −0,01 | arredondamento |
| 7995354 | Puré Gato Creamy Catit | 2,9900 | 2,99 | 0,00 | igual |
| 8784447 | Laranja Citrinos IGP Algarve | 1,9900 | 1,99 | 0,00 | igual |
| 8114842 | Caju com Sal Continente | 2,7913 | 2,79 | −0,01 | arredondamento |
| 5148306 | Crepes com Chocolate Belga Continente | 3,4960 | 3,49 | −0,01 | arredondamento |
| 8719429 | Mr. Beast Pack 14 Figuras | 29,9900 | 29,99 | 0,00 | igual |
| 7848092 | Fish4Cats Atum com Anchova | 1,9900 | 1,99 | 0,00 | igual |
| 8063117 | **Gel de Banho Silk Velvet Dove** | **2,9900** | **1,79** | **−1,20** | ⬇️ **preço real mudou (promo/baixa)** |

**Resultado:** 10/10 encontrados • 3 com diferença ≤ €0,01 (arredondamento decimal na BD) • **1 com diferença real (€1,20)**.

## 5. Estratégia proposta para FASE 1

1. **Iterar 4.577 produtos com PID** via M3 (Product-Show + JSON-LD).
2. Rate limit: **3,5 s** entre requests → ~16 000 s (≈ 4,5 horas). Pode correr em background/batches de 200.
3. Aceitar diferenças **> €0,01** (ignorar arredondamentos de dígitos decimais).
4. Para os 859 sem PID: deixar para uma 2ª volta via `/pesquisa/?q=<nome_normalizado>` (matching por fuzzy).
5. Log de todas as mutações em `.claude/.ai/tmp/price_updates_continente.json` (id, nome, preço_antigo, preço_novo, timestamp).
6. UPDATE apenas no campo `price` (+ `last_updated`, `updated_at`). **Não tocar** em `pricing_service.dart`.
7. Parar imediatamente em 429/captcha.

## 6. STOP

Método vencedor identificado, amostra validada. **A aguardar OK do Danilo para iniciar FASE 1.**
