# FONTES DE DADOS POR MERCADO

## 1. MERCADONA (FONTE PRINCIPAL)
- API: https://tienda.mercadona.es/api/categories/
- Subcategorias: https://tienda.mercadona.es/api/categories/{id}/
- Estrutura: response.categories[].products[]
- Campos: display_name, price_instructions.bulk_price, thumbnail, packaging
- CDN: https://prod-mercadona.imgix.net/images/{hash}.jpg?fit=crop&h=300&w=300
- IDs subcategorias: 112,115,116,117,156,163,158,159,161,162,135,133,132,118,121,120,89,95,92,97,90,216,219,218,217,164,166,181,174,168,170,173,171,169,86,81,83,84,88,46,38,47,37,42,43,44,40,45,78,80,79,48,52,49,51,50,58,54,56,53,147,148,154,155,150,149,151,884,152,145,122,123,127,130,129,126,201,199,203,202,192,189,185,191,188,187,186,190,194,196,198,213,214,27,28,29,77,72,75,226,237,241,234,235,233,231,230,232,229,243,238,239,244,206,207,208,210,212,32,34,31,36,222,221,225,65,66,69,59,60,62,64,68,71,897,138,140,142,105,110,111,106,103,109,108,104,107,99,100,143,98
- API pública, sem autenticação. Preços EUR iguais a Portugal.

## 2. CONTINENTE
- CDN: https://www.continente.pt/dw/image/v2/BDVS_PRD/on/demandware.static/-/Sites-col-master-catalog/default/{hash}/images/col/{dir}/{code}-frente.jpg?sw=280&sh=280
- Pesquisa: https://www.continente.pt/pesquisa/?q=NOME
- Plataforma: Demandware. Hash único por produto, precisa scraping.

## 3. PINGO DOCE
- CDN: https://www.pingodoce.pt/dw/image/v2/...
- Pesquisa: https://www.pingodoce.pt/pesquisa/?q=NOME
- Maioria via cross-match com Mercadona/Continente.

## 4. LIDL
- Pesquisa: https://www.lidl.pt/q/search?q=NOME
- Marcas próprias: Milbona, Combino, Cien, Lupilu
- Protegido por Cloudflare. Usa cross-match.

## 5. AUCHAN
- CDN: https://www.auchan.pt/dw/image/v2/...
- Pesquisa: https://www.auchan.pt/pesquisa?q=NOME
- Demandware. Usa cross-match.

## 6. INTERMARCHÉ
- Site difícil de aceder. Usa cross-match.

## MAPA CATEGORIAS ES→PT
Aceite/Arroz/Pasta/Conservas/Salsas → Mercearia
Agua/Refrescos/Cerveza/Vino/Café/Zumo → Bebidas
Aperitivos/Patatas/Frutos secos → Snacks
Chocolate/Caramelos → Chocolates e Doces
Bebé/Infantil → Bebé
Carne/Pollo/Ternera/Cerdo → Carne
Pescado/Marisco → Peixe
Congelados → Congelados
Detergentes/Limpieza → Limpeza
Fruta → Frutas
Verdura/Hortaliza → Legumes
Higiene/Jabón/Desodorante → Higiene
Lácteos/Leche/Yogur → Laticínios
Queso/Embutidos/Jamón → Charcutaria
Mascotas → Animais
Pan/Bollería/Galletas → Padaria
