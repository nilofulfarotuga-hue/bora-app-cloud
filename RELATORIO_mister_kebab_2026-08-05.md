# Mr Kebab & Restaurant — relatório da missão

**Data:** 2026-08-05 · **Loja:** `mrkebab-guarda` · **Branch:** `autonomous-night-2026-04-29`

> **Resumo em três linhas:** as fotos, o logo, a capa, o painel admin e o mini-site estão
> feitos. A conta de parceiro **não** foi criada porque o email do dono ficou por preencher.
> E a simulação do dinheiro **não bateu certo em 2 dos 4 números** — não mexi em nada,
> está tudo explicado abaixo.

---

## 1. Fotos dos produtos

**18 produtos ficaram com foto. 29 ficaram sem.**

| | Quantos |
|---|---|
| Fotos novas, tiradas do Uber Eats | 10 |
| Fotos que já existiam na Glovo, migradas para o nosso Storage | 8 |
| **Total com foto** | **18** |
| Sem foto | 29 |

Todas as 18 estão agora em `restaurant-assets/mrkebab-guarda/products/` (o nosso Storage).
**Zero fotos continuam a apontar para o Uber ou para a Glovo** — confirmado por query.
Cada uma foi convertida para JPEG, largura máxima 1000px, e cada URL foi testado (todos 200).

### Os 29 que ficaram sem foto

Não inventei nem gerei nenhuma imagem, como pediste.

- **Hambúrgueres (6):** Burguer Vegetariano · Cheese Burguer · Chicken Burguer ·
  Menu Burguer Vegetariano · Menu Cheese Burguer · Menu Chicken Burguer
- **Taco Kebab (2):** Taco Kebab · Menu Taco Kebab
- **Bebidas (21):** Água 1,5L · Água 33cl · Água 50cl · Água das Pedras · Água das Pedras Limão ·
  Café · Coca-Cola 1L · Coca-Cola lata 33cl · Coca-Cola Zero 1L · Coca-Cola Zero lata 33cl ·
  Compal · Fanta Ananás lata · Fanta Laranja 1L · Fanta Laranja lata · Fanta Maracujá lata ·
  Nestea Limão · Nestea Manga Ananás · Nestea Pêssego · Sprite 1L · Sprite lata · Super Bock 33cl

**Porquê:** a página do Uber Eats desta loja só tem **18 artigos** no total (menus e pratos).
Hambúrgueres, taco kebab e bebidas simplesmente não existem lá. Na Glovo tentei a página
e a API — a página só devolve 5 artigos (a lista é carregada por JavaScript) e a API
respondeu 404 em três endereços diferentes. Não há de onde tirar essas fotos sem ser
fotografá-las no balcão.

### Casamentos que fiz (todos óbvios, nenhum adivinhado)

| Produto no Bora | Nome no Uber Eats |
|---|---|
| Menu Crispy Chicken | Menu Crispy chicken no Prato |
| Menu Doner Special | Menu Doner **Especial** |
| Menu Fish Fingers | Menu Fish Fingers no Prato |
| Menu Nuggets | Menu Nuggets no Prato |
| Crispy Chicken no Prato | Crispy chicken no Prato |
| Doner Box · Falafel no Prato · Fish Fingers no Prato · Nuggets no Prato | nome igual |
| Doner Special | Doner **Especial** |

**Backup feito antes de tocar em nada:** tabela `bkp_mrkebab_pre_fotos_20260805`,
com as 47 linhas originais (39 sem foto, 8 com). Confirmado por contagem.

---

## 2. Logo e capa da loja

**Sim, os dois estão no nosso Storage.** Já não apontam para `tb-static.uber.com`.

- Capa (`hero_image_url`) → `restaurant-assets/mrkebab-guarda/hero-….jpeg` (1000×800)
- Logo (`photo_url`) → `restaurant-assets/mrkebab-guarda/logo-….jpeg` (600×480)

