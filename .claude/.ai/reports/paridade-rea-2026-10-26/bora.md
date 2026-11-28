# Bora visto da mesma maneira — 26/10/2026, 06:55–07:20

Usei o mesmo Chrome da missão, sem conta, em `app.boraguarda.com`. O `versao.json` no ar aponta
para o commit 99a23ad2, run 240, que é o mesmo código que os verificadores leram.

Prints: `Desktop\Bora\paridade-rea-2026-10-26\bora_*.png`. Observação REA da nossa própria app
(aqui é permitido usá-lo por dentro): `rea\bora_carrinho_inspect.json`, com a árvore de
acessibilidade e as mensagens da consola. Não guardei cookies nem valores.

Ao mesmo tempo, três verificadores só de leitura percorreram o código (cliente, parceiro, admin), e
consultei o banco pelo MCP. Cada achado tem ficheiro e linha.

## 1. O que se vê sem conta

A entrada mostra "Sou Cliente / Sou Estafeta / Sou Parceiro", a escolha de idioma PT/EN e o aviso
de cookies (bora_01).

**"Sou Cliente" vai direto para "Iniciar sessão"** (bora_02). Sem conta, não se vê a página
inicial, nem as lojas, nem os preços. A Glovo e a Uber Eats deixam ver tudo isto e só pedem conta
no fim.

A ligação partilhada `/#/loja/burgerking-guarda` abre a loja sem conta (bora_03). Mostra:
- capa, nome e selo "Frescura garantida";
- "5-20 min ETA" e "€2.50 Entrega";
- pesquisa dentro da loja ("Procurar em Burger King…");
- "Comprar por categoria", separadores Loja / Categorias / **Pedir de novo**;
- botão flutuante "Bora Assistente" e "Suporte Bora".

Problemas nesta página:
- **Às 06:55 a loja estava fechada** (no banco, `business_hours` = 11:00–23:00), mas o ecrã não diz
  "fechado". Mostra "5-20 min" como se estivesse aberta.
- **Em ecrã de computador (1440 px)** a foto do produto ocupa o ecrã todo, e as opções e o botão
  ficam escondidos (bora_05_produto_1440). O ecrã não está preparado para ecrãs largos.

No produto, em telemóvel (bora_06_produto_detalhe_390):
- nome, aviso de alergénios ("Consulte o estabelecimento…");
- grupos "Opcional · Escolhe até 4", com a contagem "Escolheste 0 de 4";
- preço de cada extra, quantidade −/+ e o botão "Adicionar ao carrinho · €9.65".

No carrinho (bora_08/09/10):
- linha com −/1/+ e caixote;
- "Ir buscar (takeaway, sem entrega)", "Entregar no apartamento (+€1.50)";
- Subtotal, Taxa de serviço, Entrega, Saco para viagem;
- gorjeta 1/2/3/5 €, "Outro valor", "Sem gorjeta" e o total.

Testei 1→2→1→0 e respondeu sem falhas.

**"Finalizar pedido" sem conta não faz nada** (bora_11): nem passa ao passo seguinte, nem mostra
mensagem. A causa está em `lib/screens/complete_profile_screen.dart:184`: sem cliente com sessão,
`garantirContactoDoCliente` devolve `false` em silêncio. Na Glovo e na Uber Eats, o mesmo botão
leva ao ecrã "entra ou cria conta".

A consola da nossa app (REA) mostra a causa de fundo:

```
AuthStore: guest sign-in failed => Invalid login credentials (400)
AuthStore: guest session FAILED => User already registered (422)
```

**Este erro já estava registado a 08/09** (memória `sessao-de-convidado-partida-em-producao`) **e
continua hoje, 7 semanas depois.** Sem sessão, ficam também sem leitura:
- a taxa de pedido pequeno ("SmallOrderFee… sem sessão");
- as taxas remotas ("RemoteFees… fica 99c / risco 250c"), por isso os valores mostrados ao visitante
  são valores de recurso;
