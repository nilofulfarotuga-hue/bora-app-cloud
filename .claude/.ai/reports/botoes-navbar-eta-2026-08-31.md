# Missão botoes-navbar-eta — 2026-08-31

## Acessos usados

Supabase do projecto ojykpzwqrtusfeakzrna por MCP (só leitura de platform_settings — as três chaves eta_* já existiam, criadas por MCP, com categoria "eta" e descrição em português na própria base). Git com a credencial guardada ontem nesta máquina. Nenhuma conta criada, nenhum dinheiro tocado, nenhuma migration.

## O que NÃO foi feito (a ler primeiro)

A prova no telemóvel do Danilo não foi feita: continua sem haver nenhum Android ligado por USB a este computador (só Windows/Chrome/Edge aparecem). As capturas do fluxo do motorista e do estafeta com o botão inteiro visível ficam em dívida — e o build que este push dispara é exactamente o que põe o código novo na Play alpha para essa prova ser feita no aparelho real quando o Danilo actualizar. Tudo o resto da missão fechou.

## Bloco 1 — botões de rodapé clicáveis (padrão único)

Nasceu o widget BoraBottomActionBar em lib/widgets/bora/bora_bottom_action_bar.dart, exportado no barrel do design system. É a única forma aprovada de pôr CTA fixo no fundo: dezasseis píxeis SEMPRE além do viewPadding do sistema (o viewPadding nunca é consumido por SafeArea acima — era essa a ratoeira que os ecrãs caíam), área de toque mínima de cinquenta e seis, largura total, espaço entre botões empilhados.

A varredura aos três apps procurou Positioned no fundo, Align bottomCenter, bottomNavigationBar com acção e folhas com botão no fim. As telas migradas/corrigidas foram estas dez:

1. Corrida activa do motorista TVDE (a da foto) — o Navegar e o Cheguei/Iniciar/Finalizar saíram do padding simples para o BoraBottomActionBar dentro do painel arrastável.
2. Mapa do estafeta no delivery (painel com Recolher/Iniciar/Concluir entrega) — o SafeArea, que dentro de sheet podia chegar consumido, deu lugar à garantia por viewPadding.
3. Checkout do cliente (carrinho, Finalizar pedido) — SafeArea(minimum) dava só o máximo entre sistema e dezasseis; passou a dezasseis além do sistema.
4. Tracking do cliente TVDE — o cartão com o Cancelar corrida ganhou margem inferior somada ao viewPadding.
5. Home do estafeta — o cartão de estado do fundo trocou padding por viewPadding.
6. Pedir lavagem (carwash) — migrado para o BoraBottomActionBar.
7. Festas, ecrã do dia e hora (Continuar) — migrado.
8. Fotos de recolha do lavador (Recolhi o carro) — migrado.
9. Rodapé de orçamento partilhado (enviar encomenda e levar compras) — viewPadding e o clamp anti-tela-branca subiu de 40 para 56, porque a navbar de 3 botões tem 48 e o clamp antigo deixava o botão colado nela.
10. As folhas TVDE do cliente (pagamento, chamar a volta, parada) já tinham o tratamento certo de ontem — verificadas, não tocadas.

Os restantes achados da varredura eram badges decorativos, FABs de mapa ou ecrãs admin de desktop — não são CTA fixo de fundo e ficaram como estavam. As miras de centralizar já tinham ficado acima dos painéis no trabalho de ontem (a do motorista acompanha a altura real do painel; a do cliente fica acima da fitinha).

## Bloco 2 — ETA a sério no TVDE

A fonte do tempo é a duração da MESMA rota que já se desenha no mapa (Directions). Enquanto essa duração é fresca — pedida há menos de quarenta e cinco segundos e com o carro a menos de cento e cinquenta metros de onde foi pedida — é ela que manda; envelhecendo, o cálculo cai no fallback distância restante a dividir pela velocidade média de eta_avg_speed_kmh (lida das definições, fallback 28 no código, nada cravado). No motorista o número recalcula-se a cada posição nova e, parado, num ticker de trinta segundos; a linha recolhida mostra o estado com o ETA colado. No cliente o poll de posição de cinco segundos já alimentava o recálculo — agora com a rota como fonte primeira e a velocidade das definições; a fitinha diz "Motorista a caminho · chega em ~X min" e, em viagem, "chegada ~X min". Nenhum dos dois congela no valor inicial.

