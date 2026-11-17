# Teste 1.2 — pedido na Farmácia da Sé, do princípio ao fim, em dinheiro (16/11/2026, ~19:40 Lisboa)

Feito por um ajudante do Claude Code na missão noite-farmacia-17-11. Tudo correu na base de produção
(ojykpzwqrtusfeakzrna) dentro de transações que acabam desfeitas (bloco DO que termina com `raise exception`
com o resultado em JSON). No fim conferi por SELECT que nada ficou: o pedido de teste
aac8067c-9d49-45f5-a53a-18b9ba05f1bb não existe, 0 pedidos e 0 receitas do cliente demo, a lista de permissão
da Sé continua com 3 contas, o estafeta demo continua desligado, 0 linhas em order_edits e em
pedido_chegada_tardia. Não houve dinheiro real, nem Stripe, nem navegador, nem palavras-passe.

**VEREDITO: 1.2 VERDE** (com uma ressalva: na loja escondida o "entregue" fecha como "cancelado — demonstração
concluída, sem custo", por isso os gatilhos de dinheiro do entregue — ganhos, livro, fatura — não correram; isso
só se prova quando a loja abrir ao público).

## Quem fez cada papel

- Cliente: demo.cliente@bora.app (e3c166d2…), conta de demonstração. Não está na lista de permissão da Sé; meti-a
  na lista DENTRO da transação com a função do painel `admin_loja_lista_permissao_definir` (como admin), e saiu
  no fim com o resto. A lista real tem 3 contas: a conta da Bora, a conta do Danilo e uma pessoa da
  Gripharma (nenhuma é de teste, por isso não as usei como cliente).
- Farmácia: a conta dona da Sé (9b218f1a…), só pelo identificador na sessão, sem palavra-passe. Só a dona pode
  aceitar e marcar em falta (`_partner_owns_order`).
- Estafeta: Estafeta Demo (user dede0000-…-0001, drivers.id dede0000-…-0002), que estava desligado desde 29/10.

## O caminho (só as funções que a app chama)

A app cria o pedido pela função `create_order` (lib/stores/order_store.dart:1052), não por INSERT direto. A Sé,
por ser parceira, vai como tipo `restaurant` (lib/screens/stores_screen.dart:406-408).

1. `quote_order_pricing` (o orçamento do carrinho) e `create_order` como cliente, dinheiro, 3 produtos:
   Ben-u-ron Direct 5,82 + Sensodyne fio dentário 4,03 + CeraVe creme de mãos 6,38 = 16,23 €. Morada a 1,5 km em
   linha reta; mandei 1,97 km (como a rota). Resultado: pedido criado, `is_test_order = true`, estado `created`.
2. Farmácia aceita com `partner_aceitar_pedido` (15 min de preparação, como no painel): estado `preparing`.
3. Farmácia marca o Sensodyne em falta: `order_edit_quote` e depois `partner_propose_order_edit` com
   `tipo = remove` (o botão "Marcar em falta"). Aplicou logo: "total a cobrar na entrega desceu 2,84 €".
4. Estafeta: a SQL não consegue chamar o despacho (é uma Edge Function), por isso fiz o caminho permitido:
   o estafeta demo mandou posição e batimento (`driver_update_location`, `driver_heartbeat`, como a app),
   o admin ligou-o (`admin_set_driver_online`), e `ops_reassign_order(..., 'claude-code')` SEM forçar
   pré-atribuiu o pedido (estava em preparação). Quando a farmácia carregou "pronto" (`partner_mark_ready`)
   o gatilho passou a pré-atribuição a oferta ao estafeta demo.
5. Estafeta: `driver_accept_offer` → `driverAccepted`; `driver_advance_order` → `pickedUp` → `onTheWay`;
   `driver_validate_delivery_pin` com o código certo → aceite.
6. Fecho: o gatilho da loja em demonstração (`_demo_loja_sem_entrega`) trocou "entregue" por "cancelado",
   motivo "Demonstracao concluida: entrega simulada, sem custo", taxa de cancelamento 0. Livro (ledger) do
   pedido: 0 linhas.

## Os números, contra as regras

Regras das farmácias (lidas no servidor: `pricing_calculate_loja`, `small_order_fee_calc`,
`partner_store_share`; e no carrinho: `cart_store.dart` 664-688 e `small_order_fee.dart`):
preço do produto = preço do balcão/Glovo e a farmácia recebe tudo; cliente paga entrega 2,50 € (até 4 km)
+ taxa de serviço 0,99 € + 5 % do subtotal (numa linha) + 1,39 € se o pedido for abaixo de 15 €; sem saco;
sem entrega grátis; sem comissão no pedido.