- os prémios do check-in (`client_checkin_premios`: permission denied 42501, repetido).

## 2. O que o cliente tem, segundo o código (verificador 1)

**a) Início**
- Morada automática: carrinho → morada guardada → "Casa" → GPS (`client_home_screen.dart:250-302`).
- **Pesquisa única** de lojas e produtos (`global_search_screen.dart`, RPC `cliente_pesquisar`).
- 14 ladrilhos (incluindo Favores, Reservar mesa, Limpeza, Motorista, Festas, Lavagem).
- Faixas `home_banners`.
- Secções "Pede outra vez", "Os mais pedidos", "Novidades".
- Faltam:
  - os **cartões da página inicial só têm foto, nome e cozinha**, sem tempo, taxa, nota,
    promoção nem distância (`home_feed.dart:533-616`);
  - **não há filtros nem forma de ordenar**.

**b) Listas**
- Restaurantes: pesquisa por nome, ordem fixa (abertos primeiro, depois alfabética), cartão com
  tempo, km, taxa e estrelas. **Sem filtros e sem escolher a ordem** (`restaurants_screen.dart`).
- Mercados: ordenar por nome ou avaliação.

**c) Loja**
- Tem: capa, logótipo, estrelas, tempo, taxa, favorito, separadores, pesquisa no menu, botão de
  reservar mesa.
- **Promoções e destaques nunca aparecem**: `is_popular`, `is_on_sale` e `discount_price` são
  carregados (`restaurant_store.dart:233-235`) mas nenhum ecrã os mostra.
- **Não há ficha da loja** com horário, mínimo e morada.

**d) Produto**
- Tem uma foto, alergénios, extras obrigatórios e opcionais com mínimo e máximo, quantidade, e
  variantes "Mais barato / Premium".
- **Não há nota por artigo**: só existe a nota do pedido, no ecrã de pagamento.

**e) Carrinho**
- Tem: pôr, mudar quantidade e tirar; aviso ao trocar de loja; taxas detalhadas; "Faltam X € para
  evitar a taxa / para a entrega grátis"; gorjeta; carteira.
- Falta:
  - botão para esvaziar;
  - sugestões do tipo "leve também";
  - um carrinho por loja.

**f) Finalizar**
- Tem: contacto obrigatório, Tokens, "deixar à porta", nota do pedido, Cartão / MB Way / Dinheiro,
  cartões guardados, recolha na loja com código e curbside.
- Falta:
  - **a morada não aparece nem se pode trocar no checkout** (só bloqueia se estiver vazia);
  - **campo de cupão no checkout**: o código promocional só se converte em tokens, no Perfil;
  - **agendar entregas normais**: só as Festas podem ser agendadas.

**g) Depois do pedido**
- Mapa com o estafeta ao vivo, ETA, partilhar o seguimento, chat com a loja e com o estafeta, PIN,
  cancelar com escolha do reembolso.
- Avaliação 48 h depois, "Pedir de novo", reportar problema com foto, suporte (FAQ, robô, email,
  telefone).
- Livro de Reclamações em Perfil → Informação legal (escondido).

## 3. Parceiro (verificador 2) e admin (verificador 3)

**Parceiro**
- Tem:
  - produtos com foto e alergénios; extras com mínimo e máximo;
  - **pausar a loja** 15/30/60 min ou até fechar; **esgotado só hoje / sem data** (volta sozinho);
  - horário e dias fechados; tempo de preparação ao aceitar;
  - som persistente; ganhos, fecho semanal e extrato em PDF;
  - chamar estafeta; acrescentar produto ao pedido (interruptor desligado).
- Não tem:
  - **modo ocupado** (+X min em todos os pedidos);
  - **mudar a hora de pronto** depois de aceitar;
  - impressão automática do talão;
  - alerta de atraso; pausa automática quando falha vários pedidos;
  - **responder a avaliações**;
  - descrições ou resumos feitos por IA;
  - **promoções criadas pelo parceiro**;
  - página web "para restaurantes".

