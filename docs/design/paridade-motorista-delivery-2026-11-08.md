# Paridade: o que o Bora Motorista (TVDE) ganhou e o delivery ainda não tem (08/11/2026)

Só leitura de código e `git log --since=2026-10-11`. Nenhum código alterado.
Zonas: verde = textos e ecrãs; amarela = notificações e estados; vermelha = dinheiro, despacho, preços, Stripe.
Custo: P = pequeno (menos de 1 dia), M = médio (1 a 3 dias), G = grande.

## Resumo para o Danilo

O delivery já tem a maior parte do que se vê: carro a deslizar, ETA ao vivo, avaliação com "Saltar", MB Way com espera, chamada insistente ao estafeta e encomenda agendada. O que falta de verde é pequeno: dizer ao cliente "o estafeta chegou ao restaurante" e pôr o nome e o tempo na frase de estado. O resto (fila inteligente, compensação por cancelamento tardio) mexe em despacho e dinheiro, por isso só prepara-se e espera pelo "autorizo".

## O que o TVDE ganhou nas últimas 4 semanas (commits desde 11/10)

- Fila inteligente (40 s, passa ao 2.º sem recalcular): `e22414d9`, `622c8700`, painel `08aeb58a` (21/10).
- Carro a deslizar por canal privado (Realtime broadcast): `c859550e`.
- Cancelamento tardio com compensação ao motorista: `3e235f78`, `73cfb88c`, `8b11d61d`, `b05c56c9` (17/10).
- Reserva agendada, hora de Lisboa: `ab056aa3`, `8a81803f`.
- Reserva em que o cliente não aparece: "Não compareceu" `84027792`, `99a23ad2`.
- Pedir corrida nunca trava (morada escrita conta, botão diz o que falta): `c142aa18`.
- Online/ligado sem sinal, serviço de fundo religa: `286080d8`, `68ef7ce5`.
- Online só para quem está aprovado: `280e50db` (01/11).
- Bora Motorista fechado pelo interruptor `tvde_app_visivel`: `ee71173f` (04/11).
- Tipo do pedido (passageiros ou encomendas) no mesmo motor: `9311e68a`, `728b72cd`.
- Duas contas Stripe: `171733e8` (preparado, sem publicar).

## Tabela de paridade

| Item do TVDE | O delivery já tem? (prova) | Faz sentido ter? | Custo | Zona |
|---|---|---|---|---|
| Fila inteligente 40 s | Parcial. A oferta tem tempo limite lido do servidor (`dispatch_offer_timeout_seconds`, `lib/screens/driver_home_screen.dart:3960-3985`). A fila ao vivo com ordenação inteligente é só do TVDE | Sim, mas é decisão de despacho | G | Vermelha (despacho) |
| Preço fixo mostrado antes de pedir | Sim. O carrinho mostra o total e a decomposição (`lib/screens/cart_screen.dart`; no seguimento `order_tracking_screen.dart:1178-1210`) | Já feito | - | Vermelha (preços), nada a fazer |
| Cancelamento tardio com compensação | Parcial. Cancelar tem tempo de cortesia grátis e escolha do reembolso (`order_tracking_screen.dart:1370-1395`). Não há compensação ao estafeta nem ao parceiro | Sim, em estudo, para pedidos já recolhidos | G | Vermelha (dinheiro) |
| Mapa e ETA ao cliente | Sim. `DriverLiveFeed` + `MarcadorAnimado` + `OrderEtaService` (`order_tracking_screen.dart:64-175`, `lib/services/order_eta_service.dart:230-239`) | Já feito, ver item (a) | - | Verde |
| Carro a deslizar | Sim, estafeta interpolado desde 07/10 (`lib/utils/marcador_animado.dart`, `test/rastreio_interpolacao_test.dart`). Usa canal em `driver_locations` mais consulta de reserva; o canal privado de broadcast do TVDE (`c859550e`) não | Sim, trocar de canal só se a latência se notar | M | Amarela |
| Reserva agendada | Sim. `order.scheduledFor` (`order_tracking_screen.dart:834-837`, `partner_dashboard_screen.dart`, `driver_home_screen.dart`) | Já feito | - | Amarela |
| Reserva em que o cliente não aparece ("Não compareceu") | Não. Não há estado equivalente em `OrderStatus` (`lib/models/order_model.dart:17-33`) | Pouco: o cliente delivery não está num local fixo; já existe "entrega falhada" por outras vias a confirmar | M | Amarela |
| Online só pelo botão e só se aprovado | Sim. `_handleOnlineToggle` e regra do servidor (`driver_home_screen.dart:390-502`, `280e50db`) | Já feito | - | Amarela |
| MB Way toca ao pagar, com espera | Sim. `_MBWayWaitingDialog` com contagem e consulta a cada 3 s (`lib/screens/payment_method_screen.dart:1616-1670`, `:1956`) | Já feito | - | Vermelha (pagamento), nada a fazer |
| Chamada persistente ao motorista | Sim, é a origem. Som em ciclo, ecrã inteiro, canal de alarme (`lib/services/incoming_job_alert.dart`, `kCanalOfertasAlarme`) e `TempoDaOferta` | Já feito | - | Amarela |
| Mensagens "chegou" / "a caminho" por nome | Parcial. TVDE: "{0} chegou", "{0} chega em ~{1} min" (`tvde_ride_tracking_screen.dart:2054-2080`). Delivery: texto fixo sem nome nem tempo (`order_tracking_screen.dart:1661-1684`) | Sim | P a M | Verde (cartão) / Amarela (aviso) |
| Avaliação sem travar | Sim. Abre sozinha, tem "Saltar" e volta a perguntar no máximo 2 vezes em 48 h (`order_tracking_screen.dart:278-322`, `rating_screen.dart:311`, `client_home_screen.dart:153-215`) | Já feito; falta torná-la menos intrusiva, ver (c) | P | Verde |
| Pedir "nunca trava" (botão diz o que falta) | A verificar no carrinho (`cart_screen.dart`). Não confirmado | Sim | P | Verde |
| Painel com filtro por tipo | Já existe para TVDE (`83e1705a`); o delivery tem o seu painel | - | - | - |