**Uma nota honesta:** o Facebook da loja devolveu **HTTP 400** (está atrás de login),
por isso usei só o Uber, como mandaste. Só que o Uber tem **uma única imagem** para esta
loja — não tem logo separado da capa. Resultado: o logo e a capa são a mesma fotografia
em dois tamanhos. Funciona, mas **um logo a sério continua por arranjar** — o melhor é
pedires um ao dono quando falares com ele.

---

## 3. Conta de parceiro

**NÃO foi criada.** O email do dono ficou como `__PREENCHER__` no pedido.
Como combinado, saltei este passo e fiz tudo o resto.

Não há palavra-passe temporária para te dar — não houve conta.

Quando me deres o email, o que falta é: criar o utilizador no Auth com palavra-passe
temporária, pôr `users.role = 'partner'` e ligar `restaurants.user_id` a esse utilizador.

**`nif` e `iban` estão os dois vazios** — confirmado. Ficam pendentes de ti, e sem o IBAN
não é possível pagar o repasse semanal a esta loja.

---

## 4. Os 4 números da simulação de €20

Corri o pedido a sério dentro de uma transação com ROLLBACK: €20 de produtos, 3 km, cartão.
**Nada ficou gravado** — confirmei depois: 0 pedidos na loja, ledger na mesma (14 linhas),
`order_financials` a zero e `coming_soon` continua `true`.

| | Esperado | Deu | |
|---|---|---|---|
| Cliente paga | € 23,80 | **€ 23,80** | ✅ bate |
| Estafeta ganha | € 4,40 | **€ 4,40** | ✅ bate |
| Loja recebe | € 17,14 | **€ 17,15** | ❌ 1 cêntimo a mais |
| Bora fica com | € 2,86 | **€ 2,85** | ❌ 1 cêntimo a menos |

**PAREI e não corrigi nada**, como mandaste.

### Porque é que dá 1 cêntimo de diferença

Não é a fórmula que está errada — é **um arredondamento a meio da conta**.
A função `post_order_to_ledger` faz assim:

```
passo 1:  20,00 ÷ 1,05  = 19,047619…  →  arredonda já para 19,05
passo 2:  19,05 × 0,90  = 17,145      →  arredonda para 17,15
```

Se não arredondasse a meio, dava o teu número:

```
20,00 ÷ 1,05 × 0,90 = 17,142857…  →  17,14
```

Provei isto com uma query só de leitura:

| divisão exacta | passo 1 arredondado | como a função faz | sem arredondar a meio |
|---|---|---|---|
| 19,0476190476190476 | 19,05 | **17,15** (Bora 2,85) | **17,14** (Bora 2,86) |

É meio cêntimo a favor da loja em cada pedido. Nada de dramático, mas é uma decisão tua:
ou aceitas o 17,15, ou tiras o arredondamento do passo 1. **Não toquei na função.**

### Em dinheiro (cash) — este fecha certo ✅

Mesma simulação, paga em dinheiro. O acerto do estafeta fecha:

```
driver | cash_adjustment  => -23,80   (recebeu em mãos)
driver | earning          => +4,40    (o que é dele)
                     net  = -19,40    → deve 19,40 à Bora  ✅
```

Loja e plataforma dão o mesmo que no cartão (17,15 / 2,85).

### O caminho do dinheiro, ponta a ponta

`orders` → `post_order_to_ledger` → `ledger_entries` → `compute_partner_weekly_settlement`
→ `partner_weekly_settlements` — **esta parte está inteira e coerente.**
Chamei a `compute_partner_weekly_settlement` em modo leitura para esta loja e respondeu
certo (zeros, porque ainda não há pedidos).

---

## 5. O que mudou no painel admin

Duas coisas, ambas em PT-BR. `flutter analyze`: **0 erros**.

**a) Detalhe da loja** (`admin_partner_detail_screen.dart`) — cartão novo
**"Quem paga a comissão de 10%"**, com as duas opções:

- *Comissão paga pelo parceiro* (padrão)
- *Comissão paga pelo cliente* ← é a desta loja

Com o aviso em destaque, tal como pediste:

