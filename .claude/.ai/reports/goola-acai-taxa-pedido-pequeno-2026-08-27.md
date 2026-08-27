# Goola Açaí + Taxa de pedido pequeno + Sobremesas — 2026-08-27

> Relatório para ser ouvido em voz alta. Cada afirmação tem saída de comando
> por baixo. O que falhou está dito com a causa real.

---

## 0. O QUE TENS DE DECIDIR (só isto exige "vai")

**⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.**

A taxa de pedido pequeno está **construída ponta a ponta mas DESLIGADA**.
Falta **uma peça**, e é a Trava que a protege — não a contornei.

Ficheiro pronto:
`supabase/migrations/20260827131000_PROPOSTA_taxa_pedido_pequeno_pricing.sql`

```
🔒 TRAVA BORA — operação BLOQUEADA: DDL (CREATE OR REPLACE/DROP/ALTER)
   sobre função/trigger de dinheiro
```

Porque é que essa peça é mesmo precisa: o pagamento por **cartão** cobra o
valor calculado **antes de o pedido existir**. Sem essa alteração, o cartão
cobrava sem a taxa e o pedido ficava registado com ela — o mesmo carrinho
sairia mais barato a cartão do que a dinheiro. Preferi deixar tudo desligado a
deixar isso no ar.

Quando disseres "vai", são dois passos: aplicar o ficheiro e pôr
`small_order_fee_enabled` a `true` no painel. **Os dois lados acendem ao mesmo
tempo** — o cliente e o servidor leem o mesmo interruptor.

---

## 1. PROVA — as duas definições novas, lidas pelo checkout

```sql
SELECT key, value, category, description FROM platform_settings
 WHERE key IN ('min_order_cents','small_order_fee_cents','small_order_fee_enabled');
```

| key | value | category |
|---|---|---|
| `min_order_cents` | `1200` | fees |
| `small_order_fee_cents` | `139` | fees |
| `small_order_fee_enabled` | `false` | fees |

Nenhum destes valores está no código. O cliente e o servidor leem-nos daqui —
é a regra que já nos mordeu nos tokens do TVDE.

Função de cálculo viva em produção (a MESMA que o cliente espelha):

```sql
SELECT public.small_order_fee_calc('restaurant', 9.22, 'goola-acai-guarda');
--> 0      (porque o interruptor está false — estado seguro de hoje)
```

Com o interruptor ligado (medido antes de o pôr a false):

| caso | subtotal | taxa |
|---|---|---|
| goola bowl, abaixo do mínimo | 9,22 | **1,39** |
| 2 big bowls, acima | 23,10 | 0 |
| exactamente no mínimo | 12,00 | 0 |
| um cêntimo abaixo | 11,99 | **1,39** |
| mercado não-parceiro | 8,00 | **1,39** |
| takeaway (não é entrega) | 9,22 | 0 |
| sendPackage (sem produtos) | — | 0 |

---

## 2. PROVA — o cálculo, ao cêntimo, cliente e servidor

`flutter test test/taxa_pedido_pequeno_test.dart` → **17/17 verdes**

**Um bowl só (com taxa)** — Goola Bowl, parceiro, 1 km:

| linha | valor |
|---|---|
| Subtotal | 9,22 € |
| Taxa de serviço (5%) | 0,46 € |
| Entrega | 2,50 € |
| Saco para viagem | 0,30 € |
| **Taxa de pedido pequeno** | **1,39 €** |
| **Total** | **13,87 €** |

**Acima do mínimo (sem taxa)** — dois Big Bowls:

| linha | valor |
|---|---|
| Subtotal | 23,10 € |
| Taxa de serviço | 1,16 € |
| Entrega | 2,50 € |
| Saco | 0,30 € |
| Taxa de pedido pequeno | *não aparece* |
| **Total** | **27,06 €** |

Os valores do servidor (`pricing_calculate` em produção, medidos hoje) batem:
12,48 + 1,39 = 13,87 · e 27,06 sem taxa.

**Achado pequeno:** o getter `customerTotal` do lado do cliente soma doubles
sem arredondar (dá `12.480000000000002`). Ao cêntimo bate — e é ao cêntimo que
o cliente paga —, mas ficou registado no teste com um comentário.