**Admin** (150 ecrãs)
- Faltam ecrãs para:
  - favoritos;
  - **alergénios** (o admin não os vê nem corrige: risco legal);
  - editar e reativar cupões e ver quem os usou;
  - interruptor geral de agendados, de recolha e das faixas;
  - responder ou ocultar avaliações;
  - compensar a partir de uma reclamação.

## 4. O que existe no banco (SELECT de 26/10)

Contagens:
- client_favorites: 6;
- pedidos com `scheduled_for`: 0;
- pedidos de recolha (código de levantamento): 0;
- tips: 1;
- promo_codes: 8;
- home_banners: 4;
- assistant_cart_proposals: 41;
- lojas: 28, das quais 5 são parceiras;
- pedidos nos últimos 30 dias: 36, dos quais 17 entregues.

Ou seja, a recolha e o agendamento existem mas não são usados, e o assistente de carrinho é a
função "extra" mais usada.

## 5. Verificações de dinheiro — SÓ RELATO (zonas protegidas, não toquei)

- **O total é recalculado no servidor:** SIM. O `create_order` soma `products.price` com os extras
  e aplica `pricing_calculate`.
- **Buracos no create_order:**
  - Se o `product_id` não existir, aceita o preço enviado pela app (migração 20261004194537,
    linhas 464-465).
  - O preço não é filtrado pela loja do pedido.
  - O `distance_km` vem do cliente.
- **Dinheiro em cêntimos:** é misto. Os pedidos estão em NUMERIC (euros); a carteira, os tokens e
  a gorjeta estão em cêntimos; a app usa double.
- **Toque duplo:**
  - Com cartão está protegido (índice único no payment_intent).
  - **Em dinheiro não há chave de idempotência no servidor**. Confirmado por SQL: no
    `create_order` só a `wallet_transactions` tem `idempotency_key`. Só a app trava o segundo
    toque.
- **Preços congelados:** em parte. O `orders.items` (JSONB) guarda o preço enviado pela app, mais
  os extras com o preço do servidor.
- **Trocar de loja avisa:** sim, mas compara a loja pelo **nome**. O próprio `create_order`
  procura a loja por nome (`WHERE name = v_vendor_name`, confirmado por SQL). Hoje não há nomes
  repetidos (0 em 28), por isso o risco é latente.
- **Produto esgotado:**
  - Some do menu.
  - **O create_order não verifica `is_available`** (0 ocorrências na função de 33 717 caracteres,
    confirmado por SQL).
  - O carrinho não volta a verificar.
  - O "Pedir de novo" repõe artigos esgotados.
- **A confirmar:** no carrinho do BK, que é não-parceiro (`is_partner=false`), aparece "Taxa de
  serviço 0,48 €" (5% do subtotal) além da entrega de 2,50 €. A secção 2.2 do
  `business_rules.md` diz que os não-parceiros não têm taxa em percentagem. Pode ser o valor de
  recurso da app sem sessão (ver ponto 1), ou o servidor cobrar mesmo assim. **Não mexi. Fica para
  a Claude.ai ou o Danilo verem.**

## 6. O que o Bora tem A MAIS (não estragar; usar na propaganda)

- Reserva de mesa com pré-pagamento e lista de espera (o iFood só lançou isto em junho de 2026, e
  só em São Paulo).
- Favores, Enviar encomenda, Levar compras, TVDE com planos, Limpeza, Lavagem, Beleza, Festas.
- Check-in diário com prémios, Receita do Dia que enche o carrinho, Bora Tokens, carteira.
- **Assistente que monta o carrinho a partir de uma lista ou foto e divide por lojas.**
- **Pesquisa que mostra produtos e não só lojas** (a Glovo e a Uber Eats mostram só lojas).
- Gorjeta 100% para o estafeta, partilhar o seguimento, "deixar à porta", curbside, +18.
- Comissão ao parceiro muito abaixo da Glovo (30%) e da Uber Eats (30% + 3,49 €/semana).
- Pausa da loja "até fechar", com volta automática; esgotado "só hoje".