## Os 3 itens verdes, a fundo

### (a) Cliente vê o estafeta a deslizar no mapa, com ETA, durante a entrega

EXISTE, quase tudo. Provas:
- Canal do estafeta e consulta de reserva: `lib/screens/order_tracking_screen.dart:121-175` (`_sincronizarFeed`, `_aceitarAmostra`, `DriverLiveFeed` em `lib/services/driver_live_feed.dart`).
- Marcador que desliza e nunca anda para trás: `_estafeta = MarcadorAnimado(...)` (`:71-72`), com `lib/utils/marcador_animado.dart` e `lib/utils/rastreio_interpolacao.dart`; teste `test/rastreio_interpolacao_test.dart`.
- Marcador no mapa: `:410-475`. Rota a seguir à estrada: `_updateRoute` (`:326-340`).
- ETA que usa a posição viva: `OrderEtaService.label(order, driverPos: ...)` (`:830-845`, serviço em `lib/services/order_eta_service.dart:230-240`). Mostra "Chega em ~X min", arredondado a 5 min, e "Entrega estimada: A-B min" para compras em lojas sem parceria. Esconde o ETA em encomendas agendadas.
- Os intervalos vêm do painel (`RastreioSettings`, chaves `eta_*`).

O que FALTA (pequeno):
1. O ETA é só um selo no cartão que se arrasta. Não há um número grande por cima do mapa; com o cartão a 22% o cliente não o vê bem. Sugestão: o mesmo texto numa pílula fixa em cima do mapa.
2. "Chega em ~X min" não mostra a hora (padrão Glovo/Uber: "Chega às 19:42"). Ver melhoria 3 do comparativo.
3. O texto "Chega em ~$m min" não passa por `.tr` (`order_eta_service.dart:235,239`), por isso não tem versão em inglês.
4. O TVDE usa um canal privado de broadcast (`c859550e`); o delivery usa consulta e canal normal. Só se mexe nisto se houver atraso medido. Zona amarela.

Ficheiros mínimos: `lib/screens/order_tracking_screen.dart` (pílula em cima do mapa, perto de `:596`) e `lib/services/order_eta_service.dart` (formato). Nenhum proibido.

### (b) Mensagens de estado "chegou ao restaurante" / "a caminho de ti", como no TVDE

