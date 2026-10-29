---
id: memoria-claude-ai-paridade-mundo-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Paridade do mundo, segunda volta (Rappi, DoorDash, Zomato, Meituan) 29/10/2026

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `paridade-mundo-2026-10-29`, origem `claude-code`, atualizada em 2026-10-29T14:25:48.975762+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: paridade mundo 2026 10 29 · memoria claude.ai · claude_ai_memoria

# Paridade do mundo, segunda volta (29/10/2026)

Missão final-app-2026-10-29, Bloco 6.b. Rappi, DoorDash, Zomato e Meituan, só por fora: páginas de ajuda, sites, imprensa e lojas de apps. Sem login, sem pedido, sem contornar bloqueios. Repo lido só para confirmar o que o Bora já tem: C:\BoraLocal\wt-missao-geral-28-10 (commit 892fa5e4). Nada foi editado. São ideias de funcionamento: não se copia código, texto nem marca.

Fora desta lista, porque já estão na página paridade-mundo-e-lei-2026-10-17: pedido em grupo, assinaturas, mapa de calor do estafeta, modo ocupado e pausa da loja, prova de entrega com foto, chat com foto nas substituições. Já existem no Bora (visto no código): gorjeta, partilhar o seguimento, agendar entrega, nota ao estafeta, reportar problema, takeaway, pausa da loja, "Faltam X € para a entrega grátis", produtos mais vendidos no parceiro.

Resumo: 10 itens, 5 PEQUENOS (1 a 5), 5 MÉDIOS (6 a 10). Nenhum mexe em preços, comissões, carteira, tokens ou zonas protegidas, salvo onde está escrito.

## PEQUENOS (com descrição exata para implementar)

### 1. Sem talheres, por defeito — Zomato, Meituan — PEQUENO
O que é: no pagamento, talheres e guardanapos só vão se o cliente pedir. A Zomato passou de "saltar talheres" para "pedir talheres" em agosto de 2021 (diz que mais de 90% dos clientes não precisam). A Meituan tem a opção "sem talheres" desde 2017 (Projeto Montanha Azul).
Fontes: https://www.restaurantindia.in/news/you-can-now-skip-plastic-cutlery-on-ordering-online-as-zomato-takes-a-step-closer-to-environment.n19973 · https://officechai.com/?p=40505 · https://sdgs.un.org/partnerships/meituan-waimai-blue-mountain-project
Porque ajuda na Guarda: a loja poupa dinheiro e plástico em cada pedido e o cliente sente-se do lado do ambiente, sem custo para ninguém.
Risco: baixo, não toca em preço. A Zomato teve queixas de lojas que ignoravam o pedido: por isso a linha tem de aparecer bem visível no cartão do parceiro.
O que mudar:
- Ecrã: Pagamento (payment_method_screen.dart), um cartão novo logo acima do campo "Nota para o estafeta". Só aparece em pedidos de restaurante com entrega ou takeaway (não em mercado, Favor, TVDE, limpeza, lavagem).
- Texto PT-PT: título "Talheres e guardanapos". Interruptor "Preciso de talheres e guardanapos", DESLIGADO por defeito, verde #16A34A quando ligado. Linha pequena a cinzento: "Se não precisares, poupas plástico e ajudas a loja. Só enviamos se pedires."
- Ao criar o pedido, sem coluna nova: acrescentar ao princípio de customer_notes a linha "SEM TALHERES" (interruptor desligado) ou "COM TALHERES" (ligado). O parceiro, o estafeta e o admin já mostram a nota (partner_dashboard_screen e admin_order_detail_screen). No cartão do parceiro mostrar a linha em negrito.
- O limite de caracteres do campo de nota conta só o texto do cliente; as linhas automáticas juntam-se depois (uma função pura num só sítio, com teste).
- Painel admin (PT-BR): Configurações da plataforma, interruptor novo "Perguntar por talheres no pagamento" (chave não financeira ask_cutlery em platform_settings, padrão ligado; migração com ON CONFLICT DO NOTHING, também guardada no repo). Ver: a nota aparece no detalhe do pedido.
- Português novo com .tr exige a tradução em inglês em strings_en.dart (o CI falha sem ela). Uma só cor laranja por ecrã: neste cartão não usar laranja.

