# Rastreio em tempo real — resumo (07/10/2026, 22:00–23:50)

Agente: `estafeta-motorista`. Sem commit, sem push, sem `apply`/`execute_sql` no Supabase.
Não se tocou em dispatch, pricing, ganhos, RLS de orders/wallets/ledger, Stripe.
Aviso: outra sessão esteve a editar a mesma árvore ao mesmo tempo (Bora Assistente,
Maiores de 18): `strings_en.dart`, `AndroidManifest.xml` (RECORD_AUDIO), `main.dart`, etc.
Os ficheiros abaixo são só os meus; o `git status` traz também os dela.

## Ficheiros (todos em C:\BoraLocal\projetosflutter\bora_app)

Novos
- `lib/utils/rastreio_interpolacao.dart` — regra PURA do marcador: nunca anda para trás (amostra com `em` mais antigo OU igual é ignorada), rumo pelo `heading` (nulo/0 com velocidade > 0 → rumo entre os 2 últimos pontos; parado mantém), duração = intervalo real entre amostras (chão 240 ms, tecto 2× o poll / 8 s), por cima da rota (`passosSobreRota`) ou linha recta.
- `lib/utils/marcador_animado.dart` — o relógio à volta (fotogramas, `onFrame`, expirar, parar).
- `lib/services/driver_live_feed.dart` — Realtime na linha do condutor em `driver_locations` (filtro `driver_id = user_id`) + `lerAgora()` de reserva + `RastreioSettings` (lê as 4 settings uma vez).
- `lib/services/client_live_location_service.dart` — cliente envia a posição (RPC `client_live_location_upsert` a cada N s, `client_live_location_stop` ao parar) + lado do condutor (Realtime em `client_live_locations`, expira aos 30 s sem amostra).
- `lib/widgets/partilhar_localizacao_card.dart` — cartão com interruptor (opt-in, preferência em SharedPreferences `bora_client.partilhar_localizacao`) e o `PartilharLocalizacaoController` que vive no ecrã (não no cartão: o painel arrastável desmontava-o ao recolher e parava a partilha).
- `supabase/migrations/20261007230000_rastreio_tempo_real.sql` — **NÃO APLICADA, pôr na gaveta.**
- `test/rastreio_interpolacao_test.dart` (20 testes) e `test/gps_religar_corrida_test.dart` (8 testes).

Editados
- `lib/screens/driver/tvde/tvde_ride_active_screen.dart` — C3 religar; feed por tempo; pontinho azul.
- `lib/screens/driver_map_screen.dart` — feed por tempo com heading; pontinho(s) azul(is) por pedido.
- `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` — carro pelo `MarcadorAnimado`; canal Realtime; tocar no carro; cartão de partilha.
- `lib/screens/order_tracking_screen.dart` — estafeta pelo canal + poll de reserva; Directions com travão; câmara por amostra; cartão de partilha.
- `lib/services/driver_location_ping_service.dart` — `intervaloMinimo` opcional (nunca < 1 s; quem não passa fica com os 14 s).
- `lib/screens/admin/admin_platform_settings_screen.dart` — 4 chaves editáveis (E4).
- `lib/l10n/strings_en.dart` — 2 chaves novas ('Chega em ~{0} min', 'A calcular o tempo de chegada…'). As outras 6 frases do cartão já lá estavam (a outra sessão correu o gerador e apanhou-as do meu código); tirei os meus duplicados.

## O que cada tarefa ficou