Ao criar (3 produtos):
- subtotal 16,23 € (regra 16,23) — certo
- entrega 2,50 € (regra 2,50; 1,97 km < 4 km) — certo
- taxa de serviço 1,80 € (regra 0,99 + 5 % × 16,23 = 0,99 + 0,81 = 1,80) — certo
- pedido pequeno 0,00 € (16,23 ≥ 15) — certo
- saco 0,00 € (regra das farmácias: sem saco; bag_count fica 1 mas o valor é 0) — certo
- total 20,53 € (orçamento do carrinho também 20,53) — certo; em dinheiro a cobrar 20,53
- comissão 0, margem escondida 0 — certo (os 10 % só começam 3 meses depois de a loja abrir:
  `partner_extra_commission_starts_at` está vazio e `admin_farmacia_abrir` põe agora + 3 meses)
- farmácia recebe 16,23 €
- ganho do estafeta 4,19 € (regra 3,80 + 0,20 × 1,97 km = 4,19) — certo

Depois de marcar o Sensodyne em falta (2 produtos):
- subtotal 12,20 € (16,23 − 4,03) — certo
- taxa de serviço 1,60 € (0,99 + 5 % × 12,20 = 0,99 + 0,61) — certo
- pedido pequeno 1,39 € (12,20 < 15, entra sozinho) — certo
- entrega 2,50 €, saco 0,00 € — certo
- total 17,69 € (12,20 + 1,60 + 2,50 + 1,39); diferença −2,84 € dita ao cliente — certo
- farmácia recebe 12,20 €; comissão 0 — certo
- ganho do estafeta 4,19 € (não muda) — certo
- no fecho ficaram estes mesmos valores na linha do pedido.

Nota (só informação, não mexi): com estas regras a Bora fica com taxa de serviço + pedido pequeno + entrega
− estafeta: 1,80 + 0 + 2,50 − 4,19 = 0,11 € no pedido de 16,23 €, e 1,60 + 1,39 + 2,50 − 4,19 = 1,30 € depois da falta.

## a) Pedido acima de 40 € em dinheiro

7 × CeraVe = 44,66 € de produtos, total 50,38 € (taxa 3,22 + entrega 2,50). O orçamento devolve 50,38 e o
`create_order` é recusado pelo gatilho `enforce_cash_payment_limit`:
"CASH_LIMIT_EXCEEDED: pagamento em dinheiro disponivel apenas ate 40.00 EUR (pedido = 50.38 EUR)".
`max_cash_amount_cents` = 4000.

O que a app mostra hoje (este ramo e o ramo principal): o botão Dinheiro fica apagado com
"Pagamento em dinheiro só até 40 €. Este pedido fica em 50,38 €. Escolhe Cartão ou MBWay."
(payment_method_screen.dart:527) e, se o servidor recusar, "Pagamento em dinheiro só até 40 €. Escolhe
Cartão ou MBWay." (payment_method_screen.dart:1241-1243).
A mensagem nova do commit a38d9418 (caixa amarela "… Este pedido fica em {1} €. Paga com MB Way ou cartão."
e aviso ao tocar no Dinheiro apagado) só está no ramo origin/ai/2026-11-16-dinheiro-dividido: NÃO está no
ramo principal nem nesta árvore.
Atenção: enquanto a Sé estiver escondida, os pedidos de teste só passam em dinheiro (gatilho
`_loja_escondida_so_pedidos_teste`: "LOJA_EM_DEMONSTRACAO"), por isso um teste acima de 40 € na Sé é
impossível — nem dinheiro nem cartão.

## b) "Chega mais tarde (2-4 h)"

Funciona na Sé. Num pedido `restaurant` da Sé, `farmacia_chegada_marcar` (como a app manda: hora, linha 1,
sem minutos) aceitou: a hora ficou em `scheduled_for`/`ready_at_promised`. O cliente respondeu "tirar" com
`farmacia_chegada_responder`: ficou `estado = tirar` e a hora voltou ao que estava.
Num pedido `storeShopping` da Sé recusa com "PEDIDO_NAO_SERVE: Só nos pedidos com entrega feitos na app."
O bloqueio está na função SQL `farmacia_chegada_marcar`
(`if not v_o.parceira or coalesce(v_o.service_type, '') <> 'restaurant'`) e na app em
lib/widgets/partner/farmacia_painel.dart:378-382 (`podeMarcar` exige `OrderServiceType.restaurant`).
A Sé não usa storeShopping (parceira vai como restaurant desde 11/11), por isso para ela não há bloqueio.
Duas coisas a saber:
- "Tirar" não tira o produto sozinho: só avisa a farmácia "tire … em Marcar em falta". O pedido ficou com os
  3 produtos e 20,53 € até a farmácia carregar no botão.