---

## 3. PROVA — o repasse do parceiro continua a dar 7,90 e 9,90

```sql
SELECT id, price, partner_shelf_price, public.partner_store_share(price) AS repasse
  FROM products WHERE restaurant_id='goola-acai-guarda';
```

| produto | preço gravado | balcão | **repasse** |
|---|---|---|---|
| `goola-bowl` | 9,22 | 7,90 | **7,90** ✅ |
| `goola-big-bowl` | 11,55 | 9,90 | **9,90** ✅ |

A taxa **não toca nisto**, e isso está provado onde importa:
- `apply_order_financial_split` calcula o repasse a partir de
  `final_purchase_value`/`subtotal` — **nunca do total**.
- `compute_partner_weekly_settlement` soma `o.subtotal` e o ledger.
- O ganho do estafeta (`driver_earnings`) não é tocado em lado nenhum.

Logo: o acerto semanal e o extrato continuam a bater.

---

## 4. IDs DOS PAGAMENTOS REAIS — **não foram feitos**, e a causa é esta

Pediste cartão, MB Way e dinheiro reais na Goola. **Não é possível hoje**, e
não é por falta de configuração:

A loja está `coming_soon = true` — por decisão tua, até o dono confirmar. O
servidor faz cumprir isso. Tentei mesmo criar um pedido:

```
ERROR: P0001: STORE_COMING_SOON: Esta loja ainda nao esta a aceitar pedidos.
CONTEXT: PL/pgSQL function _coming_soon_guard_orders() line 14 at RAISE
```

Enquanto a loja estiver em "Em breve", **nenhum** método de pagamento passa —
nem dinheiro. É exactamente o comportamento que o Bloco 3.5 pedia.

Há ainda uma segunda razão, essa permanente: **eu não posso escrever dados de
cartão nem confirmar um MB Way**. São credenciais financeiras; é um clique
teu, não meu.

**Os três métodos estão prontos** para o minuto em que abrires a loja:

| método | como está |
|---|---|
| Cartão | `create-payment-intent` v34 · ACTIVE · `stripe-webhook` v34 ACTIVE |
| MB Way | `create-mbway-payment-intent` v27 · ACTIVE |
| Dinheiro | local, sem Edge Function |

A loja é `is_partner=true` e segue o fluxo de parceiro normal — não tem nada de
específico que impeça qualquer um dos três.

---

## 5. O QUE FICOU FEITO

### Bloco 1 — taxa de pedido pequeno (app inteiro)

- Vale para **todas as lojas e todas as categorias de entrega**
  (`restaurant` + `storeShopping`, parceiro e não-parceiro).
  Fora: takeaway, favores, transporte de compras, encomendas — nenhum tem
  subtotal de produtos.
- **Linha própria e visível** em PT-PT — `Taxa de pedido pequeno` — no
  carrinho, no checkout e no detalhe do pedido.
- Acima do mínimo a linha **não aparece de todo**.
- No carrinho, quando falta pouco:
  `Faltam 2,78 € para evitar a taxa de pedido pequeno` — é o que a Uber e a
  Glovo fazem, e é o que faz o ticket subir.
- **Servidor cobra por sua conta** (função `small_order_fee_calc` + trigger
  `orders_aa_small_order_fee`): o total não pode ser forjado pelo cliente.
  O nome do trigger começa por `aa` de propósito — os triggers BEFORE correm
  por ordem alfabética e este tem de correr **antes** do tecto dos 40 € em
  dinheiro.

**Não toquei em `pricing_service.dart`.** A taxa vive fora do
`OrderPricingBreakdown`, num serviço próprio (`lib/services/small_order_fee.dart`).
Nenhuma fórmula, comissão, markup ou ganho de estafeta foi alterado.

### Bloco 2 — painel admin (PT-BR)

- As três chaves passam a ser **editáveis com validação e auditoria**
  (`admin_update_setting` já regista em `admin_audit_log`). Rejeita valor
  fora da faixa ou com casas decimais, com mensagem em PT-BR.
- **Override por loja:** colunas novas `min_order_cents_override` e
  `small_order_fee_cents_override` em `restaurants`, com `CHECK` de sanidade.
  Cartão novo na ficha da loja, com botão "Voltar ao global".
  Vazio = `NULL` = usa o global (0 seria "esta loja nunca cobra", que é outra
  decisão).
