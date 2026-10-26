# PLANO de melhorias do Bora — missão paridade-rea-2026-10-26

> Está escrito e PARADO. Nada daqui foi implementado. O código só se mexe depois de a Claude.ai
> rever o plano (regra do Danilo).
>
> Baseia-se em glovo.md, ubereats.md, ifood.md e bora.md desta pasta, com os prints em
> `Desktop\Bora\paridade-rea-2026-10-26\`.
>
> Regras seguidas no plano:
> - Só entra o que a Glovo, a Uber Eats ou o iFood já têm. Nada é inventado.
> - Mantém-se tudo o que é do Bora: verde #16A34A, laranja #F97316, letra Inter, fotos reais dos
>   produtos intocadas. Nada do vermelho do iFood. Nenhum texto copiado.
> - As apps do cliente, estafeta e parceiro em PT-PT; o painel em PT-BR.
> - Nenhum item muda preços, comissões ou taxas.
> - TVDE fica de fora.
>
> Ordem: primeiro o que faz o cliente comprar mais e com menos esforço, sem tocar em dinheiro;
> depois a loja e o parceiro; no fim, o que mexe em dinheiro ou no despacho, marcado
> "precisa do autorizo do Danilo".
>
> Tamanhos: P = até meio dia; M = 1 a 2 dias; G = mais de 2 dias.
>
> Como provar cada item, sempre nas 3 plataformas:
> - **Android:** APK do CI, com conta demo e pagamento em dinheiro, sem acordar estafetas reais.
> - **iPhone:** TestFlight.
> - **Web:** app.boraguarda.com, confirmando o commit no `versao.json` antes de olhar.
> - Para cada uma: print antes e depois, e o e2e_log.

---

## A. O cliente compra mais e com menos esforço (sem dinheiro)

### 1. "Finalizar pedido" sem conta leva a "Entrar ou criar conta" e volta ao carrinho
- **O que é:** hoje, quem chega pela ligação de uma loja enche o carrinho, carrega em Finalizar e
  não acontece nada. Passa a abrir o ecrã de entrar ou criar conta e, depois, a voltar ao mesmo
  carrinho, com tudo lá dentro.
- **Quem tem:** a Glovo (print glovo_17) e a Uber Eats (print ubereats_14). As duas pedem conta
  exatamente neste passo.
- **O que muda no Bora:**
  - `lib/screens/complete_profile_screen.dart:184` (`garantirContactoDoCliente`): sem sessão,
    abre o login do cliente em vez de devolver `false` calado.
  - `lib/screens/cart_screen.dart:649`.
  - O carrinho já vive no `CartStore` e não se perde.
- **Painel admin:** nos KPIs (`admin_advanced_kpis`), um contador "carrinhos que pediram conta /
  que acabaram em pedido".
- **Tamanho e risco:** P. Não toca em dinheiro. Toca no ecrã de autenticação (zona sensível, não
  protegida).
- **Prova:** sem conta, abrir `/#/loja/<id>`, pôr um artigo, carregar em Finalizar → aparece o
  login; entrar com a conta demo → volta ao carrinho com o mesmo artigo. Repetir em Android e
  iPhone com a ligação partilhada.

### 2. Ver a app sem conta: página inicial, lojas e preços (e reparar a sessão de convidado)
- **O que é:** "Sou Cliente" deixa explorar antes de pedir conta. Para isso é preciso reparar a
  sessão de convidado, que está partida desde 08/09: a consola mostra 400 e 422 no
  `guest@bora.com`. Sem ela, o visitante não lê as taxas reais, e os valores mostrados são valores
  de recurso.
- **Quem tem:** a Glovo (glovo_01 a 06) e a Uber Eats (ubereats_01 a 06) mostram lojas, menus e
  preços sem conta.
- **O que muda no Bora:**
  - `lib/auth/auth_store.dart`, no `_ensureGuestSession`: trocar a conta partilhada pela entrada
    anónima do Supabase, que já existe em `lib/services/auth_service.dart:20`, ou repor a
    palavra-passe pelo cofre.
  - A rota "Sou Cliente" em `lib/main.dart`.
  - É preciso rever as RLS que hoje dependem de "authenticated", sem abrir dados de clientes.
