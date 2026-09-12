# Mr Kebab — crawler pelo Chrome real (2026-08-05)

**Loja:** `mrkebab-guarda` · **Método:** Chrome real com o teu perfil + Playwright por CDP

> **Resumo em três linhas:** o método novo trouxe **26 produtos** (o errado trazia 18) — mas
> a loja **só tem 26 no Uber**, não 47. Fotos novas: **zero**, porque as que faltam não
> existem em lado nenhum. O que valeu mesmo a pena foi **o logo e a capa a sério do Facebook**
> e **3 bebidas que faltavam nos menus**.

---

## 1. Quantos produtos o Uber devolveu

| Método | Produtos |
|---|---|
| Sessão anterior (pedido à página pública) | 18 |
| **Agora (Chrome real + sessão do Danilo)** | **26** |
| No balcão (a nossa verdade) | 47 |

**+8 produtos** que o método errado não via — as 8 bebidas do Uber (Coca-cola, Coca-cola Zero,
Fanta Laranja, Nestea ×3, Super Bock, Água). Aparecem sem foto, e é por isso que o método
antigo, que só apanhava coisas com imagem, as perdia.

**As validações do BLOCO 2 passaram todas:**

| Validação | Resultado |
|---|---|
| ≥ 25 produtos | ✅ 26 |
| 0 produtos sem preço na fonte | ✅ 0 |
| Nenhuma imagem repetida em >5 produtos | ✅ máx. 2× |

Bruto guardado em [harvest/mrkebab_uber_2026-08-05.json](harvest/mrkebab_uber_2026-08-05.json)
(26 produtos, com descrições e grupos de opções) — gravado **antes** de tocar na base de dados.

**Porque é que 26 e não 47:** o Uber não é um espelho do balcão. A carta do Uber não tem
hambúrgueres, não tem taco kebab, não tem pizzas, e tem só 8 bebidas em vez de 21. Não é falha
do crawler — abri o detalhe dos 26 produtos um a um e todos responderam 200. É mesmo o menu
que a loja pôs no Uber.

---

## 2. Fotos: quantos dos 29 ficaram com foto

**Zero. Continuam 29 sem foto.** Ficamos nos mesmos 18 de antes.

Desta vez a resposta é definitiva, não é uma suspeita:

- **Hambúrgueres (6) e Taco Kebab (2):** não existem no Uber. Nada para buscar.
- **Bebidas (21):** as 8 que o Uber tem apareceram agora — mas **todas sem imagem**.
  Confirmei abrindo o modal de detalhe de cada uma: `img=nao` nas 8.

**Os que continuam sem foto:**
Água 1,5L · Água 33cl · Água 50cl · Água das Pedras · Água das Pedras Limão · Café ·
Coca-Cola 1L · Coca-Cola lata · Coca-Cola Zero 1L · Coca-Cola Zero lata · Compal ·
Fanta Ananás lata · Fanta Laranja 1L · Fanta Laranja lata · Fanta Maracujá lata ·
Nestea Limão · Nestea Manga Ananás · Nestea Pêssego · Sprite 1L · Sprite lata ·
Super Bock 33cl · Burguer Vegetariano · Cheese Burguer · Chicken Burguer ·
Menu Burguer Vegetariano · Menu Cheese Burguer · Menu Chicken Burguer ·
Taco Kebab · Menu Taco Kebab

Para estes só há um caminho: **fotografar no balcão**. Não inventei nem gerei nenhuma.

---

## 3. Opções novas que apareceram

**Acrescentei 3 bebidas ao grupo "Bebida à escolha"**, que o Uber oferece e nós não tínhamos:

- **Super Bock**
- **Água das Pedras**
- **Água das Pedras Limão**

Aplicado aos **13 menus** que têm esse grupo → **39 linhas novas** (390 → 429 itens de opção).
Todas a **+0,00 €**, exactamente como no Uber e como as outras 10 bebidas. Não apaguei nada
nem mexi em nenhum preço existente.

**Nos "Extras" não havia nada de novo** — pelo contrário, nós somos mais completos:

| | Nosso | Uber |
|---|---|---|
| Extras | 10 opções | 4 opções |

