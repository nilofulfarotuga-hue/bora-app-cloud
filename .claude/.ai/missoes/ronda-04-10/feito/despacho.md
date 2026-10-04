# Relatório — agente DESPACHO (ronda de correção 04/10/2026)

Ramo: `agente-despacho` @ 72af81e8 (commitado, sem push para ramos de publicação).
CI: `analise-despacho` = 72af81e8 + commit só-CI (workflow estrito) → run **37229487436 VERDE** (analyze + testes).
Não houve mudanças em Flutter (lib/) — só migrations e Edge Function.

## FEITO

### Migration 20261004160100 `despacho_candidatos_e_ofertas` (aplicada em produção)
Ficheiro: `supabase/migrations/20261004160100_despacho_candidatos_e_ofertas.sql`
- Settings novos (nascem com valor pedido): `dispatch_gps_fresh_seconds_entregas=900`, `dispatch_raio_max_oferta_km=20`.
- Nova `dispatch_candidatos_entrega(order_id)` (só service_role): o matching das entregas num sítio só —
  online + aprovado + não banido (ou ban expirado) + não apagado + não `rides_only` + **heartbeat E GPS
  mais novos que 900 s** (sem o pôr offline) + carro quando exigido + `aceita_papel(delivery)` + sem corrida
  TVDE ativa + **uma oferta viva de cada vez** (salvo outra oferta da MESMA loja) + **Favor nunca agrupado**
  (favor só a estafeta livre; quem leva favor não recebe mais nada) + máx. 3 ativos + **raio máximo**;
  ordena mesma-loja primeiro, depois distância.
- Nova `_dispatch_service_jwt()` (chave de serviço do cofre) e os chamadores do banco passam a usá-la:
  `invoke_dispatch_engine`, `fn_dispatch_on_calling_driver`, `bora_dispatch_maintenance`,
  `invoke_notify_driver`, `_notify_driver_offer_http`, `fn_notify_driver_on_offer` (antes mandavam o JWT anónimo).
- Achado A1 confirmado na produção: Valdemir online com heartbeat a bater mas GPS de há 1 dia (03/10 19:17) — entrava nas ofertas.
- PROVA (DO + RAISE, desfeito): agora=[Danilo 2,1 km] (Valdemir fora) | GPS fresco → Valdemir entra |
  banido → sai. Oferta viva noutra loja → Danilo fora; mesma loja → Danilo volta; favor com Danilo ocupado →
  só Valdemir; Danilo com favor aceite → fora de tudo; recolha a 110 km → ninguém.
- ⚠️ O dispatch-engine ainda NÃO usa esta função (ver NÃO FEITO). Por isso A1/#4/#5 estão prontos e provados
  no banco mas ainda não mandam nas ofertas reais.

### Migration 20261004160200 `despacho_cancelar_e_heartbeat` (aplicada)
Ficheiro: `supabase/migrations/20261004160200_despacho_cancelar_e_heartbeat.sql`
- **A3 `driver_cancel_order`**: procura o pedido por `user_id` OU `id` do estafeta (antes só `drivers.id`, e a
  app grava `user_id` → falhava para quem tem id≠user_id); limpa `assigned_driver_id`, `driver_id`,
  `driver_phone`, `preassigned_driver_id` (antes o gatilho de pré-atribuição voltava a oferecer ao mesmo),
  oferta e `dispatch_next_retry_at`; `tried_driver_ids` += drivers.id; chama o motor com chave
  (`invoke_dispatch_engine`); fecha a anon. PROVA (estafeta demo id≠user_id): outro estafeta → recusa;
  o próprio → ok; depois: callingDriver, todos os campos NULL, tried={dede…0002}.
