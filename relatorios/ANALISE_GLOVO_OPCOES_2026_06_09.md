# Análise Glovo vs Bora — Opções de Produtos (4 restaurantes)
### FASE 1 — SÓ ANÁLISE · 2026-06-09

> ⚠️ **MODO PROTECÇÃO TOTAL.** Este documento é **só leitura/relatório**. NÃO foi alterado código, NÃO foi alterada a DB, NÃO foi feito commit. Validado por `prompt-blindado-validator` (Bloco 1 com ressalva: a Fase 1 não inclui `git push`/`/ctx` por ser read-only — exigido pelo próprio prompt).
>
> **Quem decide a seguir:** Claude.ai + Danilo aprovam este relatório antes de qualquer Fase 2 (implementação).

---

## 0. TL;DR (para decisão rápida)

1. **O problema confirma-se:** McDonald's, Burger King e KFC têm **0 grupos de opções / 0 items** na Bora. O cliente não consegue escolher bebida, acompanhamento, molhos, extras nem tamanho. Só o **Sabores Açaí** tem opções (e ainda incompletas).
2. **A boa notícia:** a app **JÁ TEM** o sistema de opções a funcionar (modelo + UI cliente + UI parceiro + carrinho). A UI do cliente já suporta obrigatório/opcional, escolha única e múltipla, mín/máx e acréscimo de preço (`+€`). **Isto é essencialmente um problema de DADOS, não de UI.**
3. **A má notícia:** a Glovo mudou a API (v3 morreu). Foi preciso mudar de método (ler a página SSR da Glovo) — o crawler antigo `.ai_mcd_deep_crawler.js` está **partido** e tem de ser actualizado.
4. **Volume a inserir (3 fast-food):** **~1418 grupos + ~9887 items** se for inserção "ingénua" (1 cópia por produto). Com modelo de **templates reutilizáveis** desce para **~1262 definições distintas** (KFC sozinho colapsa de 6335 → 348 items, 18×).
5. **2 decisões de arquitectura** que o Danilo/Claude.ai têm de tomar antes da Fase 2 (ver §6): **(A)** tamanho como grupo vs. como produto-variante (conflito no McDonald's); **(B)** inserção ingénua vs. templates partilhados.

| Loja | Bora hoje (grupos/items) | Glovo (produtos c/ opção) | Falta inserir (grupos / items, ingénuo) |
|---|---:|---:|---:|
| McDonald's | 0 / 0 | 92 | ~333 / ~1379 |
| Burger King | 0 / 0 | 121 | ~381 / ~2173 |
| KFC | 0 / 0 | 143 | ~704 / ~6335 |
| Sabores Açaí | 8 / 80 | (não está na Glovo) | re-categorizar + confirmar com o dono |
| **TOTAL fast-food** | **0 / 0** | **356** | **~1418 / ~9887** |

---

## 1. Método e achado de infra-estrutura (IMPORTANTE)

### 1.1 A API v3 da Glovo morreu
Todos os endpoints do crawler antigo devolvem **404 "page not found"**:
- `GET /v3/stores/215649/addresses/346436/content` → **404**
- `GET /v3/stores/215649/addresses/346436/products/{id}` → **404**

A nova API é **v4** e exige um header novo:
- `GET /v3/stores/{id}` → **400** `Required request header 'Glovo-Perseus-Session-Id' is missing`
- Endpoint de menu actual: `GET /v4/stores/{store}/addresses/{addr}/content/main?nodeType=DEEP_LINK&link={categoria-slug}` (ex.: `link=bebidas-c.3004712557`).
- **Problema:** mesmo com o header `Glovo-Perseus-Session-Id` (UUID gerado), o endpoint v4 **pendura/timeout** para clientes não-browser (provável anti-bot). Não foi possível usá-lo de forma fiável.

### 1.2 Solução usada: ler a página SSR da Glovo
A página web da loja (`https://glovoapp.com/pt/pt/guarda/stores/{slug}`) é renderizada no servidor (React/Next streaming) e **traz o menu inteiro embebido em JSON** — incluindo `attributeGroups` completos (não só tamanho). 1 pedido por loja, fiável, sem rate-limit agressivo. Foi este o método usado para todo este relatório.

- Confirmado: um McMenu traz **10 grupos** inline (Tamanho, Bebida ×9 items, Acompanhamento ×4, Molho ×7, Complemento ×6, etc.).

> 🐞 **Bug/dívida de infra a registar:** `.ai_mcd_deep_crawler.js` (e por extensão qualquer skill que dependa da API v3 da Glovo, p.ex. `market-data-sync`) está **obsoleto**. Para a Fase 2 (e futuros scrapes Glovo) usar o **parser SSR-HTML** validado nesta sessão. NÃO foi commitado nada — é só registo.

### 1.3 Lojas e IDs confirmados (Supabase)
| Loja | `restaurants.id` | `is_partner` | Slug Glovo |
|---|---|---|---|
| McDonald's | `mcdonalds-guarda` | false | `mcdonalds-grd` (store 215649 / addr 346436) |
| Burger King | `burgerking-guarda` | false | `burger-king-grd` (store 279991 / addr 427202) |
| KFC | `kfc-guarda` | false | `kfc-grd` (store 363080 / addr 538047) |
| Sabores de Casa Açaí | `12aa2cbb-01bd-443b-a17e-633c169d4864` | **true** | — (não Glovo) |
| ~~Pizza Hut~~ | `pizzahut-guarda` | false | **EXCLUÍDA** (stop rule + `is_active_admin=false`) |

### 1.4 Esquema actual da DB (sem alterações)
- `product_option_groups`: `id, product_id, name, description, is_required, min_choices, max_choices, sort_order` — **um grupo pertence a UM produto** (1:N).
- `product_option_items`: `id, group_id, name, price_add, is_available, sort_order`.
- UI cliente (`lib/screens/product_detail_screen.dart`) lê por `product_id` e renderiza. **Capacidades já existentes:** obrigatório/opcional, escolha única e múltipla, mín/máx (botão "Adicionar" bloqueado até `min` cumprido), acréscimo de preço (`+€`). **Não suporta:** grupos condicionais/dependentes; e esconde grupos se o produto tiver `variants` (linha 173).

---

## 2. McDonald's — `mcdonalds-guarda`

### 2.1 Visão geral
| Métrica | Glovo (distinto) | Bora hoje | Falta |
|---|---:|---:|---:|
| Produtos | 107 | 138 *(ver anomalia §7.1)* | — |
| Produtos com opções | 92 | 0 | 92 |
| Grupos de opções (ingénuo) | 333 | 0 | **~333** |
| Items de opção (ingénuo) | 1379 | 0 | **~1379** |
| Definições distintas (grupo×item) | 321 | 0 | ~321 |

**Categorias Glovo (12):** Mais vendidos · Novidades · Sanduíches e McMenu · Happy Meal · Saco de transporte · Sobremesas · Saladas/Veggies & outros · Europoupança · Acompanhamentos e Molhos · Bebidas · Sanduíche individual · Items individuais.

### 2.2 Blocos canónicos (reutilizados em quase todos os McMenu)
- **🔴 Selecione o Tamanho** *(obrig, 1)*: Médio (+€0,00) · Grande (+€1,90)
- **🔴 Selecione a sua bebida** *(obrig, 1 de 9)*: Coca-Cola Zero, Coca-Cola, Fanta Laranja Zero, Sumol Ananás, Fuze Tea Pêssego Hibisco Zero, Água 0,5L, Compal Laranja do Algarve, Compal Manga/Laranja, Compal Pêssego (todos +€0,00)
- **🔴 Selecione o seu acompanhamento** *(obrig, 1 de 4)*: Batata · Salada Mista · Creme Cenoura · Sopa Caldo Verde (+€0,00)
- **🔴 Deseja adicionar um molho?** *(obrig, 1 de 7)*: Ketchup (+€0,10) · Molho FIFA Big Mac (+€1,15) · Molho Batatas (+€1,15) · Maionese e Alho (+€1,15) · Agridoce (+€1,15) · Barbecue (+€1,15) · Sem molho
- **🔴 Deseja adicionar um complemento?** *(obrig, 1 de 6)*: Cheeseburger (+€3,00) · Chicken Wings 3 (+€3,10) · Chicken Delights (+€3,60) · McNuggets 4 (+€3,20) · Snack Wrap Chicken Cheese (+€3,70) · Não, obrigado!
- **⚪ Deseja adicionar Ketchup?** *(opc, 0-1)*: Ketchup (+€0,10) · Sem Ketchup
- **⚪ Sem [Sanduíche]** *(opc, 0-N)* e **⚪ Extra [Sanduíche]** *(opc, 0-N)*: por sanduíche — Extra Queijo (+€1,10), Extra Bacon (+€1,40), Extra Tomate (+€1,10), Extra Alface (+€1,10), etc. *(grupos específicos por produto, não reutilizáveis)*

### 2.3 Produtos representativos (fluxo Glovo → Bora → GAP)

**📦 McMenu® Big Mac® — €7,90 — Glovo: 8 grupos / 36 items**
- Na Glovo, o cliente escolhe: Tamanho → Bebida → Acompanhamento → Molho → Complemento → (opc) Ketchup → (opc) Sem Big Mac (Sem Alface/Queijo/Molho/Pickles/Cebola) → (opc) Extra Big Mac (Extra Queijo +€1,10).
- **Na Bora hoje:** 0 grupos. Cliente adiciona o "McMenu Big Mac" ao carrinho **sem escolher nada**.
- **GAP:** 8 grupos / 36 items (5 obrigatórios + 3 opcionais).

**📦 McMenu® 2 Snack Wraps — €8,25 — Glovo: 10 grupos / 38 items** *(o mais complexo)*
- Tamanho · Selecione Snack Wrap 1 (Chicken Cheese/Mayo) · Selecione Snack Wrap 2 · Bebida ×9 · Acompanhamento ×4 · Molho ×7 · Complemento ×6 · (opc) Ketchup.
- **GAP:** 10 grupos / 38 items. *(Tem grupos repetidos "Selecione o seu Snack Wrap" — ver nota de grupos condicionais §6.3.)*

**📦 Menu para 2 Chicken Share Box — €15,20 — Glovo: 9 grupos / 49 items**
- 2× Bebida, 2× Acompanhamento, 2× Molho (porque é menu para 2) + complementos.
- **GAP:** 9 grupos / 49 items. *(Duplicação de grupos = menu para 2 pessoas.)*

**📦 McMenu McPrego — €7,80 — Glovo: 9 grupos / 38 items**
- Tamanho · **Oferta de Mostarda?** (Molho Mostarda/Sem) · Bebida · Acompanhamento · Molho · Complemento · (opc) Ketchup · (opc) Sem McPrego (Sem Molho/Cebola) · (opc) Extra McPrego (Extra Alface/Queijo/Tomate +€1,10, Extra Bacon +€1,40).
- **GAP:** 9 grupos / 38 items.

**Outros representativos confirmados (mesmo padrão de blocos canónicos):** McMenu® McPrego com ovo (9g/39i) · McMenu® McBifana à Cervejeira (9g/37i) · McMenu® CBO® (8g/38i) · Menu McCrispy Spicy Cajun (8g/36i) · McMenu® McCrispy BBQ & Bacon (8g/38i) · McMenu Big Arch (8g/37i) · McMenu® Big Tasty® Double (8g/38i).

### 2.4 Resumo McDonald's
| | Glovo | Bora | Falta |
|---|---:|---:|---:|
| Grupos | 333 | 0 | **333** |
| Items | 1379 | 0 | **1379** |
| Distintos (grupo×item) | 321 | 0 | ~321 |

---

## 3. Burger King — `burgerking-guarda`

### 3.1 Visão geral
| Métrica | Glovo (distinto) | Bora hoje | Falta |
|---|---:|---:|---:|
| Produtos | 168 | 173 *(ver §7.1)* | — |
| Produtos com opções | 121 | 0 | 121 |
| Grupos (ingénuo) | 381 | 0 | **~381** |
| Items (ingénuo) | 2173 | 0 | **~2173** |
| Definições distintas (grupo×item) | 593 | 0 | ~593 |

### 3.2 Blocos canónicos (estrutura BK ≠ McDonald's)
> ⚠️ **O BK NÃO usa grupo de "Tamanho".** O menu é: carne (fixa) + acompanhamento + bebida + remover ingredientes + extras.
- **🔴 Carne** *(obrig, normalmente 1 fixo)*: ex. Whopper®.
- **🔴 Acompanhamentos** *(obrig, 1 de ~6-9)*: King Aros de Cebola x10 · Batatas Clássicas · Batatas Clássicas King Mix (+€0,60) · Batatas Supreme · King Fries (+€1,00) · King Supreme (+€1,00) · Cowboy King Fries (+€1,00)…
- **🔴 Bebidas** *(obrig, 1 de 13-15)*: Coca-Cola (+€0,10) · Coca-Cola Zero (+€0,10) · Sprite Zero (+€0,10) · Fanta Laranja (+€0,10) · Fanta Guaraná (+€0,10) · Fuze Tea (+€0,10) · Compal Laranja do Algarve (€0,00) · Compal Pêssego · Compal Tutti Frutti · Água (+€0,10) · Cerveja c/álcool (+€0,10) · Cerveja s/álcool (+€0,10) · Monster Energy (+€0,60) · Monster Ultra White (+€0,60) · Monster Mango Loco (+€0,60).
- **⚪ Remover ingredientes [sanduíche]** *(opc, 0-N)*: SIN Maionese/Picles/Cebola/Alface/Ketchup/Tomate… (€0,00).
- **⚪ Adiciona extras [sanduíche]** *(opc, 0-N)*: EXTRA Bacon+Queijo (+€2,00) · EXTRA Bacon (+€1,10) · EXTRA Queijo (+€0,90) · EXTRA Carne Whopper (+€2,60) · EXTRA Maionese/Picles/Cebola/Alface/Ketchup/Tomate (€0,00).

### 3.3 Produtos representativos

**📦 Menu Whopper® — €9,50 — Glovo: 5 grupos / 41 items**
- Carne (Whopper) · Acompanhamentos ×9 · Bebidas ×15 · (opc) Remover ingredientes Whopper ×6 · (opc) Adiciona extras Whopper ×10.
- **Na Bora hoje:** 0. **GAP:** 5 grupos / 41 items.

**📦 Menu Long Chicken + 10 Anéis de Cebola — €15,55 — Glovo: 6 grupos / 29 items**
- Carne (Long Chicken) · Acompanhamentos ×5 · Bebidas ×15 · Aros (fixo) · (opc) Remover ×2 · (opc) Extras ×5.
- **GAP:** 6 grupos / 29 items.

**📦 2 Whopper + 2 batatas + Nuggets x5 — €27,80 — Glovo: 7 grupos / 21 items**
- Carne 1 · Carne 2 · Acompanhamento 1 · Acompanhamento 2 · Complementos (Nuggets x5) · (opc) Remover Whopper ×6 · (opc) Extras Whopper ×10. *(Menu família = grupos duplicados.)*
- **GAP:** 7 grupos / 21 items.

**Outros representativos confirmados (mesmo padrão):** Menu Double Duo Bacon Cheddar (5g/37i) · Double Cowboy Menu (5g/27i) · Cowboy Double Crispy Chicken Menu (5g/26i) · Double Tuga Whopper® com Chouriço Menu (5g/39i) · Double Tuga Whopper® Menu (5g/38i) · Cowboy Menu (5g/27i) · Cowboy Crispy Chicken Menu (5g/26i) · Tuga Long Chicken® com Chouriço Menu (5g/30i) · Tuga Long Chicken® Menu (5g/29i).

### 3.4 Resumo Burger King
| | Glovo | Bora | Falta |
|---|---:|---:|---:|
| Grupos | 381 | 0 | **381** |
| Items | 2173 | 0 | **2173** |
| Distintos (grupo×item) | 593 | 0 | ~593 |

---

## 4. KFC — `kfc-guarda`

### 4.1 Visão geral
| Métrica | Glovo (distinto) | Bora hoje | Falta |
|---|---:|---:|---:|
| Produtos | 174 | 176 *(ver §7.1)* | — |
| Produtos com opções | 143 | 0 | 143 |
| Grupos (ingénuo) | 704 | 0 | **~704** |
| Items (ingénuo) | **6335** | 0 | **~6335** |
| Definições distintas (grupo×item) | 348 | 0 | ~348 |

> 🔑 **KFC é o caso extremo da repetição:** os menus são combos enormes (até **16 grupos** num só produto) e **cada menu repete** as mesmas listas gigantes (sobremesas ×26, bebidas ×13, molhos ×9, "ainda tem espaço" ×9). Por isso 6335 items "ingénuos" colapsam para **348** definições distintas (**18× menos**). É o argumento mais forte para o modelo de templates (§6.2).

### 4.2 Blocos canónicos (muito reutilizados)
- **🔴 Escolha a Sanduíche** *(obrig, 1 de 4-5)*: [família] Receita Original · Zinger (Picante) · Double Original (+€3,40) · Double Zinger (+€3,40) [+ Wrap nalguns].
- **🔴/N Escolha o Acompanhamento** *(obrig, 1 ou N de 9)*: Batata Palitos · Arroz · Salada Snack · ½ Maçaroca · Batata Grande (+€0,85) · Kentucky Fries BBQ Bacon/O'Cheddar/Coronel/Ruffles (+€2,95).
- **🔴/N Escolha a Bebida** *(obrig, 1 ou N de 12-13)*: Água 33cl · Água sem Gás 50cl (+€0,60) · 7Up · Cerveja · Ice Tea Manga · Sumol Ananás · Sumol Laranja · Néctar Laranja/Manga · Néctar Pêssego · Bongo 8 Frutos · Red Bull / Zero / Tropical (+€1,00).
- **⚪ Ingredientes Extra (não se fazem trocas)** *(opc, 0-8)*: Extra Bacon (+€1,40) · Extra Queijo (+€1,10) · Extra Batata Crocante (+€1,20) · Extra Pepino (+€0,75) · Sem Maionese/Alface/Tomate…
- **⚪ Pretende uma sobremesa?** *(opc, 0-4, **26 items**)*: Gelatina (+€1,95) · 4 Profiteroles (+€2,55) · Kream ×6 (+€3,50) · Sundae ×12 (+€2,80) · Shake ×7 (+€3,95).
- **⚪ Pretende um molho?** *(opc, 0-10, 9)*: DIP Maionese/Maionese Alho/Hot Chilli/Barbecue/O'Cheddar/Coronel (+€1,15) · Ketchup (+€0,05) · Molho O'Cheddar XXL (+€2,99) · Molho BBQ XXL (+€2,99).
- **⚪ Ainda tem espaço?** *(opc, 0-4, 9)* · **⚪ Talheres** *(opc, 0-6, 2)*: Faca+Garfo (+€0,20) · Colher Sobremesa (+€0,10).

### 4.3 Produtos representativos

**📦 Box Meal Coronel — €13,20 — Glovo: 9 grupos / 87 items** *(o "menu individual" típico)*
- Sanduíche ×5 · (opc) Ingredientes Extra ×9 · Acompanhamento ×9 · Complemento ×7 · Bebida ×13 · Molho ×7 · (opc) Sobremesa ×26 · (opc) Ainda tem espaço ×9 · (opc) Talheres ×2.
- **Na Bora hoje:** 0. **GAP:** 9 grupos / 87 items.

**📦 Menu Kids + Menu Kentucky + Menu Clássica — €24,95 — Glovo: 16 grupos / 130 items** *(o mais complexo de todos)*
- Combo de 3 menus: 2 sanduíches adultos (cada um com sanduíche + extras + acompanhamento + bebida) + 1 menu infantil (opção + acompanhamento + bebida) + sobremesa + molho + talheres.
- **GAP:** 16 grupos / 130 items. *(Grupos repetidos por sub-menu — ver §6.3.)*

**📦 Super Bucket Para 4 — €49,95 — Glovo: 15 grupos / 111 items**
- Super Chick&Share ×4 · 2 Wraps (cada c/ extras) · 2 Kentucky BBQ Single (cada c/ extras) · **Escolha 4 Acompanhamentos** (4-4) · **Escolha 4 Bebidas** (4-4) · sobremesa · molho · talheres.
- **GAP:** 15 grupos / 111 items. *(Repare nos grupos `min=max=4` — escolha múltipla obrigatória; a UI Bora já suporta isto.)*

**Outros representativos confirmados:** Menu Kids + Menu Kentucky (12g/97i) · Super Bucket para 2 (11g/90i) · Combo O'Cheddar Para 2 (10g/59i) · Box Meal Tosta Mista (10g/85i) · Box Meal Fully Loaded (10g/83i) · Menu Duplo Coronel (10g/96i) · Menu Duplo Clássica (10g/92i) · Box Meal Mix (9g/77i) · Box Meal Kentucky BBQ (9g/87i).

### 4.4 Resumo KFC
| | Glovo | Bora | Falta |
|---|---:|---:|---:|
| Grupos | 704 | 0 | **704** |
| Items | 6335 | 0 | **6335** |
| Distintos (grupo×item) | 348 | 0 | ~348 |

---

## 5. Sabores de Casa Açaí — `12aa2cbb-…` (PARCEIRO, não-Glovo)

### 5.1 Estado actual (Supabase)
11 produtos. Só os **4 "Copo"** têm opções; cada um tem **exactamente 2 grupos** (total 8 grupos / 80 items):

| Produto | Preço | G1 "Escolha os Acompanhamentos" (obrig) | G2 "Deseja Extras?" (opc) |
|---|---:|---|---|
| Copo Pequeno 250ml | €3,50 | mín=máx **2** | 0-10 (+€1 cada) |
| Copo Médio 330ml | €5,00 | mín=máx **3** | 0-10 (+€1 cada) |
| Copo Grande | €8,00 | mín=máx **4** | 0-10 (+€1 cada) |
| Copo Mega 500ml | €12,00 | mín=máx **5** | 0-10 (+€1 cada) |

- **Lista única de 10 items** (igual nos dois grupos): Leite Condensado · Amendoim · Leite em Pó · Granola · Mel · Creme de Avelã · Paçoca · Banana · Morango · Kiwi.
- **7 produtos sem opções:** Água, Pepsi, Guaraná Antarctica, Paçoca Moreninha do Rio, Goma Jujuba Gomets, Saco, **"Em breve…"** (€0,01 — placeholder, ver §7.4).

### 5.2 GAP vs. açaí "completo"
O modelo actual (tamanho via produto + N toppings grátis + extras a €1) é **funcional e bem montado**, mas a lista é **genérica e curta**: mistura frutas, granolas e caldas num só grupo, e **faltam toppings standard** da indústria. Benchmark (Oakberry, Açaí Brasil, Mr. Bey Açaí — categorias típicas, **a confirmar com o menu real do estabelecimento**):

| Categoria | Tem hoje | Faltam tipicamente |
|---|---|---|
| **Frutas** | Banana, Morango, Kiwi | Manga, Maracujá, Abacaxi, Uva, Mirtilo |
| **Cereais/Granolas** | Granola, Paçoca, Leite em Pó | Aveia, Sucrilhos/Corn Flakes, Flocos |
| **Caldas/Líquidos** | Leite Condensado, Mel, Creme de Avelã | Nutella, Leite Ninho líquido, Calda Choco, Calda Morango |
| **Doces/Complementos** | Amendoim | M&M's, KitKat triturado, Oreo, Choco Granulado, Bis, Confete |
| **Frutas secas** | — (nenhuma) | Coco Ralado, Uva Passa, Castanha de Caju |

> ⚠️ **Stop rule respeitada (não inventar):** a lista acima é **benchmark da indústria**, não factos do Sabores de Casa Açaí. **Recomendação:** como é um **parceiro real**, pedir ao dono a lista verdadeira de toppings + preços e a estrutura de grupos pretendida. Só depois categorizar (ex.: 4-5 grupos: Frutas / Cereais / Caldas / Doces / Extras pagos).

### 5.3 Gap estimado Açaí
- Re-categorizar a lista única em 4-5 grupos por copo (4 copos) → ~16-20 grupos.
- Expandir de 10 → ~25-40 items (×4 copos no modelo ingénuo) **OU** usar templates (1 lista partilhada pelos 4 copos).
- Decidir se "Água/Pepsi/Guaraná/Paçoca/Goma" ficam como produtos avulsos (provavelmente sim).

---

## 6. Achados de arquitectura (DECISÕES para a Fase 2)

### 6.1 A UI já existe — isto é sobretudo um problema de DADOS ✅
`lib/screens/product_detail_screen.dart` (776 linhas) **já renderiza** grupos de opção com: obrigatório/opcional, escolha única e múltipla, mín/máx (botão "Adicionar" bloqueado até `min`), e acréscimo de preço (`+€`, somado ao total). O carrinho (`cart_item.dart`) já carrega `selectedOptions`. Existe também UI de gestão para parceiro/admin (`product_options_manage_screen.dart`). **→ Não é preciso reescrever UI para o caso comum.**

### 6.2 DECISÃO A — Inserção ingénua vs. Templates partilhados
O esquema actual liga cada grupo a **um** `product_id`. Para replicar a Glovo "tal e qual":

| | **Ingénuo (sem mudar schema)** | **Templates (mudar schema)** |
|---|---|---|
| Linhas a inserir (3 lojas) | ~1418 grupos + **~9887 items** (~11,3k linhas) | ~1262 definições distintas + tabela de ligação |
| Schema/UI | **Zero alterações** (UI já lê por `product_id`) | Migration + alterar modelo Flutter (Validation Gate: DB) |
| Manutenção | Mudar 1 bebida = editar em ~40 sítios (KFC) | Editar 1 vez, propaga |
| Velocidade p/ lançar | **Rápido** | Mais lento |
| Recomendação | ✅ **Para lançar** (e talvez só top-N) | 🔵 Optimização **pós-lançamento** |

### 6.3 DECISÃO B — Tamanho: grupo vs. produto-variante (conflito McDonald's) 🚨
- O McDonald's tem **27 produtos com sufixo "(Médio)/(Grande)"** na Bora — o crawler antigo **expandiu o tamanho em produtos separados**.
- A Glovo modela tamanho como **grupo de opção** ("Selecione o Tamanho") num só produto (107 distintos vs 138 na Bora).
- A UI Bora **esconde grupos se o produto tiver `variants`** (linha 173). Se importarmos o grupo "Tamanho" da Glovo por cima dos produtos-variante, ficamos com **dupla modelação** (tamanho como produto **e** como grupo).
- **Decisão necessária:** (a) colapsar os 27 produtos-variante num só produto + grupo "Tamanho"; **ou** (b) manter produtos-variante e **remover** o grupo "Tamanho" dos dados Glovo na importação. *(BK e KFC não têm este problema — 0 sufixos de tamanho.)*

### 6.4 Grupos condicionais/dependentes (limitação de UI conhecida)
Combos grandes (McMenu 2 Snack Wraps; KFC "Kids+Kentucky+Clássica" com 16 grupos) têm grupos **repetidos/dependentes** da escolha anterior. A UI Bora **não** suporta condicionais — renderiza tudo em lista plana. **Para MVP é aceitável** (mostra todos os grupos seguidos). Refinar (condicionais) é pós-lançamento. Recomenda-se começar pelos **menus simples** (1 sanduíche) onde a lista plana é perfeita.

### 6.5 Cross-sell / upsell
"Quer adicionar?" / "Ainda tem espaço?" / "Pretende uma sobremesa?" — na Glovo são carrosséis de upsell; na API vêm como **grupos opcionais (0-N)**. Podem entrar como grupos opcionais (dados) sem UI nova. O efeito "carrossel pós-carrinho" é uma feature de UI separada (não bloqueia).

---

## 7. Bugs / anomalias encontradas (registo)

1. **§7.1 — Contagens Bora > Glovo:** McDonald's 138>107, BK 173>168, KFC 176>174.
   - McDonald's: a diferença (~31) ≈ os **27 produtos-variante de tamanho** + alguns. Confirma o ponto §6.3.
   - BK/KFC: diferença pequena (5, 2) — provavelmente produtos descontinuados/renomeados na Glovo ou duplicados de carrossel na Bora. **Recomenda-se reconciliação por nome normalizado na Fase 2** (qual produto Bora ↔ qual produto Glovo, para colar as opções no `product_id` certo).
2. **§7.2 — API v3 Glovo morta + v4 com anti-bot** (ver §1.1). Crawler antigo obsoleto.
3. **§7.3 — Repetição massiva de grupos** (KFC 6335→348). Não é bug, mas torna a inserção ingénua pesada e frágil de manter (§6.2).
4. **§7.4 — Açaí "Em breve…" (€0,01):** produto placeholder que está **encomendável**. Sugestão (pós-aprovação): `is_available=false` ou remover.
5. **§7.5 — Mapear produto Glovo → produto Bora:** o `product_id` da Bora pode não ser o `storeProductId` da Glovo (o crawler antigo prefixava/expandia). A Fase 2 precisa de um passo de **matching por nome normalizado** antes de inserir grupos.

---

## 8. Estimativa para a Fase 2 (implementação)

> O parser SSR-HTML já está validado nesta sessão → a geração dos dados é automatizável. O esforço real está no **matching de produtos**, nas **2 decisões** (§6.2/§6.3) e no **QA real no A36**.

| Abordagem | Âmbito | Esforço estimado |
|---|---|---|
| **C — Top-20/loja, schema actual (RECOMENDADA p/ lançar)** | ~60 produtos mais pedidos (3 lojas), inserção ingénua, menus simples primeiro | **~2 dias** (1d script+matching+insert · 0,5d decisão tamanho McD · 0,5d QA checkout/talão A36) |
| **Full ingénuo** | Todos os ~356 produtos c/ opções, schema actual | **~3-4 dias** (mais edge-cases combos/condicionais + QA) |
| **Templates partilhados** | Migration + modelo Flutter + ligação | **+2-3 dias** (Validation Gate DB) — **pós-lançamento** |
| **Açaí** | Re-categorizar 4 copos + confirmar lista real c/ dono | **~0,5 dia** (depende de receber a lista do dono) |

**Recomendação de sequência:** Abordagem **C** (top-20/loja, schema actual, menus simples) para validar UX end-to-end no A36 → depois alargar a todos os produtos → templates só se a manutenção doer.

---

## 9. Perguntas em aberto para Danilo / Claude.ai

1. **Decisão A (§6.2):** inserção ingénua (rápido, ~11k linhas) **ou** templates partilhados (limpo, muda schema)? → recomendo **ingénuo para lançar**.
2. **Decisão B (§6.3):** McDonald's — colapsar produtos-variante de tamanho num só produto + grupo "Tamanho", **ou** manter variantes e remover o grupo "Tamanho"?
3. **Âmbito Fase 2:** começar pelos **top-20/loja** ou ir logo aos ~356 produtos?
4. **Açaí:** consegues obter do dono a **lista real de toppings + preços + grupos**? (evita inventar — stop rule).
5. **Preço dos extras:** os `+€` da Glovo entram **puros** ou com o markup de 15% non-partner aplicado em runtime pelo `pricing_calculate`? *(Açaí é parceiro → modelo 10+5+5%; McD/BK/KFC são non-partner → +15%.)* Confirmar para não duplicar markup.

---

*Fim da Fase 1. Nada foi commitado. Ficheiro fica no working tree para revisão.*