> ⚠️ Trocar esta opção **NÃO recalcula os preços do catálogo**. Ela só registra o acordo.
> Se o acordo mudou de verdade, os preços dos produtos precisam ser revistos à parte.

O cartão só aparece em lojas parceiras.

**b) Repasses a parceiros** (`admin_partner_payouts_screen.dart`) — cartão novo
**"Como esse número é calculado"**, com os 3 passos e um exemplo:

```
1. Preço do catálogo (já inclui os 5% embutidos)
2. Tira os 5% embutidos:   preço ÷ 1,05
3. Tira os 10% de comissão: × 0,90 = repasse à loja

Exemplo: € 20,00 → 19,05 → € 17,15 para a loja. A Bora fica com € 2,85.
```

⚠️ **Repara:** pus no exemplo **17,15 / 2,85**, que é o que o sistema faz de verdade
(provado acima) — e não 17,14 / 2,86. O painel tem de dizer a verdade. Se decidires
tirar o arredondamento do meio, este texto muda junto.

**c) Ver / editar / criar / banir / exportar:** já funcionava, não precisei mexer.
Confirmei no código: a lista do admin puxa **todos** os restaurantes sem filtro
(a loja aparece lá normalmente), o banir/reativar usa `is_active_admin` com registo
em auditoria, e o export já está ligado (`admin_export_service`).

---

## 6. Mini-site de presente

**https://mr-kebab.pages.dev** — a responder **HTTP 200**.

- Ficheiro único, 1,63 MB, todas as imagens em base64 — abre sem servidor nenhum.
- Tema preto / vermelho / dourado, a condizer com os quadros da loja.
  Tipos: Bebas Neue + Inter (Google Fonts).
- Secções: capa · sobre · 18 destaques do menu com preços · morada + mapa + horário ·
  faixa verde do Bora · rodapé.
- **QR verificado**: gerado com `segno` e confirmado byte-a-byte contra o URL da Play Store.
- Verificado ao vivo no browser: **21 imagens, 0 partidas**, sem scroll horizontal.
- **Só material real** — fotos da própria loja (Uber/Glovo) e o logo Bora do repo `bora-site`.
  Nada de bancos de imagem.
- Os preços mostrados são os do Bora App, tal como estão na base de dados. Não recalculei nada.

O projeto no Cloudflare não existia; criei-o (`mr-kebab`). Para republicar depois de
editares: `bash deploy-cloudflare.sh` dentro de `C:\Users\danil\Desktop\mr-kebab`.

---

## 7. Bugs encontrados fora do âmbito (não corrigi nenhum)

### 🔴 BUG 1 — `apply_order_financial_split` ficou de fora da correcção

A migration `fix_partner_ledger_hidden_markup_2026_08_05` arrumou a `post_order_to_ledger`,
mas **existe uma segunda função que também reparte o dinheiro do parceiro** e continua com
a fórmula antiga escrita à mão:

```sql
v_restaurant := ROUND(v_base * 0.90, 2);   -- 0,90 à mão, ignora o markup escondido
```

Ela corre no mesmo momento (trigger `orders_financial_split`) e escreve em
`order_financials` e `order_financial_transactions`. Na minha simulação:

| Onde | Loja | Plataforma |
|---|---|---|
| `ledger_entries` (função corrigida) | 17,15 | 2,85 |
| `order_financials` (função **não** corrigida) | **18,00** | **2,00** |

**Duas tabelas a dizer coisas diferentes sobre o mesmo pedido.** A boa notícia: o pagamento
semanal lê o `ledger_entries` (o correcto), por isso **ninguém está a ser mal pago hoje**.
A má: o `order_financials` é uma contabilidade paralela errada, e um dia alguém vai olhar
para ela e acreditar.

**Isto mexe em dinheiro — não toquei. Precisa da tua decisão.**

### 🟡 BUG 2 — as RPCs `admin_list_partner_payouts` / `admin_mark_partner_payouts_paid` não são deste caminho

