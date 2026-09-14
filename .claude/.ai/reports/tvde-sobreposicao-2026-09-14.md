# TVDE — sobreposição de corridas (back-to-back, "igualzinho à Uber")
**Missão** `tvde-sobreposicao-back-to-back` · 14/09/2026 · Opus 5 · Claude Code · ramo `autonomous-night-2026-04-29`
**run_id** `tvde-sobreposicao-2026-09-14` · e2e_log ids 1780–1793 · provas em `.claude/.ai/provas/tvde-sobreposicao-2026-09-14/`

## Acessos (no topo, como manda o Bloco F)
- Supabase `ojykpzwqrtusfeakzrna` por MCP (SQL, migrations, deploy da Edge). Córtex MCP **pedia autenticação** — não foi usado; o rasto ficou no `e2e_log` e neste ficheiro.
- Emulador Android `emdia` (API 34) no PC, APK debug construído localmente com o `.dart_defines` local.
- Ponte Telegram (`orquestracao/ponte-telegram.sh`) — 2 mensagens enviadas e lidas de volta no log do servidor.

## O que NÃO ficou feito / o que correu mal (lê isto primeiro)
1. **INCIDENTE causado por mim, às 16:51.** Uma corrida de TESTE minha (Intermarché → R. Francisco de Passos, cliente demo) foi oferecida ao **Valdemir** (motorista real), ele aceitou às 16:51:14 e eu cancelei às 16:51:51 — cancelada como cliente, taxa 0, push "Corrida cancelada… não precisas de ir" enviado (`push_enviado ride_cancelled`). Sem dinheiro envolvido. Avisei-te logo pelo Telegram (16:53). **Causa:** pus a oferta ao motorista demo com 10 minutos de validade e os quatro motoristas reais na lista de tentados, mas a Edge `notify-tvde-driver` **re-ancora o `offer_expires_at` para 40 s** depois de o push sair; a oferta ao demo expirou, o sweep esperou a pausa de 35 s, limpou a lista de tentados e ofereceu ao real mais próximo. É comportamento normal do despacho (não é bug), foi erro meu no desenho do teste. Lição gravada na memória: com motoristas reais online, um pedido sintético só é seguro sem passar pela oferta.
2. **A oferta em sobreposição aceite a partir da faixa (item 5 → aceitar) não foi aceite no emulador**: a oferta já tinha expirado quando carreguei (pelo mesmo re-ancorar dos 40 s). O aceite em fila está provado em rollback (P2) e o caso real do Valdemir de hoje (fila pelo admin) é o mesmo caminho do servidor. A faixa em si está provada na captura.
3. **Push `queued_added` ao motorista**: no ar, a Edge v16 aceita o kind (HTTP 200, evento com `kind=queued_added`), mas o corpo da mensagem só se prova com um motorista com token FCM — o demo só ganhou token depois, e não voltei a chamar. Fica por provar o texto do push (o código é o mesmo padrão dos kinds de reserva).
4. **Vídeo P3**: a primeira gravação perdeu-se (o Git Bash trocou `/sdcard/...` por `C:/Program Files/Git/sdcard/...`); repeti a transição inteira com uma terceira corrida e gravei (`P3_transicao_automatica.mp4`, 159 s). Está feito, mas custou uma volta.
5. **Nada de Córtex**: `cortex_*` pedia autenticação nesta sessão. O digest foi para `claude_ai_memoria`.
6. **RAM**: 272 MB disponíveis no arranque (portão 400) — o consumidor era o `llama-server` do Ollama (4,9 GB, serviço vivo, não é meu para matar); avancei com a parte de ficheiros/SQL e medi outra vez antes do `flutter analyze`: 1217 MB.

## Como ficou a funcionar (em português para ouvir)
Quando um motorista larga uma corrida e o outro está ocupado, o sistema **chama o ocupado na mesma**: a oferta aparece **por cima do ecrã da corrida que ele está a fazer**, com o que ele **ganha em grande**, a frase "depois desta corrida" e a distância de onde vai largar até onde vai buscar. Ele aceita e **continua no passageiro que leva**; a nova fica num cartão "Próxima corrida" e no mapa em tom mais claro. Quando termina a actual, a app **abre sozinha** a seguinte. O cliente da corrida em fila vê "o teu motorista está a terminar uma corrida aqui perto" com um tempo que soma o que falta da corrida em curso mais o caminho até ele. Se o ocupado recusar ou deixar passar, a roda segue — e pode voltar ao livre (como tu confirmaste). No painel admin vê-se quem está em fila e atrás de quê, e há um botão para reatribuir uma corrida a outro motorista (livre = recebe já; ocupado = entra na fila dele). Tudo com interruptor e limites em `platform_settings`.

