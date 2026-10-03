# Mr Kebab — o site novo (2026-08-05)

**Loja:** `mrkebab-guarda` · **Site:** https://mr-kebab.pages.dev

> **Resumo:** o site v2 está feito e no ar, com o logo 3D que geraste, a fotografia da
> loja tratada e o menu completo. Sem uma única foto do Uber ou da Glovo, como pediste.
> Fiz também o BLOCO 5 (o cliente já percorre tudo e só é travado no pagamento).
> **Os BLOCOS 6 e 7 não foram feitos** — digo abaixo exactamente porquê e o que falta.

---

## 1. O site

**https://mr-kebab.pages.dev** — HTTP 200, 2,1 MB, ficheiro único.

Verificado ao vivo no browser, em duas larguras:

| | Telemóvel (390px) | Desktop (1440px) |
|---|---|---|
| Imagens | 9 | 9 |
| **Imagens partidas** | **0** | **0** |
| Scroll horizontal | não | não |
| Itens de menu | 47 | 47 |

Screenshots: [telemóvel](docs/mrkebab-site/site-mobile.png) ·
[desktop](docs/mrkebab-site/site-desktop.png) ·
[página completa](docs/mrkebab-site/site-pagina-completa.jpg)

### O que mudou em relação ao v1

- **Logo 3D em grande na capa**, recortado do fundo vermelho para assentar sobre a foto
  (antes teria aparecido como um quadrado colado).
- **Tipografia com carácter:** Baloo 2 (arredondada, a condizer com o relevo do logo) +
  Inter para o texto corrido. Nada por defeito.
- **Paleta tirada do logo:** vermelho `#D32027`, dourado `#F5B335`, creme `#FFF6EC`,
  preto para respirar.
- **7 secções:** capa · sobre (com a fachada) · menu completo (4 categorias, 47 itens,
  com linha pontilhada até ao preço) · galeria em mosaico · onde estamos (mapa + horário) ·
  contactos (4 cartões) · faixa Bora com QR + rodapé.
- **Animações discretas** ao rolar (IntersectionObserver, respeita `prefers-reduced-motion`).
- **Botão de WhatsApp** para +351 920 101 026, e o Facebook nos contactos.
- **QR real** gerado com `segno`, a apontar para a Play Store.

---

## 2. O logo — onde estava e onde ficou

Encontrei-o em `C:\Users\danil\Downloads`, gerado **hoje às 22:02**:
`mrkebab-logo-3d-1024.png` (1024×1024) e a versão 512.

- Subido para `restaurant-assets/mrkebab-guarda/logo3d-….png`
- **`restaurants.photo_url` já aponta para ele** ✅
- Usado tal e qual no site — não redesenhei nada. A única coisa que fiz foi **tirar o
  fundo vermelho** (preenchimento a partir das bordas), para o emblema assentar sobre a
  foto da capa. O desenho em si está intacto.

---

## 3. Imagens: de onde vieram e o que levaram

| Fonte | Encontradas | Usadas | Notas |
|---|---|---|---|
| **Downloads (PC)** | 2 | 1 | Só os dois ficheiros do logo. **Não há uma única foto da loja no PC** — as 3 fotos que lá estavam são screenshots do próprio Bora App, de Junho |
| **Facebook** | 10 | **5** | Capa, fachada e 3 de comida |
| **Instagram** | 0 | 0 | Tentei `@mrkebabrestaurant` e `@mr.kebab.guarda` — **não existe conta**. `social_instagram` fica a NULL |
| **Google Business** | 1 | 0 | Só devolveu miniaturas de mapa, sem foto aproveitável do estabelecimento |
| **TripAdvisor** | 0 | 0 | A loja não tem ficha |
| **Uber Eats / Glovo** | — | **0** | **Excluídas por tua ordem** |

### O que rejeitei do Facebook (e porquê)

- Um **anúncio da Glovo** ("mega DESCONTO") — é publicidade da plataforma, não comida da casa
- O **logotipo do Uber Eats**
- A foto do **quadro de menu** — tem preços diferentes dos nossos, ia baralhar o cliente
- Uma repetida da capa

### Tratamento aplicado (o mesmo em todas, para não parecer colagem)

1. `autocontrast` com corte de 1% — nivela a exposição sem queimar os brancos
2. Correcção da dominante de cor pelo cinza-médio, a 60% (as fotos vinham amareladas)
3. Saturação +10%, contraste +4%
4. Redimensionamento (1500px a capa, 1100px as restantes)
5. `UnsharpMask` raio 1,3 / 95% / limiar 3 — nitidez sem halo

Nenhuma foto foi gerada. Nenhum prato inventado.

---

## 4. Onde o cliente é travado agora (BLOCO 5) ✅

**Antes:** com `coming_soon = true` o cliente batia numa parede logo no primeiro "+" —
não conseguia sequer pôr nada no carrinho.

**Agora:** percorre tudo — abre a loja, escolhe produtos, escolhe opções, enche o
carrinho, segue para o checkout, escolhe morada e método de pagamento — e **só para no
ecrã de pagamento**, onde o botão "Confirmar pagamento" é substituído por:

