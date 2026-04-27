# Lojas Suportadas — Market Data Sync

Lista de lojas com fontes de catálogo (imagens) e fontes de preço (oficial).

---

## Glovo Guarda

| Loja | source_store_id (Glovo) | restaurant_id (BD) | Fonte de preço |
|------|------------------------|---------------------|----------------|
| Continente | `continente-grd1` | `<a definir>` | continente.pt (M3) |
| Pingo Doce | `pingo-doce-grd1` | `<a definir>` | pingodoce.pt |
| Auchan | `auchan-grd1` | `<a definir>` | auchan.pt |

URL Glovo: `https://glovoapp.com/pt/pt/guarda/<source_store_id>/`

---

## Uber Eats Guarda

| Loja | URL Uber | restaurant_id (BD) | Fonte de preço |
|------|----------|---------------------|----------------|
| Continente | `https://www.ubereats.com/pt/store/continente-guarda/...` | `<a definir>` | continente.pt (M3) |
| Pingo Doce | `https://www.ubereats.com/pt/store/pingo-doce-guarda/...` | `<a definir>` | pingodoce.pt |

---

## Métodos de Preço (sites oficiais)

### Continente — Método **M3** (CONFIRMADO ✅)
- Endpoint: `https://www.continente.pt/on/demandware.store/Sites-continente-Site/default/Search-UpdateGrid`
- Query string: `?q=<name>&start=0&sz=12`
- Headers necessários: `User-Agent` realista + cookie de sessão (extraído pela extensão Chrome).
- Selector preço: `.pwc-tile--price-primary` (em centavos × 100).
- Rate limit: **4,5s ± 1s jitter**.
- Confirmado em: continente-price-updater-phase1-final.md

### Pingo Doce
- Endpoint: `https://www.pingodoce.pt/wp-json/wp/v2/produto?search=<name>`
- Selector preço: campo `price` no JSON (em €).
- Rate limit: 4,5s ± jitter.
- Status: **a validar com extensão Chrome**.

### Auchan
- Endpoint: `https://www.auchan.pt/pt/search?q=<name>`
- Selector preço: `.product-price .value` (HTML).
- Rate limit: 4,5s ± jitter.
- Status: **a validar com extensão Chrome**.

### Mercadona
- Endpoint: `https://tienda.mercadona.es/api/v1.1/categories/?lang=pt&wh=mad1`
- Nota: Mercadona Portugal usa o catálogo de Espanha — preços em €.
- Selector preço: `unit_price` no JSON.
- Rate limit: 4,5s ± jitter.
- Status: **a validar**.

### Lidl
- Endpoint: `https://www.lidl.pt/q/query/<name>`
- Selector preço: `.m-price__price`.
- Rate limit: 4,5s ± jitter.
- Status: **scraper PT já existe** — ver lidl-scraper-pt-report.md.

### Intermarché
- Endpoint: `https://www.intermarche.pt/produtos/search?q=<name>`
- Selector preço: `.price-tag .integer` + `.decimal`.
- Rate limit: 4,5s ± jitter.
- Status: **a validar**.

---

## Tipos de Loja Suportados

| Tipo | Exemplos | Notas |
|------|----------|-------|
| Supermercado | Continente, Pingo Doce, Auchan, Lidl, Mercadona, Intermarché | Preço sempre do site oficial |
| Farmácia | Wells, Holon, Sá da Bandeira | Preço do site oficial (se existir) ou manual |
| Restaurante | Pizzarias, kebabs, locais | Preço do menu oficial / app própria / manual |

Para tipos sem site oficial (restaurantes pequenos), usar `price_source = manual` e introduzir preços via painel admin.

---

## Como Adicionar uma Nova Loja

1. Adicionar linha à tabela apropriada acima (Glovo / Uber / Outras).
2. Confirmar `restaurant_id` existe na tabela `restaurants` da BD Bora.
3. Documentar método de preço (endpoint, selector, rate limit) numa nova secção.
4. Validar com extensão Chrome em modo manual (1 produto) antes de scraping em massa.
5. Pedir aprovação do Danilo antes do primeiro sync completo.
