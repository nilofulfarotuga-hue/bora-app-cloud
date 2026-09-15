# Mr Kebab — opções do Uber e fotos das bebidas (2026-08-05)

**Loja:** `mrkebab-guarda` · **Método:** Chrome real com o teu perfil + Playwright por CDP

> **Resumo em três linhas:** as opções já estavam quase todas certas — só faltava **uma**
> (Batata Frita com Molho), que acrescentei aos 26 produtos. Das 21 bebidas, **7 ficaram
> com foto**; rejeitei 6 imagens que mostravam packs de 6/8/24 ou o tamanho errado.
> E há **3 preços de opção** que o Uber tem mais caros — não mexi, precisa da tua decisão.

---

## 1. Opções: o que o Uber tem vs o que tínhamos

Abri os **26 produtos do Uber um a um** (`getMenuItemV1`, o mesmo pedido do modal de
"adicionar ao carrinho"). Nenhum saltou, nenhum falhou — 26/26 responderam.

### O que o Uber tem

| Grupo no Uber | Obrigatório | Mín/Máx | Em quantos produtos | Opções |
|---|---|---|---|---|
| Escolha a sua bebida | Não (min=0) | 0–1 | 9 | 10, todas a +0,00 € |
| Deseja Extras? | Não | 0–2 | 17 | 4 |

### O que nós temos

| Grupo nosso | Obrigatório | Mín/Máx | Em quantos produtos | Opções |
|---|---|---|---|---|
| Bebida à escolha | **Sim** | 1–1 | 13 | 13, todas a +0,00 € |
| Extras | Não | 0–10 | 26 | 10 → **11** |

**Somos mais completos que o Uber nos dois grupos.** Tínhamos 13 bebidas contra 10, e
10 extras contra 4.

### O que foi acrescentado

**Uma opção nova, em 26 produtos:**

| Opção | Preço | Porquê |
|---|---|---|
| **Batata Frita com Molho** | +3,00 € | O Uber tem ("Batata Frita c/ molho"), nós não tínhamos |

Nome arrumado em PT-PT, como pediste. Total de itens de opção: **429 → 455**.

### O que ficou como estava, e porquê

| Situação | Decisão |
|---|---|
| Sprite, Fanta Ananás, Fanta Maracujá, Água 33cl (bebidas só nossas) | **Mantidas** — vieram do quadro da loja, são reais |
| Batata Grande/Pequena, Salada no Prato, Pão, Falafel, Crispy, Nuggets (extras só nossos) | **Mantidos** pela mesma razão |
| Uber "Água" vs nosso "Água 33cl" | **Não dupliquei** — é a mesma coisa e o nosso nome é o mais arrumado (regra dos nomes PT-PT) |
| Uber deixa levar menu **sem** bebida (min=0); nós obrigamos a escolher (min=1) | **Mantive o nosso.** Um menu com bebida incluída deve obrigar à escolha, senão o cliente paga a bebida e não a leva |

### Cobertura — já estava completa, não foi preciso mexer

- **Extras:** nos 26 produtos não-bebida (os 47 menos as 21 bebidas). Inclui os
  **6 hambúrgueres e os 2 taco kebab** que não existem no Uber. ✅
- **Bebida à escolha:** nos 13 menus. Não está (e bem) nos pratos individuais nem nas bebidas. ✅

---

## 2. ⚠️ Preços de opção diferentes do Uber — NÃO alinhei

O pedido dizia "preço de opção diferente do Uber → alinhar pelo Uber". **Parei aqui**, e
explico porquê num parágrafo.

| Opção | Nosso | Uber | Se alinhasse |
|---|---|---|---|
| Extra Arroz | 1,84 € | 2,50 € | +36% |
| Extra Carne | 2,30 € | 2,50 € | +9% |
| Extra Molho | 0,58 € | 0,80 € | +38% |

**O motivo:** os nossos preços de opção **já seguem a regra que corrigiste hoje**
(`balcão × 1,15`) — 1,60×1,15=1,84 · 2,00×1,15=2,30 · 0,50×1,15=0,58. Batem certo, ao
cêntimo. Os preços do Uber **não são preços de balcão**: já trazem a margem do Uber por
cima (em média o Uber está +11,2% acima de nós na comida).