### 2. Troco ("Vais pagar com que nota?") — Rappi — PEQUENO
O que é: quando o cliente escolhe dinheiro, a app pergunta com que nota vai pagar, para a loja ou o estafeta levarem troco. Vi-o descrito em queixas de clientes da Rappi no Chile (o campo existe, mas nem sempre havia troco). FONTE NÃO OFICIAL: https://www.reclamos.cl/rappi/reclamo/2024/feb/rappi-no-traen-vuelto
Porque ajuda na Guarda: pagar em dinheiro é comum e o limite do Bora é 40 €. Hoje o estafeta só vê "RECEBER €X" e não sabe se o cliente tem a conta certa.
Risco: baixo a médio. É o ecrã de pagamento em dinheiro, mas só acrescenta texto: não muda nenhum valor. Decisão do Danilo antes de ligar: o estafeta deve mesmo levar troco? O texto abaixo é honesto e não promete.
O que mudar:
- Ecrã: Pagamento, quando o método é Dinheiro, por baixo do aviso do limite de dinheiro.
- Título "Com que nota vais pagar?". Chips: "Valor certo" (escolhido por defeito), "10 €", "20 €", "50 €". Só aparecem as notas MAIORES que o total do pedido. Chip escolhido: verde #16A34A com texto branco.
- Linha a cinzento por baixo: "Avisamos o estafeta, mas o troco depende dele. Se puderes, paga com o valor certo."
- Ao criar o pedido: acrescentar a customer_notes a linha "TROCO PARA 20 €" (nota escolhida). O banner "RECEBER €X" do estafeta (CashCollectBanner) fica igual.
- Painel admin (PT-BR): Configurações da plataforma, interruptor "Perguntar troco no pagamento em dinheiro" (chave ask_cash_change, padrão ligado). Ver: nota no detalhe do pedido.
- Mais tarde, versão com coluna própria para o estafeta ver "troco a levar: X €" em destaque.

### 3. Andar, porta e código na morada — DoorDash — PEQUENO
O que é: ao guardar uma morada, a DoorDash deixa juntar apartamento e instruções, que ficam guardadas para os pedidos seguintes. Fonte: https://help.doordash.com/en-us/consumers/article/how-do-i-change-my-delivery-address
Porque ajuda na Guarda: prédios com código de porta, andares e casas sem número claro. Hoje a morada do Bora é "casa/trabalho + linha de endereço" e o cliente tem de repetir a explicação na nota todas as vezes.
Risco: baixo. Uma coluna nova numa tabela fora das zonas protegidas (client_addresses). A migração tem de ficar também em supabase/migrations.
O que mudar:
- Ecrã: Moradas do cliente (client_addresses_screen.dart), formulário de adicionar e editar: campo novo "Andar, porta ou código (opcional)", dica "Ex.: 2.º Dto · porta azul · código 1234", máximo 80 caracteres, por baixo da morada.
- Base de dados: coluna details text null em client_addresses (a regra RLS por user_id não muda) e o campo details em ClientAddress (fromJson e toJson).
- Pagamento: mostrar esse texto a cinzento por baixo da morada escolhida. Ao criar o pedido, acrescentar a customer_notes a linha "MORADA: 2.º Dto · código 1234". Assim o estafeta, o parceiro e o admin vêem-na sem coluna nova em orders.
- Painel admin (PT-BR): o detalhe do pedido já mostra a nota. Se a ficha do cliente já lista moradas, mostrar a coluna "Complemento"; se não lista, basta a nota.

### 4. Filtros rápidos na lista de restaurantes — Zomato (e Rappi, DoorDash em geral) — PEQUENO
O que é: uma fila de botões no topo da lista (aberto agora, só takeaway, entrega grátis...) para encurtar a escolha. FONTE FRACA: https://uxdesign.cc/thoughts-on-online-food-ordering-experience-439a50f2aefc (crítica de UX que descreve os filtros rápidos da Zomato e da Swiggy). A razão forte é interna: o painel admin já tem o ecrã "Filtros de Descoberta" e a app do cliente ainda não o lê.
Porque ajuda na Guarda: a lista hoje só ordena (abertas primeiro, depois alfabético). Quem tem fome quer ver o que está aberto e o que vem grátis.
Risco: baixo, só leitura.
O que mudar:
- Ecrã: lista de restaurantes (restaurants_screen.dart), uma linha de chips por baixo da pesquisa: "Aberto agora", "Ir buscar", "Entrega grátis".
- Dados que já existem: isOpenNow(), takeawayEnabled do RestaurantModel e SmallOrderFeeService.entregaGratisMinCents(id) diferente de nulo.
- Ligar ao interruptor que já existe: platform_settings.discovery_filters (open_now_enabled). Acrescentar ao mesmo JSON duas chaves, takeaway_enabled e free_delivery_enabled (padrão false). Só mostrar os chips cujo interruptor esteja ligado.
- Painel admin (PT-BR): ecrã "Filtros de Descoberta" (admin_discovery_filters_screen.dart), dois interruptores novos: "Filtro 'Ir buscar'" e "Filtro 'Entrega grátis'". Tirar também a nota do ecrã que diz que o cliente ainda não consome os filtros.
- Visual: chip ativo com fundo verde #16A34A e texto branco; inativo com contorno cinzento. Sem laranja. Lista vazia: "Nenhuma loja com estes filtros. Tira um filtro para ver mais."
- Os filtros dietéticos (vegetariano, vegan, sem glúten) ficam desligados: precisam de etiqueta por produto, é trabalho MÉDIO à parte.