> ⏱️ **Esta loja ainda está a ser preparada. Em breve poderá finalizar o seu pedido.**

Como está feito, em vez de espalhar condições por sete ficheiros:

- `CartStore` ganhou o getter **`vendorBlocksAddToCart`**, que devolve `false` e está
  documentado a dizer porquê. Os seis sítios que travavam o carrinho passaram a lê-lo.
- `vendorComingSoon` continua a existir e é o que alimenta **o selo "Em breve" na lista
  e o banner na ficha** — esses ficam, como pediste.
- O bloqueio novo vive em `payment_method_screen.dart`.

**Não toquei no trigger `trg_payment_draft_coming_soon`.** É ele que garante que ninguém
é cobrado; isto é só a camada de UI. `flutter analyze`: **0 erros**.

Ficheiros: [cart_store.dart](lib/stores/cart_store.dart) ·
[payment_method_screen.dart](lib/screens/payment_method_screen.dart) ·
restaurant_menu · product_detail · cart_screen · store_products · market_product_card ·
bora_product_card

---

## 5. ⚠️ O que NÃO foi feito

Sou directo: **os BLOCOS 6 e 7 ficaram por fazer.** A missão tinha oito blocos e o site
— que tu próprio disseste ser o critério principal — levou a maior parte do trabalho
(procurar o material, três abordagens diferentes até conseguir apanhar as fotos do
Facebook sem o modal de login por cima, tratar tudo, construir, publicar, verificar).

### BLOCO 6 — multi-papel parceiro + cliente
Não auditei o Flutter nem testei o login `mr.kebab@bora.app`. O lado da base de dados
já está feito (as duas linhas em `user_roles`, a RPC `my_roles()`), mas **não sei dizer
se a app mostra o seletor de papel** — e não vou dizer que sim sem ter visto.

Para a próxima sessão: procurar quem chama `my_roles()` em `lib/`, ver o que acontece a
seguir ao login quando devolve dois papéis, e correr o teste real com os dois logins.

### BLOCO 7 — painel admin
Não expus `whatsapp`, `social_facebook`, `social_instagram`, `about_text`,
`takeaway_enabled`, `reservations_enabled` nem os papéis do utilizador. Fica inteiro
para a próxima.

---

## 6. Bugs e achados fora do âmbito

### 🟠 1 — O Facebook tapa tudo com o modal de login
Capturar imagens da página exige contornar isto. Falharam duas abordagens: screenshot do
elemento (sai com o modal por cima) e remover os overlays do DOM (removeu também o
conteúdo — 0 capturas). **A que funciona:** recolher os URLs `fbcdn` da página e depois
**abrir cada imagem no seu próprio separador**, onde não há overlay nenhum. Fica
registado para não se perder tempo outra vez.

### 🟡 2 — O logo veio com fundo sólido, não transparente
O PNG que geraste é um quadrado vermelho cheio. Num site com foto de fundo isso aparece
como um rectângulo colado. Recortei-o por software, mas **se conseguires gerar uma versão
com fundo transparente**, fica melhor — a orla do recorte tem uns dentes finos no topo.

### 🟡 3 — A cache do Chrome enganou-me na verificação
O primeiro screenshot depois de publicar mostrava ainda a versão antiga. Só percebi
porque fui comparar os bytes do logo no disco com os do site ao vivo — batiam. Passei a
tirar os screenshots com `Network.setCacheDisabled`. **Um screenshot logo a seguir a um
deploy não prova nada sem desligar a cache.**

### 🟢 4 — Não há uma única foto real da loja no PC
Nem no Downloads, nem no Pictures, nem no Desktop. Todo o material fotográfico do site
veio do Facebook. Vale a pena tirares fotos no balcão — é o que falta para o site subir
mais um degrau.

---

## 7. Pendente de ti

1. **NIF e IBAN** da loja — continuam vazios; sem IBAN não há repasse semanal.
2. **Horário certo**, com a pausa de almoço — o que está na base de dados diz
   11:00–23:59 seguido, e o quadro da loja diz "11 AM até às 12 AM". O site mostra o que
   está na base de dados.
3. **Fotos de 22 produtos** — 6 hambúrgueres, 2 taco kebab e 14 bebidas.
4. **As 9 pizzas** do quadro do Facebook, que continuam fora do catálogo.
5. **Instagram** — se a loja tiver conta, diz o handle e eu gravo em `social_instagram`.
6. **Logo com fundo transparente** (ver achado 2).
7. Continuam de pé as decisões de dinheiro dos relatórios anteriores.

---

## O que não toquei, de propósito

- `products.price`, `products.partner_shelf_price` — zero alterações.
- `platform_settings`, `post_order_to_ledger`, `apply_order_financial_split`,
  `partner_store_share`, o trigger de `payment_drafts`.
- **Nenhuma outra loja.**
- `coming_soon` continua **`true`**.
- `versionCode` não mexido.

## Máquina deixada como estava

Chrome fechado (0 processos), `C:\Users\danil\chrome-bora` apagado, porta 9222 fechada.