- **A6 heartbeats**: `driver_heartbeat()`, `driver_heartbeat(text)` e `driver_heartbeat_by_id` deixam de pôr
  `is_online=true`; `driver_update_location(p_is_online=true)` também não liga (false continua a desligar —
  é o ping do botão "offline"); `driver_locations.is_online` = pedido E botão.
  `driver_heartbeat_by_id` (forma antiga, apps nos telemóveis): com sessão → só o próprio; sem sessão (FGS
  Android) → só renova o sinal de quem JÁ está online. Novo caminho seguro: tabela
  `driver_heartbeat_segredos` (RLS ligada, sem acesso direto) + `driver_heartbeat_segredo_obter(p_renovar)`
  (com sessão) + `driver_heartbeat_segredo(p_driver_id, p_segredo)` (anon, exige segredo).
  Revogado anon de `driver_heartbeat*` com sessão, `driver_update_location`, `driver_cancel_order`.
- **08 "mudar a posição GPS de qualquer estafeta"** = `driver_push_position(text,…)` (anon, qualquer id):
  agora só o próprio, admin ou serviço; anon revogado. (Nenhum código atual a chama.)
- PROVA A6: anon by_id em estafeta offline → não mexe; anon by_id em online → só sinal; anon push_position →
  permission denied; demo com sessão faz heartbeat + posição p_is_online=true → continua OFFLINE;
  sessão de um a fingir outro → recusa; push_position de outro → forbidden; segredo bom → ok, mau → forbidden.

### Migration 20261004160300 `despacho_parceiro_chamada_no_tempo` (aplicada) — C4 servidor
Ficheiro: `supabase/migrations/20261004160300_despacho_parceiro_chamada_no_tempo.sql`
- Settings `dispatch_antecedencia_minutos=8`, `dispatch_antecedencia_agendado_minutos=30`.
- Coluna `orders.accepted_at` + gatilho `trg_orders_set_accepted_at` (preenche ao passar a preparing).
- `partner_auto_dispatch_ready_orders` (cron 72): com `scheduled_for` → `scheduled_for − 30 min`, nunca antes;
  com prep → `accepted_at + greatest(0, prep − 8)`; sem prep → como hoje (5 min, `partner_auto_dispatch_after_minutes`;
  0 continua a desligar). Pedidos antigos sem accepted_at usam `status_updated_at`.
- PROVA (Goola, cliente@bora.app, desfeito): sem prep 6 min → chama; 2 min → espera; prep 25/10 min → espera;
  prep 25/18 min → chama; festa daqui a 3 dias → espera; marcado daqui a 20 min → chama.
- **Porteiro das lojas por telefone intacto** (DaVinci): ao pedir estafeta fica `preparing` (prep 20, na fila);
  o cron de parceiros não lhe toca; aos 16 min o `encomendas_telefone_relogio` liberta → callingDriver.

### Edge `notify-driver` v42 (publicada, verify_jwt=false como no ar)
Ficheiro: `supabase/functions/notify-driver/index.ts` — exige chave de serviço (env ou a do cofre, validada
na Auth) ou JWT de admin. Chamadores verificados: gatilhos/funções do banco (agora com chave),
`admin-cancel-order` (cliente service), `client_respond_budget_increase` (chave do cofre). A app não a chama.
PROVA (pg_net): chave de serviço → 200 `stale_offer` (pedido inexistente, ninguém notificado); JWT anónimo → 403; sem token → 403.
`notify-driver-assigned` já estava fechado (verify_jwt=true + role service_role) — sem mudança.
Motor no ar continua a responder: chamada com a chave nova → 200 `{"ok":true}`.