## Bloco 3 — ETA por fases no delivery

Os estados reais usados são os do OrderStatus que já existiam (created, preparing, callingDriver, driverAccepted, pickedUp, onTheWay, delivered) — nada foi inventado. O serviço único OrderEtaService ganhou as fases: numa compra não-parceira (storeShopping) ainda por terminar — até ao pickedUp, que é o "comprei" do estafeta — o cliente vê um intervalo honesto estilo Glovo, "Entrega estimada: X–Y min", somando a deslocação do estafeta até à loja (quando já há estafeta com posição), o intervalo de compra das definições (eta_shopping_minutes_nonpartner_min/max, fallback 30/45) e a deslocação loja→cliente. Marcado o pickedUp, o rótulo passa ao número único vivo, só a deslocação real até ao cliente, recalculado com a posição realtime do estafeta — o ecrã de acompanhamento passa a entregar ao cálculo a posição VIVA do DriverStore em vez da coordenada velha gravada na linha do pedido. No restaurante parceiro, quando o parceiro anuncia tempo de preparação (prep_time_minutes, campo que já existia), é esse que entra na conta; sem ele fica o buffer de sempre. E o ponto (d) confirmou-se sem obra nenhuma: o tracking do cliente JÁ recebe a posição do estafeta em tempo real pelo DriverStore (subscrição realtime da tabela drivers), já desenha o estafeta a mexer no mapa e já traça a rota — estava construído; o que faltava era o ETA usá-la, e agora usa.

## Painel admin

As três chaves eta_* aparecem no ecrã Configurações do admin (categoria "eta") e passaram a ser EDITÁVEIS — entraram na whitelist operacional, porque afinam o tempo mostrado ao cliente e nunca um valor cobrado ou pago. A explicação de cada uma já vive na coluna description da própria base (escrita quando as chaves nasceram por MCP) e é essa que o ecrã mostra por baixo de cada chave.

## Provas

flutter analyze sem um único erro (as 263 notas são lint antigo pré-existente — deprecations de activeColor/groupValue e afins, nenhum nos meus acrescentos). A bateria de testes INTEIRA correu verde: 324 testes, incluindo os TVDE todos e o teste novo order_eta_phases_test.dart, que fixa o intervalo da compra (30–50 pela geometria do caso), a soma da deslocação à loja, a velocidade das definições a alimentar o cálculo (mudar a velocidade muda o intervalo), a passagem de intervalo para número vivo no pickedUp, o ETA a DESCER quando o estafeta se aproxima (o anti-congelamento), e o prep_time_minutes do parceiro a substituir o buffer.

## Fora do âmbito, encontrado e não corrigido

O dispatch_service tem a sua velocidade própria cravada a 30 (zona protegida — não toquei). Os ecrãs admin de desktop com painéis no fundo não foram migrados para o rodapé novo (uso é no browser/PT-BR, sem navbar Android). Os deprecations de activeColor/groupValue espalhados pelo código pedem uma passagem própria um dia. O Hermes/outra sessão voltou a escrever em ficheiros do .claude durante a missão — foram para um stash próprio (telemetria-hermes-2026-08-31) sem nada apagado, e o stash quebrado-outra-sessao-2026-08-30 ficou quieto como mandado.

## O que falta para fechar de vez

Só a prova no aparelho real: quando o build deste push chegar à Play alpha e o Danilo actualizar o Samsung, capturar o fluxo do motorista (cheguei/iniciar/finalizar) e do estafeta (recolher/iniciar/concluir) com os botões inteiros e clicáveis acima da navbar de 3 botões, e ver o ETA a mexer em corrida real.