### 5. "Juntar mais" no carrinho — Meituan — PEQUENO
O que é: quando falta pouco para o mínimo ou para o desconto, a Meituan mostra um botão que abre pratos baratos, ordenados do mais barato para o mais caro, para completar o pedido. Fonte: https://www.woshipm.com/operate/1219047.html
Porque ajuda na Guarda: o carrinho já diz "Faltam X € para a entrega grátis", mas não ajuda a chegar lá. A loja vende mais e o cliente poupa a entrega.
Risco: baixo. Não toca em preço nem em taxas: só adiciona produtos pelo método normal do carrinho, sem mexer no PricingService. Condição: a lista de produtos da loja estar em memória no carrinho; se não estiver, passa a MÉDIO.
O que mudar:
- Ecrã: carrinho (cart_screen.dart), por baixo da linha "Faltam {0} € para a entrega grátis" (a que já existe, _FaltaParaOMinimo).
- Quando falta mais que zero, mostrar uma tira horizontal "Juntar mais" com até 3 produtos DA MESMA LOJA, do mais barato para o mais caro, cada um com foto pequena, nome, preço e botão "+" verde #16A34A. Excluir esgotados.
- Produtos com opções obrigatórias (tamanho, acompanhamento): o "+" abre o detalhe em vez de adicionar logo.
- Subtítulo da tira: "Faltam {0} € para a entrega grátis". Se o pedido ainda está abaixo do mínimo da loja: "Faltam {0} € para o pedido mínimo".
- Painel admin (PT-BR): sem ecrã novo, usa o mínimo que o admin já define por loja. Paridade: interruptor em Configurações da plataforma, "Mostrar 'Juntar mais' no carrinho" (chave cart_add_more_strip, padrão ligado).

## MÉDIOS

### 6. Modo letra grande e simples — Meituan — MÉDIO
O que é: a Meituan tem uma versão para mais velhos ("modo sénior"), que se liga em "Meu > Definições" e fica só com o pedido de comida. Fonte: https://finance.sina.cn/tech/2023-10-23/detail-imzsaxve2225826.d.html (a mesma fonte diz que não detalha o tamanho da letra).
Porque ajuda na Guarda: cidade do interior, com clientes mais velhos e Favores para quem não sai de casa. A app já segue o tamanho de letra do telemóvel; o ganho é pôr o interruptor DENTRO da app (Perfil: "Letra normal / grande / muito grande"), onde essa pessoa o encontra.
Risco: médio. Letra maior pode partir layouts fixos: ver pelo menos 6 ecrãs principais. Nada de dinheiro.

### 7. Preferência de substituição por pedido de mercado — DoorDash — MÉDIO
O que é: antes de pagar, o cliente escolhe o que acontece se faltar um produto: trocar por parecido, tirar e devolver, ou ligar-lhe. Fonte: https://help.doordash.com/en-ca/consumers/article/what-are-customer-substitution-preferences
Porque ajuda na Guarda: nos mercados não parceiros é o estafeta que compra. O Bora já tem a proposta de substituição por chat; isto adiciona a decisão ANTES, e poupa mensagens. Complementa o chat com foto da lista de 17/10.
Risco: médio a alto. "Tirar e devolver" é reembolso: preparar tudo e só ligar com o "autorizo" do Danilo. Dinheiro, carteira e Stripe não se tocam sem ele.