As 4 do Uber (Arroz, Carne, Molho, Batata Frita c/ molho) são as mesmas que já temos com
outro nome (Extra Arroz, Extra Carne, Extra Molho, Batata Pequena/Grande).

---

## 4. Produtos no Uber que não temos

**Nenhum.** Os 26 do Uber estão todos no nosso catálogo de 47. Não foi preciso inserir nada,
nem usar o `needs_price_review` nem a estimativa ÷1,32.

---

## 5. Balcão vs Uber

**Em média o Uber está +11,2% acima do nosso preço** (26 produtos comparados).
Não toquei em preço nenhum — isto é só para veres.

| Produto | Bora | Uber | Dif. |
|---|---|---|---|
| Super Bock 33cl | 1,75 | 2,60 | +48,6% |
| Doner Kebab | 4,55 | 6,50 | +42,9% |
| Nestea (×3) | 1,87 | 2,60 | +39,0% |
| Durum Kebab | 5,25 | 6,80 | +29,5% |
| Doner Box | 4,67 | 6,00 | +28,5% |
| Menu Doner Box | 6,42 | 7,50 | +16,8% |
| Menu Doner Kebab | 8,05 | 9,20 | +14,3% |
| Menu Durum Kebab | 8,40 | 9,50 | +13,1% |
| Crispy Chicken no Prato | 7,82 | 8,50 | +8,7% |
| Menu Falafel | 8,75 | 9,50 | +8,6% |
| Menu Fish Fingers / Crispy | 9,22 | 9,90 | +7,4% |
| Menu Kebab no Prato / Nuggets | 9,22 | 9,80 | +6,3% |
| Falafel no Prato | 7,58 | 8,00 | +5,5% |
| Kebab / Nuggets / Fish no Prato | 7,82 | 8,00 | +2,3% |
| Menu Doner Special | 9,92 | 9,90 | −0,2% |
| Doner Special | 8,17 | 8,00 | −2,1% |
| Coca-Cola / Zero / Fanta 1L | 3,03 | 2,60 | −14,2% |
| Água 1,5L | 1,75 | 1,20 | −31,4% |

**Leitura:** somos mais baratos que o Uber em quase tudo o que é comida — nas sandes soltas
por uma margem grande (30-43%). Só perdemos nas garrafas de 1L e na água grande, onde estamos
acima. Vale a pena olhares para essas 4 bebidas.

---

## 6. Logo — apareceu, sim ✅

Com a sessão real do Chrome o Facebook abriu (antes dava HTTP 400). Recusei os cookies
opcionais e cheguei à página.

- **Capa:** ✅ foto de capa real da loja, 960×768, comida da casa (sandes de doner, nachos,
  hambúrgueres). Muito melhor que a do Uber. Subida como
  `restaurant-assets/mrkebab-guarda/hero-fb-….jpeg` (1000×801) → `hero_image_url`.
- **Logo:** ✅ a foto de perfil real da loja (os dois espetos de doner a girar). Subida como
  `logo-fb-….jpeg` → `photo_url`.
  ⚠️ **Mas só 169×169 px.** O avatar do Facebook não é descarregável como ficheiro (é
  desenhado com máscara SVG); tive de o recortar do ecrã. Dá para miniatura, não dá para
  imprimir. **Um ficheiro do logo a sério ainda vale a pena pedir ao dono.**

**Bónus:** numa publicação da loja está o **quadro de menu completo**, com o logo gráfico
verdadeiro (o "mr kebab & restaurant" em vermelho e branco) e a tabela de preços do balcão.
Guardei a imagem. É daí que se tira um logo decente se o dono não tiver o ficheiro.

O Google Business não deu nada — só devolveu mapas, sem foto da loja.

---

## 7. Site actualizado

**https://mr-kebab.pages.dev** — a responder **HTTP 200**, 1,66 MB.

Troquei só a capa (agora é a do Facebook, real). O resto ficou igual: os mesmos 18 produtos
com foto, os mesmos preços, o mesmo QR. Continua ficheiro único com tudo em base64,
**0 imagens externas**.

---

## 8. Bugs e achados fora do âmbito

### 🟠 1 — A loja tem PIZZAS que não estão no nosso catálogo