## BLOCO A — despacho (servidor)
| # | O que | Prova |
|---|---|---|
| A.1 | Migration **20260914150204** `tvde_sobreposicao_pool_unico_e_guarda_accept`: `tvde_offer_to_next` com UM pool ordenado (prio 1 livres por distância à recolha = pool antigo byte a byte; prio 2 ocupados elegíveis por destino-actual → recolha-nova, online+heartbeat, exactamente 1 activa não-fila numa fase ≥ `min_stage`, fila < `max_queue`, sem entrega, sem reserva a travar, não tentado, raio); evento `oferta` continua a levar `queued_candidate`. `tvde_accept_ride`: fila com QUALQUER activa não-fila, `queue_full`, guarda final `ride_conflict`. `tvde_cancel_ride`: largar só a fila não promove outra por cima da viagem (substituição cirúrgica sobre a definição viva, taxa não tocada; md5 novo `d9187d57…`, definições antigas guardadas no e2e_log id 1781). Settings: `tvde_backtoback_enabled=true`, `tvde_backtoback_max_queue=1`, `tvde_backtoback_min_stage=motorista_a_caminho` (categoria tvde, com descrição → aparecem e editam-se no painel), `tvde_queue_pickup_radius_km` 3→5. | Prova em rollback contra as funções JÁ em produção, 12/12 ok — `prova_A_resultado_pos_migration.json`: P5a livre primeiro (queued_candidate=false) · **P1** ocupado chamado depois de A largar (queued_candidate=true) · P1b B recusa → no_driver_since · P1c tentados limpos → volta a A · **P2** B aceita em `motorista_a_caminho` → `motorista_atribuido`+`is_queued`, activas não-fila do B = 1 · P2b 2.ª oferta → `queue_full` · item 9 largar só a fila → `solicitada`, a que leva intacta, 0 promoções · **P6** `enabled=false` → nenhum ocupado chamado · `min_stage=em_andamento` respeitado · **P5** `sem_motorista` após 120 s e aceite livre = `motorista_a_caminho` |
| A.3 | Migration **20260914151041** `tvde_admin_reassign_ride_e_queue_info`: `admin_tvde_reassign_ride(p_ride_id, p_driver_id, p_motivo)` — aceita `drivers.id` OU `drivers.user_id`, grava sempre `user_id`; livre → `motorista_a_caminho`; ocupado → fila (`queue_full` respeitado); limpa oferta/tentados/no_driver_since; evento actor `admin` com motivo; promove a fila do motorista antigo se lhe tirou a activa; push aos dois; `log_admin_action`. `tvde_ride_queue_info(p_ride_id)` (cliente/motorista/admin): ETA somado com `eta_avg_speed_kmh`, sem expor nada do outro passageiro. `admin_tvde_rides_list` com `queued_behind_ride_id` e `queue_next_ride_id`. | Rollback 10/10 ok — `prova_A3_resultado_pos_migration.json`: D1 reatribuir ao ocupado pelo `drivers.id` → fila com `user_id` + push `queued_added` · C1 ETA 11 min (3,20 km + 1,58 km a 28 km/h) · C1b estranho → `not_ride_party` · D2 lista liga fila↔activa · D3 reatribuir ao livre → pushes `ride_assigned`/`ride_reassigned_away` · D4 fila do antigo sobe · D5 `same_driver` / `ride_not_reassignable: em_andamento` / `driver_not_found` / não-admin bloqueado |
| A.4 | Edge **notify-tvde-driver v16**: ramo novo para `queued_added` / `ride_assigned` / `ride_reassigned_away` → push data-only `type=tvde_queue_update` ("Ganhas €x", regra de ouro). Kinds antigos intactos. | Deploy por MCP (v16, verify_jwt=true). `net.http_post` req 1100 → HTTP 200 `{ok:false, reason:no_fcm_token}` com evento `kind=queued_added` (motorista de teste sem token). Corpo do push por provar (ver "o que não ficou feito" 3). |

**`tvde_finish_ride` não foi tocada** (a tua correcção: já promove a fila — provado hoje às 15:35:13 com corrida real). `dispatch-engine` intacto. Funções de reserva intactas.