Alinhar pelo Uber punha estas três opções a **balcão × 1,25 a × 1,56** — ou seja, partia
a regra que acabaste de arrumar, e o cliente do Bora pagaria o preço do Uber.

**⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.**
Diz "vai" e alinho pelo Uber. Se preferires manter a regra × 1,15, não é preciso fazer nada.

*(A única exceção que apliquei foi a Batata Frita com Molho, a +3,00 €: é uma opção nova,
não temos preço de balcão para ela, e o Uber era a única fonte.)*

---

## 3. Fotos das bebidas: 7 de 21

Fonte: **Continente** (imagens de produto PNG, fundo branco, limpas). Todas normalizadas a
**800×800, fundo branco, JPEG**, subidas para o nosso Storage. Nenhuma ficou a apontar para fora.

### Ficaram com foto (7)

| Produto | Imagem |
|---|---|
| Coca-Cola lata 33cl | lata 330 ml |
| Coca-Cola Zero lata 33cl | lata 330 ml |
| Sprite lata 33cl | lata 330 ml |
| Fanta Laranja lata 33cl | lata 330 ml |
| Coca-Cola 1L | garrafa 1 L |
| Coca-Cola Zero 1L | garrafa 1 L |
| Compal | pacote Compal Família |

### Rejeitei 6 imagens depois de as ver

Descarreguei-as, olhei para elas uma a uma num mosaico, e **chumbei estas** — deixei os
produtos com `needs_photo = true`:

| Produto | Porque chumbou |
|---|---|
| Super Bock 33cl | a imagem é um **pack de 24 latas** |
| Água das Pedras | **pack de 6×33cl**, sem garrafa isolada |
| Água das Pedras Limão | **pack de 8×25cl** |
| Fanta Maracujá lata 33cl | a imagem é uma **garrafa de 2 L** — o produto é lata |
| Fanta Laranja 1L | imagem de **2 L**, o produto é 1 L |
| Sprite 1L | imagem de **2 L**, o produto é 1 L |

O Continente vende em pack, por isso muitas fotos mostram a embalagem múltipla. Pôr um
pack de 24 cervejas num item que custa 1,75 € seria enganar o cliente. Preferi deixar sem.

### Continuam sem foto (14 bebidas + 8 comidas = 22)

**Bebidas (14):** Água 1,5L · Água 33cl · Água 50cl · Água das Pedras · Água das Pedras Limão ·
Café · Fanta Ananás lata 33cl · Fanta Laranja 1L · Fanta Maracujá lata 33cl ·
Nestea Limão · Nestea Manga Ananás · Nestea Pêssego · Sprite 1L · Super Bock 33cl

Razões concretas:
- **As 3 águas simples (33cl, 50cl, 1,5L):** o nosso catálogo **não diz a marca**. Pôr uma
  garrafa de Luso quando a casa serve outra marca é errado. Falta saber qual é.
- **Os 3 Nestea:** o Continente **não vende Nestea** — só Lipton, Fuze Tea e marca própria.
  Marca errada é pior que sem foto.
- **Café:** é um expresso servido à chávena, não um produto de prateleira. As buscas só
  devolvem cápsulas e café solúvel.
- **Fanta Ananás lata:** zero resultados no Continente.
- Os restantes: ver a tabela dos chumbados acima.

**Comida (8):** os 6 hambúrgueres e os 2 taco kebab. Como combinado, **não inventei nem
gerei imagem nenhuma** — só se resolve fotografando na loja.

**Estado das fotos:** 18 → **25 de 47**.

---

## 4. Site actualizado

**https://mr-kebab.pages.dev** — **HTTP 200**, 1,99 MB.

Acrescentei a secção **Bebidas** com as 7 novas. O site tem agora **25 produtos**, continua
ficheiro único com tudo em base64 e **0 imagens externas**. Preços tal como estão na base
de dados, nada recalculado.

---

## 5. Bugs e achados fora do âmbito

### 🟠 1 — Quase escrevi na base de dados com dados incompletos

A minha primeira leitura das opções via API REST devolveu **11 grupos e 0 itens**, quando a
loja tem 39 e 429. Motivo: pedi as tabelas `product_option_groups`/`product_option_items`
**sem filtro no servidor** — o PostgREST devolveu a primeira página de **todas as lojas** e
a nossa quase não apareceu.