O quadro de menu do Facebook lista **9 pizzas** (Individual, Margherita, Napolitana,
Mr. Kebab, Carbonara, Pepperoni, Frango, Atum, Familiar). **Não temos nenhuma** — nem no
nosso catálogo, nem no Uber. As fotos do balcão de 05/08 não as apanharam.

Não inseri nada: não vieram do Uber, e o quadro do Facebook pode ser antigo. **Precisa de
confirmação com o dono** antes de entrar.

### 🟠 2 — Os preços do quadro do Facebook são MUITO mais baixos que os nossos

O mesmo quadro mostra, por exemplo, `DONNER BOX 3,20 € individual / 3,80 € menu`.
O nosso Doner Box está a **4,67 €** e o Menu Doner Box a **6,42 €**.

Aplicando a tua fórmula ao 3,20 dava 3,73 €, não 4,67 €. Ou o quadro do Facebook é de outra
época, ou as fotos do balcão de 05/08 leram outros valores.

**Não toquei em preço nenhum** — é a stop rule. Mas convém confirmares qual é o quadro em
vigor, porque a diferença é grande.

### 🟡 3 — `getCatalogPresentationV2` não serve para restaurantes

A receita da skill `market-data-sync` usa esse endpoint (validado no Intermarché). Para
restaurantes devolve **0 itens** — o menu vem todo dentro do `getStoreV1`, em
`catalogSectionsMap`. Perdi uma tentativa nisso.

**Vale a pena anotar na skill:** mercearia → `getCatalogPresentationV2`; restaurante →
`getStoreV1` + `getMenuItemV1` por produto.

### 🟡 4 — No Uber a bebida do menu é opcional; para nós é obrigatória

O grupo do Uber é `min=0` (dá para levar menu sem bebida). O nosso é `min=1, max=1`
(obrigatório). Não mudei — o nosso é o mais correcto para um menu. Fica registado.

### 🟢 5 — O `upload-restaurant-asset` continua a carimbar timestamp no nome

Já tinha sido reportado. Os ficheiros ficam `logo-fb-1785955081371.jpeg` em vez de
`logo.jpg`, e como usa `upsert:false`, cada nova corrida deixa uma cópia no bucket em vez
de substituir.

---

## 9. O que fica pendente de ti

1. **Email do dono** — continua por preencher; sem ele não há conta de parceiro.
2. **NIF e IBAN** — continuam vazios; sem IBAN não se paga o repasse semanal.
3. **As pizzas** (achado 1) — confirmar com o dono se entram no catálogo.
4. **Qual o quadro de preços em vigor** (achado 2) — a diferença é grande.
5. **Um ficheiro do logo em condições** — o que temos é um recorte de 169 px.
6. **As 29 fotos que faltam** — só fotografando no balcão.
7. Continuam de pé as **2 decisões de dinheiro** do relatório anterior
   (arredondamento 17,15 vs 17,14 e a `apply_order_financial_split`) — ver
   [RELATORIO_mister_kebab_2026-08-05.md](RELATORIO_mister_kebab_2026-08-05.md) §4 e §7.

---

## O que não toquei, de propósito

- **Preços de `products`:** zero alterações. Backup `bkp_mrkebab_pre_crawler_20260805` (47 linhas)
  criado antes de qualquer escrita.
- `platform_settings`, `post_order_to_ledger`, `apply_order_financial_split`,
  `partner_store_share`, `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`,
  `bora_tokens`, webhook Stripe.
- **Nenhuma outra loja tocada** — confirmado por query: `0` produtos de outras lojas
  alterados nas últimas 2 horas.
- `coming_soon` continua `true`. A loja **não** foi publicada.
- `versionCode` não mexido.

## Estado final da loja

| | Antes | Depois |
|---|---|---|
| Produtos | 47 | 47 |
| Com foto | 18 | 18 |
| Sem foto | 29 | 29 |
| Grupos de opções | 39 | 39 |
| Itens de opção | 390 | **429** |
| Logo | foto do Uber | **avatar real do Facebook** |
| Capa | foto do Uber | **capa real do Facebook** |

## Máquina deixada como estava

- `taskkill /IM chrome.exe /F` → 0 processos a correr.
- `C:\Users\danil\chrome-bora` apagado (confirmado: `Test-Path` = False).
- Porta 9222 fechada.