- A Goola já era gerível como as outras: `about_text`, Instagram, Facebook,
  WhatsApp, takeaway, reservas, "Em breve" e o respectivo texto **já estavam**
  no painel (`admin_partner_detail_screen` + `admin_partners_screen`) —
  confirmado, não duplicado.

### Bloco 3 — Goola viva no app

- Loja `approved`, `is_partner=true`, `is_online=true`, horário 10h–22h todos
  os dias (chaves `mon`…`sun`, gravadas certas).
- Os dois bowls com os grupos certos: **3** acompanhamentos obrigatórios no
  Goola Bowl, **4** no Big Bowl, 17 itens a 0,00 em cada, e Extras opcional
  até 3 a 1,17 €. Confirmado por SQL.
- `vendorBlocksAddToCart` continua `false`: o cliente navega, escolhe opções e
  enche o carrinho — só para no ecrã de pagamento. A grelha de produtos não é
  bloqueada.
- **Morada preenchida sozinha** já estava feita (`lib/services/auto_address.dart`,
  commit `1809427`), com a regra de 24/08 escrita no próprio ficheiro: a
  localização **nunca trava** o pedido; se o GPS falhar, o campo fica vazio e
  escrevível, sem erro nem pop-up.

### Adendo — categoria Sobremesas

- `sobremesa` no enum, "Sobremesas" para o cliente (PT-PT).
- Ladrilho novo na home, roxo-açaí, com ilustração cartoon no mesmo estilo do
  das Festas. **Foi desenhada a código** (`tools/gen_cat_sobremesas.py`) —
  o gerador de imagens ficou sem créditos, e assim fica determinística e
  regenerável.
- A listagem **reutiliza o filtro que já existe** (`belongsTo`), o mesmo que
  põe o Sabores de Casa dentro de Mercados. Não reescrevi nada.
- Fluxo de compra **normal**: pedido imediato, sem calendário. Nada copiado
  das Festas.
- Admin: a categoria aparece nos filtros, rótulos e no editor de loja (PT-BR).

**Prova pedida — a Goola nas duas listas:**

```sql
SELECT 'RESTAURANTES', count(*) FROM restaurants
 WHERE (category='restaurant' OR 'restaurant' = ANY(extra_categories)) AND id='goola-acai-guarda'
UNION ALL SELECT 'SOBREMESAS', count(*) FROM restaurants
 WHERE (category='sobremesa'  OR 'sobremesa'  = ANY(extra_categories)) AND id='goola-acai-guarda';
```

| lista | count |
|---|---|
| aparece em RESTAURANTES | **1** |
| aparece em SOBREMESAS | **1** |

E por teste: `flutter test test/categoria_sobremesas_test.dart` → **9/9 verdes**,
incluindo o caso que separa este padrão do das Festas (que fica só numa).

### Bloco 4 — mini-site de presente