### 8. Polegar para cima ou para baixo por prato, e etiqueta "Mais gostado" — DoorDash — MÉDIO
O que é: depois da entrega, o cliente dá polegar para cima ou para baixo a cada prato que pediu. Os pratos com mais polegares para cima ganham a etiqueta "Mais gostado" (até 3 por loja); a loja não vê votos individuais. Só quem pediu o prato pode votar. Fonte: https://help.doordash.com/en-us/consumers/article/frequently-asked-questions-most-liked-items-item-ratings
Porque ajuda na Guarda: o cliente escolhe melhor com poucas lojas, e o voto só de quem comprou serve a regra de avaliações verificadas da lei (Omnibus, ver 17/10).
Risco: baixo a médio. Tabela nova, função nova, ecrã de moderação no admin. Não toca em dinheiro.

### 9. Saúde da loja no painel do parceiro — DoorDash — MÉDIO
O que é: cartão com espera do estafeta, cancelamentos evitáveis, tempo parada, pedidos com item em falta ou errado, e nota. Fonte: https://help.doordash.com/en-us/merchants/article/merchant-portal-operations-quality
Porque ajuda na Guarda: o parceiro vê onde perde pedidos (hoje só vê vendas e produtos mais vendidos). O admin ganha uma lista das lojas piores primeiro.
Risco: baixo. Só leitura, com os dados dos pedidos e das queixas (reportar_problema_pedido). Ecrã novo no painel de parceiro e tabela no admin.

### 10. Enviar o pedido como presente — Rappi — MÉDIO
O que é: o cliente escolhe "Enviar como presente", põe nome e telemóvel de quem recebe e um cartão com mensagem. Quem recebe vê a mensagem e um link para seguir o pedido, sem precisar de app nem conta (artigo de 18/12/2023). Fonte: https://www.eldinamo.cl/buen-dato/2023/12/18/como-enviar-pedidos-de-delivery-como-regalo/
Porque ajuda na Guarda: filhos fora a mandarem o jantar aos pais, pessoas de fora a pagarem a refeição de alguém na terra. Hoje partilhar o seguimento só envia texto.
Risco: médio. Telemóvel de terceiros (RGPD: usar só para a entrega, dizer ao cliente), link com chave que não dá acesso a mais nada, e o PIN de entrega tem de ir para quem recebe.

## Fora do top 10, a avaliar mais tarde

- Atraso vira crédito automático (Meituan, "Zhunshibao", seguro por pedido): MÉDIO e DINHEIRO, nada se aplica sem o "autorizo" do Danilo. Fonte: https://www.cs.com.cn/bx/202205/t20220518_6270026.html
- Pedido a seguir no ecrã de bloqueio (DoorDash em iPhone, Android 16 "Live Updates"): GRANDE, mexe na publicação iOS. Fontes: https://9to5mac.com/2023/12/04/doordash-live-activities-and-dynamic-island-order-tracking/ · https://www.androidauthority.com/android-16-qpr1-live-updates-3573399
- Modo dietético (Zomato "Pure Veg", março de 2024): MÉDIO. Cuidado: a frota separada gerou polémica e foi retirada, fazer só o filtro. Fonte: https://business-standard.com/companies/news/zomato-launches-pure-veg-mode-to-woo-vegetarian-customers-all-details-124031900825_1.html
- Modo Ocupado do parceiro, +10 min em vez de pausar (DoorDash): já na lista de 17/10. Fonte: https://help.doordash.com/en-us/merchants/article/what-is-my-store-status
- Pedido de vizinhos numa entrega só (Meituan "Pinhaofan"): GRANDE e muda custos do estafeta. Fonte: https://restofworld.org/2024/meituan-batch-delivery-cost/

## Notas para quem implementar

- Apps (cliente, estafeta, parceiro) em PT-PT; painel admin em PT-BR. Verde #16A34A, laranja #F97316, fonte Inter. Uma só cor laranja por ecrã (skill audit-orange-rule).
- Não copiar textos nem marca: as descrições acima são do Bora.
- Fontes de qualidade fraca ficam marcadas (itens 2 e 4). Abertas por inteiro em 29/10/2026: a análise da Meituan (item 5), a notícia da Meituan sénior (item 6) e o artigo da Rappi (item 10). As outras fontes vêm dos resultados das pesquisas, sem abrir a página toda.
- Nenhum destes itens mexe em dispatch_engine, pricing_service, finalizePurchase, bora_tokens, webhook Stripe ou RLS de orders, wallets e ledger. O item 7 (reembolso) e a lista "Fora do top 10" com crédito por atraso precisam de "autorizo" do Danilo.
- Migrações novas (itens 1 a 5) aplicadas em produção também entram em supabase/migrations.

