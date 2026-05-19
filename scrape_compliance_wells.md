# scrape_compliance_wells.md

**Sessão Autónoma 2026-05-19 · Wells (farmácia)**

## robots.txt — wells.pt (verificado 2026-05-19)

**Fonte:** https://www.wells.pt/robots.txt (redirect → https://wells.pt/robots.txt)
**Sitemap:** https://wells.pt/sitemap_index.xml

### User-agent: *

**Disallow (paths bloqueados — NÃO usados):**
- `/*prefn*`, `/*prefv*`, `/*pmin`, `/*pmax` — filtros de preço/preferências
- `/carrinho/`, `/checkout*`, `/conta/` — transação/conta
- `*view=grid*`, `*view=list*`
- `/quickview*`, `/*Product-ShowQuickView`
- `/*Search-UpdateGrid`, `/*Analytics-Start`, `/*Product-Variation`
- `/*?utm*`, `/*?bundleReferral=`
- `/on/demandware.static/-/Sites-Wells-Library/*.pdf`
- `/resultados-pesquisa-wells*`, `/natal.html`

**Allow:** Implicitamente tudo o resto (não há `Allow:` explícito).

### Nossa abordagem (compliant)

✅ **Usamos APENAS** `sitemap_0-product.xml` (sitemap público) + GET aos URLs de produto canónicos (não bloqueados).

❌ **NÃO usamos:**
- `/Search-UpdateGrid` (proibido) → embora seja a forma natural de paginar SFCC
- `/quickview` (proibido)
- Filtros `?prefn=`/`?prefv=` (proibidos)
- Qualquer endpoint de checkout/conta

### Rate limit

1 request/seg em média (sleep 1000-1400ms entre fetches) — alinhado com §27.5 business_rules ("Máximo 1 pedido por segundo por mercado/host").

### Plataforma

Salesforce Commerce Cloud (SFCC/Demandware). Páginas Product-Show retornam HTML completo com:
- `<script type="application/ld+json">{ "@type": "Product", ... }</script>` — schema completo
- Meta tags `og:title`, `og:description`, `og:image`
- Imagens em `wells.pt/dw/image/v2/BFLP_PRD/...` (CDN Demandware)

## Glovo

- robots.txt: `User-agent: *` → `Allow: /` (PetalBot único bloqueado)
- **`https://glovoapp.com/pt/pt/guarda/wells-guarda/` retorna 503** — bloqueado por Cloudflare/anti-bot mesmo com user-agent realista
- **Decisão:** não usar Glovo como fonte primária para Wells. O sitemap oficial dá catálogo completo (8596 produtos). Glovo seria útil para curadoria mas a sua API/site nega acesso a scrapers HTTP-only.
- **Fallback futuro:** Playwright stealth se necessário para curadoria; por agora, lista oficial Wells é suficiente.

## Uber Eats

- Não testado nesta sessão (Glovo é a referência prioritária da brief).
- Pode ser usado como cross-check posterior.

## Compliance status: ✅ APROVADO

Não fazemos requests a endpoints bloqueados pelo robots.txt. Rate limit respeitado. Sitemap é mecanismo público padrão de descoberta.