- **No ar:** <https://goola-guarda.pages.dev>
- **Pasta:** `C:\Users\danil\Desktop\projetosflutter\goola-site\`
  — em git local, commitado no mesmo dia (`05a9027`). Não se perde como os da
  BeUnique e do Sabores de Casa.

Método seguido sem saltar passos: 4 referências recolhidas → design system
extraído **das fotos oficiais por código** (não a olho) → prompt de 200 linhas
(`PROMPT.md`) → construção a partir do prompt → **segunda ronda**.

**A segunda ronda valeu a pena.** Apanhou três coisas:
1. As fotos estavam **todas trocadas** — o cartão do "Goola Bowl" mostrava um
   liquidificador e a secção dos 17 acompanhamentos mostrava uma mão com um
   copo. O mapeamento estava deslocado uma posição.
2. O mapa ficava como **caixa branca** quando o iframe não carregava. Agora tem
   a morada desenhada por baixo, sempre.
3. A foto dos acompanhamentos não preenchia a coluna.

Imagens: **reais da marca** (goolaacai.com), tratadas antes de entrarem
(recorte, contraste 1.06, saturação 1.08, nitidez, WebP q82) e **embutidas em
base64** — 500 KB no total, muito abaixo dos 25 MiB. Logo em SVG transparente
(melhor que PNG: é vetorial e escala sem perder).

Auditoria feita **depois** de a Cloudflare assentar, e ao **conteúdo**, não só
ao código:

```
https://goola-guarda.pages.dev/              HTTP 200  500740 bytes
https://goola-guarda.pages.dev/robots.txt    HTTP 200
https://goola-guarda.pages.dev/sitemap.xml   HTTP 200
https://goola-guarda.pages.dev/rota-inexistente  HTTP 404  → "Esta página não existe"
```

Conteúdo verificado no HTML servido: "9,22" ✓ · "11,55" ✓ ·
"PEÇA PELO BORA APP" ✓ · "La Vie Guarda" ✓ · "Leite condensado" ✓ ·
"Whey Protein" ✓ · "10h00 às 22h00" ✓ · 13 imagens em base64 ✓

Renderizado a 1440, 390 e **360 px**: 0 imagens quebradas, 0 erros de
JavaScript, **sem scroll lateral em nenhuma largura**. Capturas em
`goola-site/provas/`.

---

## 6. O QUE FALHOU OU FICOU POR FAZER

| O quê | Porquê |
|---|---|
| **Cobrar mesmo a taxa** | A Trava protege `pricing_calculate` — é a Lista Vermelha. Ficheiro pronto, espera o teu "vai". |
| **Pagamentos reais (cartão / MB Way / dinheiro)** | A loja está em "Em breve" e o servidor rejeita qualquer pedido (erro colado no §4). E escrever dados de cartão é acção humana, não minha. |
| **NIF, IBAN, telefone, e-mail do dono** | Não os temos. Não inventei nem os pus no site. |
| **Fotos próprias do quiosque da Guarda** | O site usa as oficiais da marca. Quando tiveres fotos do quiosque, trocam-se em `goola-site/assets/`. |
| **Pote de 1 litro** | Por confirmar com o dono. |
| **Repo remoto do mini-site** | Está em git **local**. Falta criar o repo privado no GitHub — é um login, acção tua. |

### Achado que não é meu, mas que devias saber

O teste `test/order_eta_service_distance_test.dart` **já falhava antes desta
sessão** — "restaurantes com coordenadas diferentes dão distâncias diferentes",
esperava 4 distâncias distintas e obtém 2.

Prova de que não fui eu: nem o teste nem `lib/services/order_eta_service.dart`
aparecem no `git status` (intactos), e o último commit neles é o `290ba56`,
antigo. Falha igual quando corrido isolado. **Deixei-o como está** — está fora
do que pediste; diz se queres que trate disso.

Resto da suite: **225 verdes**. `flutter analyze`: **0 erros**.

---

## 7. AVISO SOBRE O PUSH

O push nesta branch **é publicação**: dispara build Android → Google Play
(internal, alpha **e produção**) e o deploy do web app. Vai código Flutter a
sério neste commit, por isso o build vai mesmo correr.

O `versionCode` não foi tocado — o CI incrementa-o sozinho, como deve ser.

---

## 8. FICHEIROS

**Servidor (aplicado):** `supabase/migrations/20260827130000_taxa_pedido_pequeno.sql`
**Servidor (à espera de "vai"):** `supabase/migrations/20260827131000_PROPOSTA_taxa_pedido_pequeno_pricing.sql`

**Cliente:** `lib/services/small_order_fee.dart` (novo) ·
`lib/screens/sobremesas_screen.dart` (novo) · `cart_store` · `cart_screen` ·
`payment_method_screen` · `order_details_screen` · `order_model` ·
`restaurant_model` · `business_mapper` · `client_home_screen` · `app_colors` ·
`restaurants_screen` · `stores_screen` · `reorder_service` · `main`

**Admin:** `admin_platform_settings_screen` · `admin_partner_detail_screen` ·
`admin_partners_screen` · `_admin_partner_edit_dialog`

**Testes:** `test/taxa_pedido_pequeno_test.dart` (17) ·
`test/categoria_sobremesas_test.dart` (9)

**Arte:** `assets/categories/cat_sobremesas.png` + `tools/gen_cat_sobremesas.py`

**Mini-site:** `C:\Users\danil\Desktop\projetosflutter\goola-site\`