## BLOCO B — app do motorista
- `tvde_driver_store.dart`: a oferta é aceite em qualquer fase (só se esconde quando já há fila); `releaseQueuedRide` (item 9); **`_reloadActiveAfterTerminal`** — corrige uma corrida com o realtime que já existia: quando a promoção da fila chegava pelo realtime ANTES de a RPC responder, o código antigo escrevia a corrida finalizada por cima da promovida e o ecrã ia para a avaliação em vez de abrir a seguinte; agora relê sempre do servidor e nunca deixa a corrida a null (um null momentâneo fecha o ecrã). Item 10: duas activas não-fila → fica a mais comprometida e grava aviso no `e2e_log` (`tvde-duas-activas`).
- `tvde_ride_active_screen.dart`: faixa de oferta sobreposta em qualquer fase (ganho em grande, `TvdePayBadge`, "Recolha a X km de onde vais largar"), cartão "Próxima corrida — depois desta" com "Largar a próxima", linhas tracejadas em tom claro + pinos azuis da próxima (destino actual → recolha → destino).
- `tvde_driver_home_screen.dart`: o poll da oferta deixa de exigir `em_andamento`.
- `notification_service.dart`: `tvde_queue_update` (persistente + reler o store + tap).
- **Prova no emulador**: item 5 — capturas `17_oferta_sobreposta.png` (push heads-up "Nova corrida!" + faixa por cima da corrida activa em `motorista_a_caminho`) e `18_oferta_sobreposta_limpa.png`; item 7 — `21_fila_cartao.png`, `27/28_painel.png`, `26_rota_fila_tracejada.png`; **P3** — `59-61_p3b_trio.png` (Finalizar → "JÁ PAGO NA APP, ganhaste €4.00" → ecrã já na corrida seguinte, "Navegar até à recolha"/"Cheguei ao passageiro") e **`P3_transicao_automatica.mp4`** (159 s); no servidor a finalizada e a promovida têm o mesmo segundo (19:46:34, evento `queued_activation`).

## BLOCO C — app do cliente
- `tvde_ride_tracking_screen.dart`: em fila, o ETA vem de `tvde_ride_queue_info` (soma), a frase é "{nome} está a terminar uma corrida aqui perto · chega em ~N min", cabeçalho "{nome} está a terminar uma corrida", texto "O teu motorista está a terminar uma corrida aqui perto e segue logo para a tua recolha. És o próximo.", sem rota enganadora até à recolha; EN adicionado.
- **P4 no emulador**: `39_cliente_fila_eta.png` — "Estafeta está a terminar uma corrida aqui perto · chega em ~9 min" (ETA real 11 = 3,2 km que faltam + 1,58 km de ligação a 28 km/h, menos os 20 % de apresentação), com a mensagem.

## BLOCO D — painel admin (PT-BR)
- `admin_tvde_rides_screen.dart`: "Em fila atrás de: …" e "Leva atrás (fila): …" com cliente e rota; botão **Reatribuir corrida** (corridas vivas) → diálogo com a lista de motoristas de passageiros aprovados, cada um marcado "Livre — recebe a corrida direto" / "Ocupado (N em curso, M em fila) — entra na fila dele" / "Offline", campo de motivo, chama `admin_tvde_reassign_ride`; erros traduzidos (`queue_full`, `ride_not_reassignable`, `same_driver`).
- Settings novas visíveis e editáveis no ecrã de definições (categoria tvde, com descrição) — a RPC `admin_update_setting` aceita bool e texto.
- Sem prova de ecrã do painel (não corri a web); a RPC por trás está provada (D1–D5).

## Qualidade
- `flutter analyze`: **0 erros** (219 infos/warnings pré-existentes; os 2 infos novos são o `groupValue` deprecado do RadioListTile, mesmo padrão já usado no painel).
- `flutter test`: **521 passed** (TVDE: 146 passed; a ordem falava em 57 — não baixou).
- RAM: 272 MB no arranque (declarado acima), 1217 MB antes do analyze, 2599 MB antes do emulador.

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO?
Não. Nenhuma alteração toca em preço, comissão, tokens, Stripe ou carteira. `tvde_cancel_ride` foi alterada só na promoção da fila (a taxa de cancelamento ficou byte a byte igual). O saldo do motorista demo, que as duas finalizações de teste puseram a −8,00 €, foi reposto a 0,00 € e as 4 corridas de teste e os eventos foram apagados (confirmado por SELECT).

## Como se reverte
- Despacho: as três definições antigas estão no `e2e_log` id 1781 (executar cada bloco tal e qual) ou `update platform_settings set value='false' where key='tvde_backtoback_enabled'` (volta ao comportamento antigo sem tocar em código — P6 provado).
- Edge: redeploy da v15 (o ficheiro do repo antes deste commit).
- App: reverter o commit desta missão.

## PARA O DANILO
- Nada que só tu possas fazer. O incidente do Valdemir está explicado acima e já te foi dito pelo Telegram; se ele perguntar, foi um pedido de teste meu cancelado 37 segundos depois.
- Decisão que fica contigo (não bloqueia): `tvde_backtoback_max_queue` está a 1 (uma corrida em fila, como a Uber). Sobe no painel se quiseres mais.

## Publicação
- Commit `977e5f08` no ramo `autonomous-night-2026-04-29`, push `34968251..977e5f08` (só este commit viajou; o ramo estava 2 atrás — bump 605 e espelho do Córtex — e foi fast-forward antes). O CI (`build_android.yml`) corre o autoteste dos 3 perfis, faz o bump (esperado 606) e sobe ao Play; a web sai no mesmo push. Prova do build: `app_latest_version_code` em `platform_settings` a subir para 606 — ainda não confirmado à hora deste relatório.