- A hora não é conferida com o horário da loja: marquei 21:42 (Lisboa) e a Sé fecha às 21:00; aceitou.

## c) Botão "Tenho receita"

- `pharmacy_prescription_real_orders_enabled` = false. Modo da receita da Sé = `so_lista`
  (restaurants e `admin_farmacias_listar`). Consentimento v1-2026-11-11, texto com o nome "Farmácia da Sé",
  15 minutos para responder, taxa 6,00 €.
- Para o cliente demo (na lista): `farmacia_botoes_visiveis` = verdadeiro.
- `prescricao_criar` com a versão velha do consentimento: recusado "AUTORIZACAO_DESATUALIZADA" (certo).
- Receita (número + código de acesso de teste, assinatura do próprio cliente, consentimento v1) → criada;
  farmácia aceita 12,50 € com `prescricao_responder` → cliente confirma em dinheiro com
  `prescricao_confirmar` → total 18,50 € (12,50 + 6,00), códigos de levantamento e de entrega criados,
  `is_demo = true` → a farmácia fecha com `farmacia_prescricao_fechar_demo` → `entregue`.
- Pedido livre → farmácia responde "não tenho" (`sem_stock`, volta a ter "amanhã") → `recusado`.
- "Estafeta levanta": não existe esse passo hoje. Em demonstração não há pedido nem estafeta (order_id vazio,
  0 pedidos criados); quem fecha é a farmácia ("marcou o pedido como levantado"). Em loja aberta ao público
  `prescricao_confirmar` recusa sempre com "RECEITA_REAL_POR_LIGAR".
- Incoerência encontrada: `prescricao_confirmar` recusa a loja pública SEM olhar para
  `pharmacy_prescription_real_orders_enabled`, mas `farmacia_botoes_visiveis` mostra o botão em loja pública
  quando essa definição for true. Se alguém a ligar antes de existir o pedido real, o cliente vê o botão e
  falha no fim.

## d) "Esqueci-me da palavra-passe" na porta Sou Parceiro (só código, nada corrido)

Não há teste automático deste caminho.
- integration_test/varredura_ecras_test.dart:394-397 abre "Esqueci-me da palavra-passe" pela porta
  Sou Cliente e só confere que o ecrã desenha; não envia nada e não passa pela porta do parceiro.
- test/entrada_google_cliente_test.dart:404 abre o PartnerLoginScreen mas só confere que não há Google/Apple.
- Nenhum teste toca em ForgotPasswordScreen nem em `AuthStore.resetPassword`.
O que falta para um teste em código: um teste de ecrã que abra lib/screens/partner_login_screen.dart, toque
no botão (linha 263-264), confirme que abre o ForgotPasswordScreen com o e-mail já escrito
(`initialEmail`, linhas 308-313) e mostre a frase certa para cada resultado de `resetPassword`
(lib/auth/auth_store.dart:1458: ok, rateLimited, emailNotSent, failed). Para isso o AuthStore precisa de poder
ser trocado por um falso: hoje usa `Supabase.instance.client` direto (auth_store.dart:150).

## O que falhou

No pedido completo em dinheiro: nada. Encontrado pelo caminho:
1. O fecho real (entregue com ganhos, livro e fatura) não se pode provar com a loja escondida: o pedido de teste
   fecha como cancelado sem custo, de propósito.
2. O despacho verdadeiro (Edge Function a oferecer só ao estafeta demo) não foi testado; usei a pré-atribuição
   por `ops_reassign_order` (sem forçar).
3. Mensagem nova do limite de 40 € (a38d9418) ainda fora do ramo principal; teste acima de 40 € na Sé escondida
   é impossível.
4. "Chega mais tarde": storeShopping bloqueado (não afeta a Sé); "tirar" depende de a farmácia marcar em falta à
   mão; hora não conferida com o horário de fecho.
5. Receita: sem passo de estafeta; a definição `pharmacy_prescription_real_orders_enabled` não é lida na
   confirmação (só no botão).
6. "Esqueci-me da palavra-passe" do parceiro sem teste automático.
7. Pequeno: se as definições não carregarem, o carrinho da farmácia mostra só os 5 % (0,81 € em vez de 1,80 €)
   antes do orçamento do servidor (cart_store.dart:677, `taxaFarmacia ?? base.serviceFee`); o servidor cobra
   certo. O pricing_service.dart (zona protegida, só lido) não tem ramo de farmácia.