## NÃO FEITO
1. **dispatch-engine (Edge)** — autenticação (#6) e passar a usar `dispatch_candidatos_entrega` (o que liga
   A1, #4 e #5 às ofertas reais). A edição do ficheiro foi **bloqueada pela proteção automática do Claude Code**
   (zona protegida `dispatch_engine`). Não contornei. Ver PRECISA DE CONFIRMAÇÃO.
2. Flutter do serviço em segundo plano a usar o segredo — é ecrã/serviço do estafeta (ver PEDIDO A app-estafeta).

## PRECISA DE CONFIRMAÇÃO
**Mudança no dispatch-engine (v62), pronta a aplicar por quem tiver permissão para a zona protegida:**
- No `Deno.serve`, logo após ler `orderId`: validar `Authorization` → aceitar se for a chave de serviço do
  ambiente, ou JWT `role=service_role` aceite pela Auth (`GET /auth/v1/admin/users?per_page=1` com esse token,
  guardar em cache), ou JWT de utilizador (`auth.getUser`) que seja admin, estafeta aprovado (`drivers.user_id`),
  dono do pedido (`orders.user_id`) ou dono da loja (`restaurants.user_id`/`user_`); senão 403.
  (A app chama-o com a sessão do cliente/parceiro/estafeta; os gatilhos já mandam a chave de serviço.)
- Em `dispatchOrder`: `const candidatos = (await supabase.rpc('dispatch_candidatos_entrega', { p_order_id: order.id })).data`
  mapeado para `{id: driver_id, user_id, lat, lng, vehicle_type, dist: dist_km}`; o "cycle reset" passa a usar
  `candidatos` em vez da query a `drivers`; `findNextDriver` = primeiro candidato cujo `driverKeys` não está em
  `triedIds`. Tudo o resto (ofertas, TTL, claim, redispatch, identidade v59) igual. verify_jwt fica false.

## PEDIDOS A OUTROS AGENTES
- **PEDIDO A app-estafeta** — `lib/services/foreground_service.dart`:
  1) em `saveDriverId` (tem sessão), depois de `_ligarTokenDeSessao()`:
     `final r = await Supabase.instance.client.rpc('driver_heartbeat_segredo_obter'); if (r is Map && r['ok'] == true) await FlutterForegroundTask.saveData(key: 'fgs_hb_segredo', value: r['segredo'] as String);`
     e em `clearDriverId`: `await FlutterForegroundTask.removeData(key: 'fgs_hb_segredo');`
  2) no tick do heartbeat (linha ~309): ler `fgs_hb_segredo`; se existir, `POST $url/rest/v1/rpc/driver_heartbeat_segredo`
     com body `{'p_driver_id': driverId, 'p_segredo': segredo}`; senão manter `driver_heartbeat_by_id` (transição).
  Nota: a app já não pode contar com o heartbeat para voltar a ficar online — só o botão liga (regra do Danilo).
- **PEDIDO A admin-geral** — `lib/screens/admin/admin_platform_settings_screen.dart`: mostrar/editar os 4 settings
  novos (`dispatch_gps_fresh_seconds_entregas`, `dispatch_raio_max_oferta_km`, `dispatch_antecedencia_minutos`,
  `dispatch_antecedencia_agendado_minutos`) junto de `partner_auto_dispatch_after_minutes`; e no detalhe do
  pedido mostrar `accepted_at` (hora de Lisboa).
- **PEDIDO A parceiro** — ao aceitar um pedido normal, gravar `prep_time_minutes` (hoje só as encomendas de festa
  o gravam → sem ele fica a regra antiga dos 5 min) e garantir o botão "Chamar estafeta já" (hoje
  `restaurantMarkReady` → callingDriver) visível durante a preparação.

## RISCOS
- Até o dispatch-engine ser atualizado, as ofertas reais continuam com o matching antigo (estafetas com GPS
  parado podem receber ofertas; várias ofertas ao mesmo estafeta). Os gatilhos já mandam chave → atualizar o
  motor não parte nada do banco.
- `driver_heartbeat_by_id` continua aberto a anon para estafetas JÁ online (só renova o sinal; não liga, não
  mexe na posição) até as apps novas usarem o segredo.
- Quem ficar offline por outra razão (documento expirado, admin) já não volta sozinho pelo heartbeat — é o
  comportamento pedido; o estafeta tem de carregar no botão.
- Raio de 20 km é novo (antes não havia limite) — ajustável no setting.