Apanhei porque o número não batia com o que a mesma pergunta em SQL tinha dado minutos antes.
Corrigi com filtro `in.(...)` no servidor e pus um `assert` a exigir 39/429 antes de seguir.

**Lição que vale para os próximos scrapers:** nunca filtrar em memória o que se pode filtrar
no servidor — a página truncada parece um resultado válido.

### 🟡 2 — Os preços das opções seguem a regra × 1,15, mas ninguém o documenta

As 10 opções de Extras batem certo com `balcão × 1,15` (1,00→1,15 · 2,00→2,30 · 4,00→4,60 ·
5,00→5,75 · 0,80→0,92). Ou seja, a correcção de hoje **também** apanhou as opções. Boa notícia
— mas não está escrito em lado nenhum que a regra se aplica a `product_option_items.price_add`.
Vale a pena registar, senão a próxima pessoa alinha-as por uma fonte externa sem saber.

### 🟡 3 — Ficaram 6 imagens órfãs no Storage

As 6 que chumbei já tinham sido subidas antes de as ver. Estão em
`restaurant-assets/mrkebab-guarda/products/` mas **nenhum produto aponta para elas** (a base
de dados só tem as 7 boas). Não fazem mal, mas ocupam espaço. Somam-se ao problema já
reportado de a Edge Function `upload-restaurant-asset` carimbar timestamp e usar
`upsert:false`, o que deixa cópias a cada corrida.

### 🟡 4 — O scratchpad foi limpo a meio pela sessão

A meio do trabalho outro processo do Claude Code apagou a pasta temporária, incluindo o
`node_modules` e os ficheiros de candidatos. Perdi uma passagem de trabalho. Passei a
trabalhar em `C:\Users\danil\mrkebab-work`, fora da pasta partilhada, e juntei
procura+download+upload numa só corrida para não depender de ficheiros intermédios.

---

## 6. O que fica pendente de ti

1. **Os 3 preços de opção** (secção 2) — dizes "vai" e alinho pelo Uber, ou fica na regra × 1,15.
2. **A marca da água** que a casa serve — sem isso as 3 águas simples ficam sem foto.
3. **Email do dono** — continua por preencher; sem ele não há conta de parceiro.
4. **NIF e IBAN** — continuam vazios; sem IBAN não se paga o repasse semanal.
5. **Um ficheiro do logo em condições** — o que temos é o avatar do Facebook a 169 px.
6. **Fotos dos 6 hambúrgueres e dos 2 taco kebab** — só na loja.
7. **Confirmar as 9 pizzas** do quadro do Facebook — continuam fora do catálogo.
8. Continuam de pé as **2 decisões de dinheiro** de
   [RELATORIO_mister_kebab_2026-08-05.md](RELATORIO_mister_kebab_2026-08-05.md) §4 e §7.

---

## O que não toquei, de propósito

- **`products.price` e `products.partner_shelf_price`:** zero alterações. Confirmado por query.
- **Preços de opção existentes:** zero alterações (ver secção 2).
- `platform_settings`, `post_order_to_ledger`, `apply_order_financial_split`,
  `partner_store_share`, `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`,
  `bora_tokens`, webhook Stripe.
- **Nenhum grupo ou opção nosso foi apagado.**
- **Nenhuma outra loja tocada** — confirmado: `0` produtos de outras lojas alterados nas
  últimas 3 horas.
- `coming_soon` continua **`true`**. A loja não foi publicada.
- `versionCode` não mexido.

**Backup antes de escrever:** `bkp_mrkebab_opcoes_v2_20260805` — 39 grupos, 429 itens.

## Estado final

| | Antes | Depois |
|---|---|---|
| Produtos | 47 | 47 |
| Com foto | 18 | **25** |
| Sem foto | 29 | **22** |
| Bebidas com foto | 0 | **7** |
| Grupos de opções | 39 | 39 |
| Itens de opção | 429 | **455** |

## Máquina deixada como estava

- Chrome fechado (0 processos), `C:\Users\danil\chrome-bora` apagado, porta 9222 fechada.