O pedido dizia que a cadeia acabava nestas duas RPCs. Não acaba. Elas trabalham sobre
`partner_reservation_payouts` — que é o **sinal das reservas de mesa**, outra coisa
completamente. Não lêem `partner_weekly_settlements`.

Quem trata do repasse semanal são a `admin_list_partner_settlements_for_week` e a
`admin_set_partner_settlement_status`. Não é um bug que parta nada — é o mapa que estava
errado. Fica registado para não se perder tempo outra vez.

### 🟡 BUG 3 — a Edge Function `upload-restaurant-asset` não deixa escolher o nome do ficheiro

Ela carimba sempre um timestamp: `<loja>/<kind>-<timestamp>.<ext>`. Por isso os ficheiros
ficaram em `mrkebab-guarda/products/mrk-doner-box-1785950107371.jpeg` e não no
`mrkebab-guarda/products/mrk-doner-box.jpg` limpo que pediste. A pasta é a certa e está
tudo a funcionar — só o nome é que leva o número atrás.

Efeito secundário: se voltares a correr as fotos, ficam **cópias** no bucket em vez de
substituir (a função usa `upsert: false`). Vale a pena arrumar um dia.

### 🟢 BUG 4 — a loja não tem email

`restaurants.email` está vazio (string vazia). Vai fazer falta quando criares a conta.

---

## 8. O que fica pendente de ti

1. **O email do dono** — sem ele não há conta de parceiro. É o que bloqueia mais coisas.
2. **NIF e IBAN da loja** — sem IBAN não dá para pagar o repasse semanal.
3. **Decidir o cêntimo:** aceitas 17,15 para a loja, ou queres tirar o arredondamento
   do meio para dar 17,14? (mexe em dinheiro — só aplico com o teu "vai")
4. **Decidir o BUG 1** (`apply_order_financial_split` com o 0,90 à mão) — é o mais sério
   dos quatro. (mexe em dinheiro — só aplico com o teu "vai")
5. **Um logo a sério da loja** — pedir ao dono; o Uber só tem uma foto.
6. **As 29 fotos que faltam** — hambúrgueres, taco kebab e bebidas. Não existem em lado
   nenhum online; ou se fotografam no balcão, ou ficam sem.

---

## Coisas que não toquei, de propósito

- Preços dos `products` e `platform_settings` — nada alterado.
- `post_order_to_ledger` — já estava corrigida, deixei-a em paz.
- `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`, webhook Stripe.
- Nenhuma outra loja foi tocada. Todas as queries filtraram por `restaurant_id = 'mrkebab-guarda'`.
- `coming_soon` continua `true` — a loja **não** foi publicada.
- O `versionCode` não foi mexido (o CI trata disso).

---

## Prova do push

Commit `9c42ac63086321e1f9d664d1cf0349842772b8d2`, confirmado pela API do GitHub:

```
sha:       9c42ac63086321e1f9d664d1cf0349842772b8d2
msg:       feat(admin): acordo de comissao + explicacao do repasse (Mr Kebab)
data:      2026-08-05T17:42:53Z
ficheiros: RELATORIO_mister_kebab_2026-08-05.md
           lib/screens/admin/admin_partner_detail_screen.dart
           lib/screens/admin/admin_partner_payouts_screen.dart
```

Foram exactamente estes 3 ficheiros — usei `git add` por caminho, nunca `git add -A`.
O push por SSH falhou (chave), como já está registado; passou por HTTPS com o
`credential.helper=manager`. O remoto tinha avançado 2 commits do executor autónomo —
resolvi com `rebase --autostash`, **nunca** `--force`.

**Nota sobre o build:** como este commit mexe em `lib/`, o CI vai correr e publicar
build Android + web. Vai de boleia o commit `adfaa7a` (docs do evolution-engine),
que já estava por enviar.

---

> ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO.** Os pontos 3 e 4 da lista de pendentes
> (o cêntimo do arredondamento e a `apply_order_financial_split`) estão diagnosticados
> e prontos. **Confirma que eu aplico** — respondes "vai" e eu trato.