**C3 — GPS próprio da corrida.** Confirmado no `geolocator_android` 5.1.1 (`getPositionStream` devolve o `_positionStream` em cache; só o `onCancel` do último ouvinte o põe a null). No `TvdeRideActiveScreen`, na primeira leitura: `_assumirGps()` (a home cancela o dela de forma síncrona) → `_religadoComDefinicoesDaCorrida = true` → `_startGps()` outra vez (cancela a subscrição herdada = último ouvinte = o geolocator larga o fluxo da home e cria um novo com `definicoesDeCorrida()`: bestForNavigation, 3 m, 700 ms, serviço da corrida). Volta a `false` em `_libertarGps()`. Mapa da entrega: NÃO partilha o fluxo (a home cancela antes do `push`), por isso não precisou de religar.
Decisão sobre `tvde_ride_gps_interval_seconds` (default 5): é a cadência da posição PARA O SERVIDOR (o que o cliente vê), em corrida TVDE e na entrega; o fluxo local fica a 700 ms/3 m porque a câmara de navegação do motorista precisa de ~1 Hz (a 5 s a seta andava aos saltos). Substitui o portão dos 50 m: envia por TEMPO, a andar ou parado (`_feedTicker` reenvia a última leitura) — parado num semáforo o cliente já não via "última posição há 60 s".

**E1 — cliente vê o condutor exacto.** (a) interpolação pelo intervalo real, rumo pelo heading/bearing, nunca para trás, sem saltos; (b) por cima da polilinha já desenhada (`_driverRouteLL` na corrida; `_routePoints` da entrega só quando é rota real, >2 pontos); (c) Realtime em `driver_locations` (não `drivers`: a RLS `drivers_select_own` nunca deixaria chegar nada ao cliente — e é por isso que o DriverStore `drivers_channel` dava vazio) + poll de reserva (`tvde_ride_driver_card` na corrida ao `tvde_driver_card_poll_seconds`; `lerAgora()` na entrega); a mesma leitura pelas duas portas é ignorada (hora igual); (d) tocar no carro centra e abre folha com nome, carro/cor/matrícula e ETA. Ícones: carro azul desenhado (TVDE, já existia) e o `MapMarkerHelper.driverIcon` (mota, já existia) nas entregas — este não roda (é um crachá redondo; rodar o crachá não lê como direcção). DriverStore ficou intocado (serve ao lado do motorista/admin).

**E2 — pontinho azul.** Migração com `client_live_locations` (RLS: cliente insere/actualiza/apaga só o seu; SELECT só `driver_user_id = auth.uid()`), índice por `driver_user_id`, REPLICA IDENTITY FULL (o DELETE do Realtime com filtro precisa da linha inteira), RPCs que validam dono + condutor atribuído e descobrem o `driver_user_id` (TVDE: `tvde_rides.driver_id` → `drivers.user_id`; entregas: `orders.assigned_driver_id::uuid`), gatilhos AFTER UPDATE OF status em `tvde_rides` e `orders` que SÓ fazem DELETE nesta tabela (SECURITY DEFINER; `CREATE OR REPLACE TRIGGER`, sem DROP). Settings `client_live_location_enabled` (true) e `_interval_seconds` (4). Cliente: cartão com interruptor quando TVDE `motorista_a_caminho` / entrega `onTheWay`, pede permissão com texto PT-PT, envia a cada N s, pára sozinho ao sair do estado, ao desligar, ao fechar o ecrã ou quando o servidor responde `ok=false`. Condutor: ponto azul (ecrã da corrida e mapa da entrega, um por pedido), mesma interpolação, some ao DELETE ou aos 30 s sem amostra.

**E3 — serviço em primeiro plano no Android 15.** Encontrado: o serviço partilhado (`flutter_foreground_task` 8.17.0) está declarado `dataSync|remoteMessaging`; o GPS em primeiro plano das corridas/entregas e do "online" já corre no serviço PRÓPRIO do geolocator (`GeolocatorLocationService`, tipo `location`, sem limite de 6 h). **Não mudei o manifesto**: a 8.17.0 arranca SEMPRE com `FOREGROUND_SERVICE_TYPE_MANIFEST` (ForegroundService.kt:260) e não tem `serviceTypes` nem `onTimeout` — acrescentar `location` rebentava o parceiro (SecurityException sem permissão de GPS), e não dá para escolher o tipo por papel. O caminho certo é subir o plugin para ≥ 9.1.0 ("Support manual foregroundServiceType via serviceTypes in startService"; 9.0.0 trouxe `isTimeout` no onDestroy para o limite do Android 15), declarar `location|dataSync|remoteMessaging` e arrancar com `[location, remoteMessaging]` no estafeta e `[dataSync, remoteMessaging]` no parceiro — é uma subida de dependência nativa que precisa de prova em aparelho, não a fiz hoje. Prova de que o limite ainda não mordeu: `debug_crash_logs` sem nenhuma linha com "did not stop within" nem "dataSync" (REST, 07/10 23:3x). O limite reinicia quando a app vem à frente.