FALTA PARTE. O que existe:
- Cartão do seguimento: `_subLabel` (`order_tracking_screen.dart:1637-1684`) devolve frases fixas por estado: "Estafeta a caminho do restaurante" (`:1680`, depende do parceiro/loja), "Estafeta a caminho da sua morada" (`:1683`). Não usa o nome do estafeta nem o tempo.
- Push: `supabase/functions/notify-client/index.ts:320-325` envia "Estafeta a caminho do restaurante" (com nome do estafeta só no corpo), "Pedido recolhido" e "A caminho! Chega em ~X min".
- Existe `PartilharLocalizacaoController.aChegar` (`order_tracking_screen.dart:~395`) quando o estado é "a caminho" - é o aviso do pontinho azul, não uma mensagem.

O que NÃO existe:
- Estado "o estafeta chegou ao restaurante". O enum `OrderStatus` (`lib/models/order_model.dart:17-33`) vai de `driverAccepted` direto para `pickedUp`. O TVDE tem `motorista_chegou`. Criar o estado novo é zona amarela (muda estados e notificações).
- Frase "está a chegar" (estafeta perto da porta).

Duas soluções:
- Sem mexer em estados (verde, P): no cartão, calcular "chegou ao restaurante" quando a posição viva do estafeta está a menos de ~80 m do `pickupLocation` e o estado ainda é `driverAccepted`; "está quase a chegar" quando a menos de ~300 m do destino e `onTheWay`. É só distância no telemóvel, como o TVDE faz ("chegou = estado do servidor OU o carro já ali", `tvde_ride_tracking_screen.dart:1773-1790`). Texto novo com o primeiro nome do estafeta (já se carrega em `_fetchedDriverName`).
- Com estado (amarela, M): novo estado `arrivedAtPickup` no servidor e push. Só depois do desenho do despacho, e não é hoje.

Textos propostos (PT-PT): "{0} chegou ao restaurante", "{0} está a caminho do restaurante · chega em ~{1} min", "{0} vai a caminho de ti · chega em ~{1} min", "{0} está quase a chegar".

Ficheiros mínimos: `lib/screens/order_tracking_screen.dart` (`_subLabel`, `:1637`, e passar `driverName` e `driverPos` ao `_EtaBadge`/cartão), `lib/l10n/strings_en.dart` (frases novas). Se for para push: `supabase/functions/notify-client/index.ts` (amarela). Nenhum ficheiro proibido. `order_store.dart` e `errand_*` NÃO se tocam.

### (c) Avaliação no fim da entrega sem travar o cliente

EXISTE e não trava:
- Abre sozinha ao entregar: `_maybeOpenRating` (`order_tracking_screen.dart:278-322`), estafeta primeiro e depois parceiro.
- Tem "Saltar" (`lib/screens/rating_screen.dart:311`) e o botão de enviar não depende de estado global.
- Se saltar, volta a perguntar ao abrir a home, só até 2 vezes por pedido e só nas últimas 48 h (`lib/screens/client_home_screen.dart:153-215`, chave `rating_skipped_<id>_count`).

O que FALTA (pequeno):
1. Abre um ecrã inteiro por cima do seguimento no instante da entrega, quando o cliente quer ver a campainha da porta. O TVDE usa um ecrã com "Agora não" e `PopScope` (`tvde_rate_screen.dart:163-250`).
2. O botão chama-se "Saltar" no delivery e "Agora não" no TVDE.
3. Proposta mais leve: no cartão do seguimento, no estado entregue, uma linha "Como correu a entrega?" com 5 estrelas; ao tocar numa estrela abre o `RatingScreen` com essa nota já escolhida. O auto-abrir deixa de ser o primeiro contacto. Verde, M.

Ficheiros mínimos: `lib/screens/order_tracking_screen.dart` (cartão entregue; `_maybeOpenRating` passa a só abrir ao tocar), `lib/screens/rating_screen.dart` (parâmetro `notaInicial`; texto do botão). Nenhum proibido.

## Ordem sugerida para a M8 (só verde)
1. Frase de estado com nome e distância (b), em `order_tracking_screen.dart`.
2. Pílula do ETA em cima do mapa (a).
3. Estrelas no cartão entregue (c).
4. Depois, com "autorizo": estado novo "chegou ao restaurante" (amarela) e compensação por cancelamento tardio (vermelha, proposta apenas).