- **Painel admin:** interruptor "visitantes podem explorar sem conta" em
  `admin_platform_settings`, mais o número de visitantes no dashboard.
- **Tamanho e risco:** M. É autenticação e RLS, mas **não** das tabelas de dinheiro. O
  classificador já recusou remendos de autenticação antes, por isso tem de ser feito com cuidado e
  revisto pelo Juiz.
- **Prova:** sem conta, a consola sem "guest session FAILED"; o carrinho mostra as taxas reais do
  servidor, iguais às do `quote_order_pricing`.

### 3. Loja fechada diz que está fechada e sugere lojas abertas
- **O que é:** às 06:55 o Burger King aparece com "5-20 min" quando só abre às 11:00. Passa a
  mostrar "Fechado · abre às 11:00" no topo da loja e uma janela com "Ver lojas abertas
  parecidas".
- **Quem tem:** a Glovo (glovo_10 e glovo_20: "está fechado até 11:00 — há estabelecimentos
  semelhantes abertos").
- **O que muda no Bora:** `lib/screens/restaurant_menu_screen.dart` e `deep_link_store_screen`
  passam a usar o `business_hours` e o `pausa_ate` que já existem. A lógica de "aberto" já está no
  cartão da lista (`restaurants_screen.dart:575`) e é só reutilizá-la.
- **Painel admin:** o horário já se edita em `admin_partner_detail`. Acrescentar a coluna "aberta
  agora?" em `admin_partners`, para ver a mesma verdade que o cliente vê.
- **Tamanho e risco:** P. Não toca em dinheiro.
- **Prova:** abrir a loja fora de horas → aparece "Fechado"; abrir dentro do horário → aparece o
  tempo normal.

### 4. Ficha "Informações da loja": morada, horário de cada dia e taxa
- **O que é:** um botão (i) no topo da loja abre a morada, o horário da semana e as taxas.
- **Quem tem:** a Glovo ("Dados do estabelecimento", glovo_11) e a Uber Eats ("Toque para ver o
  horário de funcionamento", ubereats_06).
- **O que muda no Bora:** uma folha nova a partir de `restaurant_menu_screen.dart`, com
  `business_hours`, a morada e a taxa que o ecrã já mostra.
- **Painel admin:** já edita estes dados em `admin_partner_detail`. Acrescentar a pré-visualização
  "como o cliente vê".
- **Tamanho e risco:** P. Não toca em dinheiro.
- **Prova:** print da ficha em 3 lojas (uma parceira, uma não-parceira, uma farmácia).

### 5. "Mais vendidos" e "Novidades" no topo do menu da loja
- **O que é:** antes das categorias, uma faixa com os artigos mais pedidos naquela loja e os
  novos.
- **Quem tem:** a Glovo ("Mais vendidos" e "Novidades", glovo_09) e a Uber Eats ("Artigos em
  destaque · os mais apreciados", ubereats_06).
- **O que muda no Bora:**
  - `restaurant_menu_screen.dart` passa a ler `is_popular`, que já é carregado e nunca se mostra
    (`restaurant_store.dart:233`), e/ou a contagem de pedidos dos últimos 30 dias por produto.
  - Função SQL nova, só de leitura (fechada a anon).
  - **Promoções com preço riscado ficam de fora**: o servidor não aplica o `discount_price`. Ver o
    item 15.
- **Painel admin:** em `admin_catalog`, marcar ou desmarcar "destaque" e "novidade" por produto, e
  um interruptor geral da faixa.
- **Tamanho e risco:** M. Não toca em dinheiro.
- **Prova:** uma loja com 3 destaques marcados no painel → aparecem no topo nas 3 plataformas.

### 6. Cartões da página inicial com tempo, taxa, nota e distância
- **O que é:** os cartões da página inicial hoje só têm foto, nome e cozinha. Passam a ter
  "15-25 min · 2,50 € · ★4,6 · 1,2 km", como já têm os cartões da lista de restaurantes.
- **Quem tem:** a Glovo (glovo_06) e a Uber Eats (ubereats_03).
- **O que muda no Bora:** `lib/widgets/home/home_feed.dart:533-616` reaproveita o cartão de
  `restaurants_screen.dart:603-661`.
- **Painel admin:** em `admin_home_banners`, interruptor "mostrar nota nos cartões" (para lojas
  com poucas avaliações).
- **Tamanho e risco:** P. Não toca em dinheiro: a taxa mostrada é a que a lista já mostra.
- **Prova:** print da página inicial antes e depois, nos 3 tamanhos.

### 7. Filtros e ordenação na lista de restaurantes
- **O que é:**
  - Chips: "Perto de mim", "Melhor avaliados", "Menos de 30 min", "Entrega mais barata" e tipo de
    cozinha.
  - Ordenar por: recomendado, distância, avaliação ou taxa.
- **Quem tem:** a Glovo (glovo_07: Recomendado, Perto de mim, Avaliações, Taxa de entrega) e a
  Uber Eats (ubereats_03/04: Ofertas, Taxa, Menos de 30 min, Classificação, Chegada mais cedo).
- **O que muda no Bora:** `lib/screens/restaurants_screen.dart:92-105`. Hoje a ordem é fixa
  (abertos primeiro, depois alfabética).
- **Painel admin:** o `admin_discovery_filters` já existe. Ligar ou desligar cada chip a partir
  daí.
- **Tamanho e risco:** M. Não toca em dinheiro.
- **Prova:** ligar "Melhor avaliados" → a ordem muda e bate certo com as notas do banco.

### 8. Antes de pagar, mostrar e deixar trocar a morada, e ter a nota do pedido no carrinho
- **O que é:**
  - O ecrã de pagamento passa a mostrar "Entregar em: <morada> · Trocar". Hoje não mostra a morada,
    e o cliente pode pagar para a morada antiga do GPS.
  - A "nota para a loja/estafeta" também fica visível no carrinho.
- **Quem tem:**
  - A Uber Eats: "Adicione uma nota ao pedido: utensílios, instruções especiais" no carrinho
    (ubereats_13).
  - A Glovo e a Uber Eats pedem a morada logo no início e mostram-na no topo (glovo_05,
    ubereats_03).
- **O que muda no Bora:** `lib/screens/payment_method_screen.dart:1069-1083`, que hoje só bloqueia
  quando está vazia, e `cart_screen.dart`. A nota já existe em `payment_method_screen.dart:725`.
- **Painel admin:** a morada e a nota já aparecem no `admin_order_detail`. Confirmar e acrescentar
  "morada mudada no checkout: sim/não".
- **Tamanho e risco:** P. Não toca em dinheiro. A distância é recalculada pelo servidor como hoje.
- **Prova:** escolher outra morada no checkout → o pedido de teste (em dinheiro, conta demo) fica
  com a morada nova.

### 9. "Editar" uma linha do carrinho (mudar extras) sem a apagar
- **O que é:** carregar na linha reabre o produto com as escolhas já marcadas.
- **Quem tem:** a Glovo ("Editar" em cada linha, glovo_14/21).
- **O que muda no Bora:** `cart_screen.dart` e `product_detail_screen.dart`, que passam a abrir
  com o `CartItem` existente.
- **Painel admin:** nada de novo para configurar. Contador "linhas editadas" nos KPIs, para provar
  que é usado.
- **Tamanho e risco:** P. Não toca em dinheiro: o preço continua a vir do servidor.
- **Prova:** pôr um artigo com 2 extras, editar para 1 extra → o total desce e o pedido de teste
  sai com 1 extra.

### 10. Botão "Entrega / Recolha" visível na página inicial e na loja
- **O que é:** a recolha na loja existe (código de levantamento e curbside), mas está escondida no
  carrinho. Por isso tem **0 pedidos** no banco. Passa a ter um botão no topo, como a Uber.
- **Quem tem:** a Uber Eats ("Entrega | Recolha" no topo e na loja, ubereats_03/06); a Glovo vende
  a recolha aos parceiros (glovo_27).
- **O que muda no Bora:** `client_home_screen.dart` e `restaurant_menu_screen.dart` mostram a
  escolha, e o `takeaway_enabled` por loja já existe.
- **Painel admin:** interruptor geral "recolha na loja", que hoje não existe (só há o interruptor
  loja a loja).
- **Tamanho e risco:** P. A recolha não cobra entrega, mas isso é regra que já existe; não se mexe
  em valores.
- **Prova:** escolher Recolha na página inicial → as lojas sem recolha ficam marcadas → pedido de
  teste com código de levantamento.

### 11. "Leve também" no carrinho: bebida ou sobremesa da mesma loja
- **O que é:** por baixo do carrinho, 2 ou 3 artigos da mesma loja (bebidas e sobremesas) com um
  "+" direto.
- **Quem tem:** a Glovo (sugestão de bebida ligada ao cesto, glovo_15/21) e a Uber Eats (bebidas e
  sobremesas dentro do produto, ubereats_08).
- **O que muda no Bora:** `cart_screen.dart`, mais uma consulta aos produtos da loja por categoria.
  Já existe o texto "Faltam X € para…", e as sugestões podem ajudar a chegar lá.
- **Painel admin:** em `admin_catalog`, escolher por loja quais categorias aparecem como "leve
  também", mais um interruptor geral.
- **Tamanho e risco:** M. Não toca em dinheiro.
- **Prova:** carrinho com um hambúrguer → aparecem bebidas da mesma loja → o "+" põe no carrinho.

## B. Loja, parceiro e painel

### 12. Alergénios no painel admin
- **O que é:** o parceiro já preenche os alergénios e o cliente já os vê no produto, mas o admin
  não os vê nem os corrige. É obrigação legal (Reg. UE 1169/2011, art. 14).
- **Quem tem:** a Uber Eats (aviso de alergénios no produto, ubereats_08). Na lista de 17/10 está
  como obrigação.
- **O que muda no Bora:** `admin_catalog` (e/ou `admin_partner_detail`) com a coluna e a edição de
  `products.allergens`, usando `lib/config/allergens.dart`, que já existe.
- **Painel admin:** é o próprio item.
- **Tamanho e risco:** P. Não toca em dinheiro.
- **Prova:** editar os alergénios de um produto demo no painel → aparecem na app do cliente.

### 13. Parceiro: "modo ocupado" (+10/20/30 min) e mudar a hora de pronto
- **O que é:**
  - Num dia cheio, a loja carrega em "Ocupado +20 min" e todos os pedidos novos mostram mais tempo.
  - Num pedido já aceite, pode dizer "fica pronto às 20:15".
- **Quem tem:** os painéis de parceiro da Glovo e da Uber (lista de 17/10, fontes públicas). Na
  página pública dos parceiros da Glovo aparece a "gestão de pedidos em tempo real" (glovo_27).
- **O que muda no Bora:**
  - `partner_dashboard_screen.dart`, mais duas funções SQL novas.
  - **Atenção:** hoje o estafeta é chamado em "aceite + preparação − 8 min"
    (`20261004193649_despacho_parceiro_chamada_no_tempo.sql`). Mudar a hora de pronto mexe nesse
    cálculo, que está perto do **despacho (zona protegida)**.
- **Painel admin:** no `admin_partners`, ver quais lojas estão em modo ocupado e com que tempo, e
  poder desligar.
- **Tamanho e risco:** M. **Despacho: precisa de revisão da Claude.ai antes.** Não mexe em preços.
- **Prova:** loja demo em "+20 min" → o cliente vê o tempo maior; o estafeta demo é chamado 20 min
  mais tarde (só com contas demo).

### 14. Parceiro responde às avaliações; admin oculta com motivo
- **O que é:**
  - O parceiro vê as suas avaliações. Hoje o ecrã `/partner/ratings` existe, mas nenhum botão leva
    lá, e a notificação de nota baixa também não.
  - O parceiro pode responder uma vez a cada avaliação.
  - O admin pode ocultar uma avaliação, com o motivo escrito (DSA).
- **Quem tem:** a Glovo e a Uber Eats (% de gostos por loja e por artigo, glovo_06, ubereats_06;
  responder a avaliações está nos painéis de parceiro, lista de 17/10).
- **O que muda no Bora:**
  - Botão no `partner_dashboard_screen.dart`.
  - Corrigir a rota da notificação (`notification_service.dart:1964`).
  - Resposta em `restaurant_ratings_list_screen.dart`, mais uma coluna e uma função SQL.
- **Painel admin:** no `admin_ratings`, ver a resposta e ocultar com motivo. Hoje o admin só pode
  "marcar".
- **Tamanho e risco:** M. Não toca em dinheiro.
- **Prova:** avaliação demo → o parceiro demo responde → a resposta aparece na loja → o admin
  oculta → desaparece para o cliente.

## C. Mexe em dinheiro ou no despacho — PRECISA DO AUTORIZO DO DANILO

> ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO ou no DESPACHO. Fica só descrito e não se propõe nenhum
> valor. Não se constrói sem o "autorizo" dele, com data, passado pela Claude.ai.

### 15. Pacote de dinheiro: cupão no checkout, assinatura mensal, promoções com preço riscado e agendar entregas normais
- **(a) Campo de cupão no checkout.**
  - Hoje o código promocional só vira tokens no Perfil.
  - A Glovo valida o código no perfil antes do pedido (FAQ pública); a Uber e o iFood aplicam-no
    no checkout.
  - Mexe no `create_order` e no `quote_order_pricing` (zona protegida).
  - **Painel admin:** editar e reativar cupões e ver quem usou cada um (falta hoje no
    `admin_promo_codes`).
- **(b) Assinatura mensal de entregas.**
  - A Glovo Prime e a Uber One custam 4,99 €/mês em Portugal; o Clube iFood existe no Brasil.
  - É receita recorrente (ordem de 13/10, n.º 2).
  - Mexe nas taxas e no Stripe (assinatura). **O preço e as regras são decisão do Danilo.**
- **(c) Promoções com preço riscado.**
  - O `discount_price` existe, mas o servidor não o cobra, por isso hoje não se pode mostrar.
  - Faz falta o servidor aplicar o desconto e uma nota legal, em todas as promoções, com o preço
    mais baixo dos últimos 30 dias (Diretiva Omnibus). A Glovo escreve "15 dias"; confirmar o
    texto com a advogada.
  - Quem cria a promoção: o parceiro ou o admin.
- **(d) Agendar entregas normais quando a loja está fechada.**
  - A Glovo e a Uber Eats deixam agendar em janelas de 30 minutos (glovo_10, ubereats_07).
  - O Bora só agenda as Festas.
  - Usa `orders.scheduled_for`, que já existe, mas a hora de chamar o estafeta é **despacho (zona
    protegida)**.
- **Tamanho e risco:** G no conjunto. Zona protegida (`create_order`, Stripe, despacho). Cada
  parte é uma missão separada, com teste em dinheiro e contas demo.

---

## Ideias para depois (fora dos 15)
- **Carrinho:**
  - Um carrinho por loja, em vez de apagar ao trocar (Glovo: glovo_20/21). É G e mexe no
    `CartStore` inteiro.
  - Botão "Esvaziar carrinho" e "Pedir de novo" que pergunta antes de apagar o carrinho atual
    (hoje apaga calado: `reorder_service.dart:52`).
- **Produto e loja:**
  - "Pedido por mais de 5 pessoas" nas opções do produto, e % de gostos por artigo (Uber Eats:
    ubereats_08).
  - Selo "Entregue pela própria loja" quando o parceiro chama o seu estafeta (Uber Eats).
- **Morada:** tipo de local (casa, apartamento, escritório) e pino no mapa ao gravar a morada
  (Glovo: glovo_03/04).
- **Ecrãs e legal:**
  - Ecrã para computador com largura máxima (hoje a foto do produto ocupa os 1440 px).
  - Livro de Reclamações visível no rodapé ou na página inicial (a Uber tem no rodapé; é obrigação
    legal PT). Hoje está escondido em Perfil → Informação legal.
- **Parceiro:**
  - Página web "para restaurantes", com o que o Bora oferece, para a propaganda: comissão muito
    abaixo dos 30% da Glovo e da Uber.
  - Impressão automática do talão no parceiro (a Uber inclui tablet e impressora na mensalidade).
- **Cliente:** foto da entrega visível para o cliente (hoje só o admin a vê).
- **Mais tarde:** pedido em grupo (Uber; o iFood não tem notícia disso); "comer fora com check-in"
  (iFood). O Bora já tem reservas e check-in, e pode juntar os dois.