**E4 — painel admin.** As 4 chaves (`tvde_ride_gps_interval_seconds`, `tvde_driver_card_poll_seconds`, `client_live_location_enabled`, `client_live_location_interval_seconds`) ficaram editáveis em `_isEditable` (lista `tvdeNavOperational`); o ecrã lista-as sozinho pela categoria `tvde` assim que a migração as criar.

**E5 — erros do mapa corrigidos pelo caminho**
1. Cliente da ENTREGA nunca via o estafeta: a posição vinha do DriverStore (`drivers` por Realtime), que a RLS `drivers_select_own` bloqueia ao cliente, e `orders.driver_lat` não é lido (deprecated). Agora: canal em `driver_locations` (depende da migração).
2. Carro a andar para TRÁS quando uma resposta velha chegava depois de uma nova (poll de 4 s sem ordenar por `location_updated_at`) → ignorada.
3. A mesma leitura pelo Realtime e pelo poll assentava o carro no fim a meio da animação (salto) → hora igual ignorada.
4. Animação de 12×80 ms fixos com amostras de 4-5 s (deslizava 1 s, parava 3) → duração = intervalo real.
5. Heading a 0 (telemóvel parado/sem bússola) rodava o carro para norte a andar para sul → rumo entre pontos.
6. Motorista parado num semáforo ficava "última posição há 60 s" (portão dos 50 m não enviava nada) → envio por tempo.
7. Rastreio da entrega pedia rota nova ao Directions a cada ~11 m do estafeta (chave com 4 casas) → só com destino novo, passados 45 s ou fora da rota > 60 m.
8. Rastreio da entrega encaixava a câmara (`newLatLngBounds`) em cada fotograma da animação (~12×/s, mapa a tremer) → encaixa por amostra.
9. Estafeta em entrega subia a `driver_locations` só pelo batimento (30 s) e sem heading → a cada 5 s com heading e velocidade.

## Provas
- `flutter test test/rastreio_interpolacao_test.dart test/gps_religar_corrida_test.dart test/l10n_cobertura_test.dart` → `00:09 +39: All tests passed!`
- `flutter analyze` completo (31,4 s) → **0 erros**, 266 avisos/infos antigos (`analyze_full.txt` ao lado). Nos ficheiros que toquei só aparecem 4 avisos antigos, nenhum meu: `use_build_context_synchronously` em tvde_ride_active_screen.dart:1717, `BRDriver` não usado e parâmetro `bold` em driver_map_screen.dart, `value` deprecated em order_tracking_screen.dart:1317.
- RAM medida antes de cada analyze/test: 1286 MB, 1090 MB (portão pesado 800 MB cumprido).
- REST: `platform_settings` não tinha as 3 chaves novas; `client_live_locations` não existe (404) — a migração é toda nova.

## Ficou de fora e porquê
- Migração por aplicar (ordem: só na gaveta). Até lá: TVDE funciona como hoje (poll) com a interpolação nova; a entrega continua sem estafeta no mapa do cliente (já era assim); o cartão do pontinho azul aparece mas o RPC falha em silêncio (o envio pára sozinho) — se preferires escondê-lo até à migração, `client_live_location_enabled=false` não existe ainda, logo o cartão aparece: é o único efeito visível antes da migração.
- E3: subida do `flutter_foreground_task` para ≥ 9.1.0 (ver acima) — não feita, precisa de prova em aparelho.
- Limpeza de linhas expiradas em `client_live_locations` por cron: não criei job; os gatilhos e o `stop` apagam, e o condutor ignora o que expirou.
- Prova em aparelho real (religar do GPS, pontinho azul): não havia motorista de teste ligado; os testes são de regra pura e de contrato no código-fonte.
- Ícone da mota não roda pelo heading (crachá redondo).
