# Agente parceiro — relatório (04/10/2026)

Ramo: `agente-parceiro` (worktree ../wt-ronda/parceiro), base `origin/autonomous-night-2026-04-29` @ 5b76a212.
Ramo final `agente-parceiro` @ 3fd1f605. CI: `analise-parceiro` @ 4547010b (3fd1f605 + só o commit do workflow estrito) — run 37235715565 **VERDE**
(flutter analyze sem erros, 7 avisos = igual à base medida no run 37235154340 de `analise-parceiro-base`; flutter test verde).
Migrations aplicadas em produção: `parceiro_campos_admin_pedidos_por_loja`, `parceiro_c1_campos_admin_mensagem`,
`parceiro_pausa_esgotado_feriados_chamar_estafeta`, `parceiro_chamar_estafeta_sem_colunas_geradas`, `parceiro_extrato_sem_markup_ganhos`
(ficheiros no ramo: 20261004213000_, 20261004213500_, 20261004214000_ — já com as correções). Edge: notify-partner v24, upload-restaurant-asset v7.

## FEITO

### 1. C1 — campos que só o admin muda (`restaurants`)
- Migration `20261004213000_parceiro_campos_admin_pedidos_por_loja.sql` (aplicada como `parceiro_campos_admin_pedidos_por_loja` + correção da mensagem `parceiro_c1_campos_admin_mensagem`).
- Gatilho `trg_restaurants_campos_so_admin` (BEFORE UPDATE, `CREATE OR REPLACE TRIGGER`), função `_restaurants_campos_so_admin()`:
  recusa `ADMIN_ONLY_FIELDS: <campos>` quando a escrita é direta de um utilizador (`current_user` authenticated/anon) que não é admin e muda
  name, user_id, user_, is_partner, app_markup_pct, partner_commission_billing, approval_status, approved_at/by, is_active_admin,
  avg_rating, ratings_count, stripe_* (6), min_order_cents_override, small_order_fee_cents_override.
- Caminhos legítimos verificados: a app do parceiro só escreve is_online, reservations_enabled, takeaway_enabled, curbside_enabled,
  takeaway_default_prep_minutes, business_hours, photo_url, fcm_token (restaurant_store.dart, auth_store.dart, notification_service.dart,
  register_partner_screen.dart). TODAS as funções que fazem UPDATE em restaurants são SECURITY DEFINER (approve_partner, reject_partner,
  admin_update_partner_*, admin_set_partner_special_date, apply_stripe_account_update, _update_restaurant_avg_rating, robot_apply_suggestion,
  admin_definir_loja_telefone, provider_update_legal_fields) → correm como dono e passam. service_role passa. Admin pela app passa (is_admin()).
- PROVA (desfeita, sessão do dono da Goola): is_online/horário/foto/tempo de preparação → 1 linha; `app_markup_pct` → `ADMIN_ONLY_FIELDS: app_markup_pct`;
  `name` → `ADMIN_ONLY_FIELDS: name`; `user_id` → `ADMIN_ONLY_FIELDS: user_id, user_`; admin (Danilo) muda min_order/app_markup → 1 linha;
  postgres (como o gatilho das avaliações) muda avg_rating → 1 linha.

### 2. C2 — pedidos do parceiro por `restaurant_id`
- Mesma migration: `parceiro_minhas_lojas()` (SECURITY DEFINER, lojas onde user_id OU user_ = auth.uid(); não depende do RLS de restaurants,
  que esconde lojas por aprovar). `ALTER POLICY orders_select_partner` e `orders_update_partner` → `restaurant_id IN (SELECT parceiro_minhas_lojas())`.
- `orders_insert_partner` → `WITH CHECK (false)` (o parceiro já não insere pedidos direto; o "Chamar estafeta" passa pela RPC, ver 5).
- Gatilho `a0_orders_preenche_restaurant_id` (BEFORE INSERT, corre antes dos outros): pedido de parceiro sem restaurant_id → preenche pelo nome
  só se o nome aponta para UMA loja parceira.
- Preenchimento dos antigos: cópia `bkp_orders_restaurant_id_20261004` (RLS ligada); havia 6 pedidos sem loja e 0 de parceiro com nome
  resolúvel → 0 linhas mudadas (nenhum pedido de parceiro estava sem restaurant_id).
- `_partner_owns_order` aceita também `user_`.
- PROVA (desfeita): Goola vê 6 pedidos seus e 0 da Sabores de Casa; Sabores vê 2 seus e 0 da Goola; Goola a alterar pedidos da Sabores → 0 linhas;
  Goola a inserir pedido direto → "new row violates row-level security policy". Pedido de teste inserido com restaurant_id NULL → `rid_preenchido=goola-acai-guarda`.

### 3. C3 — cartões "Ganhos hoje/semana/totais"
- RPC nova `partner_ganhos_resumo(loja)` (migration `20261004214000_parceiro_extrato_sem_markup_ganhos.sql`, aplicada): MESMA expressão do
  "Ver detalhe de ganhos" (`order_financials.restaurant_amount` ou `partner_store_share`), só `delivered`, sem testes; hoje/semana(7 dias, como o extrato)/total em hora de Lisboa.
- `partner_dashboard_screen.dart`: os cartões leem a RPC (recarrega quando muda o nº de entregues); apagados `_sumEarningsSince`/`_partnerRevenue`
  (contavam cancelados/rejeitados/por aceitar e usavam subtotal − comissão). Rótulos "N pedidos entregues".
- PROVA: Sabores total 30,28 € = `fica_para_o_parceiro` do extrato (3028 cêntimos); outra loja → `forbidden`.

### 4. A1 — aviso de pedido novo
- Edge `notify-partner` **v24** (verify_jwt=true como no ar; `config.toml` corrigido para true): iPhone passa a ALERTA com som
  (`apns-push-type: alert`, prioridade 10, `alert{title,body}`, `sound: bora_alert.wav`, time-sensitive) — antes era push "background"
  que o iOS atrasa/descarta. Android continua data-only (PADRAO §1.6), prioridade alta, ttl 600 s (era 60 s). Total/nome vêm do pedido na BD.
  Também: só pode pedir a chave de serviço, admin, o dono da loja ou o cliente desse pedido dessa loja (antes qualquer sessão avisava qualquer loja);
  aceita `customTitle/customBody` (reservas) e `restaurant_id/title/body`.
- App: o som/vibração já não pára aos 60 s — repete até não haver pedidos por aceitar (`_handleNewOrders` → stop).
- PROVA: chamada com a chave anónima → 403 `forbidden` (pg_net, id 4260). Não mandei push real a ninguém.

### 5. A2 / ALTO 3 / M1 — "Chamar estafeta" (cliente do balcão/telefone)
- RPC `partner_chamar_estafeta(loja, itens[{product_id,quantity}], nome, telefone, morada, lat, lng, notas, distancia_km)` (migration
  `20261004213500_parceiro_pausa_esgotado_feriados_chamar_estafeta.sql`, aplicada + `parceiro_chamar_estafeta_sem_colunas_geradas`).
  §2.4.1: preço de BALCÃO de cada produto (`partner_shelf_price`, senão a parte da loja do preço da app); comissão 10 % + taxa 5 % + entrega
  (`pricing_calculate`); sem markup oculto, sem saco; total pago pelo cliente em dinheiro; ganho do estafeta = pedido de parceiro normal.
  Distância do mapa presa entre a linha reta e 2,5× (sem coordenadas → 1 km). Grava restaurant_id, user_id NULL, order_type partnerRestaurant, callingDriver.
  `_store_closed_guard_orders` deixa passar este caminho (GUC `app.parceiro_chama_estafeta`) — o parceiro chama mesmo fora de horas.
- App: `OrderStore.createPartnerDeliveryRequest` chama a RPC (só ids, quantidades, morada, distância do mapa) e devolve o resumo do servidor;
  `partner_call_driver_screen.dart` mostra preço de balcão, estimativa honesta e, no fim, o total certo do servidor; erros em PT-PT.
- PROVA (desfeita): Sabores 10×1,00 € → subtotal 10,00, comissão 1,00, taxa 0,50, entrega 2,50, total 14,00, estafeta 4,00; linha gravada com
  user_id NULL, restaurant_id certo, saco 0, markup NULL, preço do item 1,00. Mr Kebab (markup próprio 15 %) 1×10,00 → mesmo 14,00 (o gatilho do markup por loja não mexe).

### 6. A3 / A4 — o parceiro nunca vê os 5 % ocultos
- `_parceiro_vendas_loja(fica, loja)`: vendas ao preço da loja = fica/0,90 (comissão 10 %), ou = fica quando a comissão é paga pelo cliente
  (`partner_commission_billing='client'` ou `app_markup_pct>0`).
- `extrato_parceiro`, `partner_my_weekly_closeout` (semana em curso + histórico) e `partner_monthly_statement` (também usado pela Edge
  monthly-partner-statement) passam a mostrar vendas ao preço da loja e comissão 10 %; "entrega e taxas" = as taxas reais (entrega+serviço+saco+pedido pequeno).
  O que fica para a loja não mudou (mesma fonte do ledger).
- `partner_earnings_screen.dart`: saiu a linha "O cliente pagou", rótulos "Vendas (preço da loja)" e "Comissão Bora".
- A4: RPC `partner_loja_recebe(ids[])`; o cartão do pedido mostra "Recebes €X" (antes mostrava o total do cliente com o markup); histórico idem.
- PROVA: pedido real da Sabores 85e0d837: vendas 33,64 €, comissão 3,36 € (10,0 %), fica 30,28 €, taxas 4,69 €; mensal set/2026 = 33,64/3,36/30,28;
  `partner_loja_recebe` com ids da Goola e da Sabores devolve só os da Sabores.

### 7. A5 — pausa e tempo de preparação
- `restaurants.pausa_ate timestamptz` (pedido do checkout e do cliente-app — nome/tipo iguais). RPC `partner_pausar_loja(loja, minutos)`:
  15/30/60, `-1` = até à hora de fecho de hoje (is_partner_open), `0` = retomar. Volta sozinha (a comparação é com now()).
  Dashboard: cartão "Muito trabalho? Pausa a loja" / "Loja em pausa — volta às HH:MM (Lisboa) · Retomar".
- RPC `partner_aceitar_pedido(pedido, minutos 5–120)` = `partner_accept_order` + grava `prep_time_minutes`. Ao aceitar um pedido normal abre
  "fica pronto em quanto tempo?" (10–60 min, padrão = tempo padrão da loja).
- Removido o temporizador da app que chamava o estafeta sozinho aos 5 min (`_schedulePartnerPreparationTimer`); fica o botão "Chamar estafeta já".
- PROVA (desfeita): pausa 30 → volta 22:19; até fechar → 22:00; loja alheia → forbidden; aceitar com 200 → `invalid_prep_minutes`;
  com 20 → status preparing, prep 20, accepted_at preenchido.

### 8. Esgotado e dias fechados
- `products.esgotado_ate` + RPC `partner_produto_esgotado(produto, 'ate_amanha'|'sem_data'|'disponivel')` + cron `produtos-esgotados-voltam`
  (*/10, função `produtos_esgotados_voltam()`). Ecrã de produtos: desligar pergunta "Esgotado só hoje" / "até eu voltar a ligar"; rótulo "Esgotado".
- Dias fechados: RPC `partner_dias_fechados(loja, datas[])` (business_hours.special_dates `{date, closed:true}`, que o `is_partner_open` e a
  guarda de horário já respeitam; dias especiais do admin com horário ficam). `partner_guardar_horario` grava o horário SEM apagar os
  special_dates (antes o ecrã de horário do parceiro apagava-os). Ecrã de horários: secção "Dias fechados (feriados, férias)".
- PROVA: esgotado até 2026-10-04T23:00Z (meia-noite de Lisboa); feriado 25/12 gravado, data passada ignorada, horário guardado mantém-no;
  `is_partner_open(...,'2026-12-25 15:00')` → fechado.
- Promoções próprias / relatórios: não feitos (ver NÃO FEITO). Responder a avaliações: restaurantes já tinham (`restaurant_respond_to_rating`);
  barbearias: RPC nova `prestador_responder_avaliacao` (sem ecrã).

### 9. M4 — fuso das reservas
- `partner_reservas_store.dart`: "hoje"/"histórico" com meia-noite de Lisboa em UTC (`inicioDiaLisboaUtc`, novo em `lib/utils/hora_lisboa.dart`),
  restantes instantes em UTC. Ecrã de reservas, agenda e financeiro das marcações, horas de pico e datas do extrato: `horaLisboa(...)` em vez de `toLocal()`.

### 10. #5 avaliação das barbearias
- Não havia forma nenhuma de avaliar marcações (e `ratings.subject_type` tem CHECK que não aceita prestadores — trocá-lo exige DROP).
  Tabela nova `appointment_ratings` (1 por marcação, RLS: leitura pública das não sinalizadas, admin tudo; escrita só por RPC),
  RPC `avaliar_marcacao(marcação, estrelas, comentário)` (só o cliente da marcação, só `completed`), gatilho `trg_appointment_ratings_provider_avg`
  → `service_providers.avg_rating/ratings_count`.
- PROVA (desfeita): cliente da marcação dá 4★ → prestador avg 4.00, n=1; outro utilizador → `marcacao_nao_encontrada`.

### 11. upload-restaurant-asset v7 (verify_jwt=true como no ar)
- Pasta de loja/prestador existente → só o dono (user_id/user_) ou admin/chave de serviço; registo novo (`temp-…`) → a pasta é gerada no
  servidor (`temp-<uuid>`), nunca a que o telemóvel manda; outros ids → 403. Também: tamanho máx. 8 MB, só imagens/PDF, sem SVG.
  Mantidos os usos existentes (logo/cover/owner_doc/activity_doc do registo, hero/logo/gallery/photo/staff_photo do admin e da equipa).
- PROVA: chave anónima para a pasta da Goola → 401 "Sessão necessária" (pg_net, id 4256).

### 12. Textos e cuidados
- "Aguardando estafeta..." → "À procura de estafeta...", "Chamando estafeta..." → "A chamar estafeta...", "turn time" → "ocupada N min",
  Indique/Selecione/Escolha/Insira/Prepare/Atualize → tu (call driver, add_product, register_partner, dashboard), "endereço" → "morada",
  erro cru do registo → frase simples. `if (!mounted)` em 6 sítios depois de pickers (pacing, walk-in, bloquear, equipa).

## NÃO FEITO
- Apagar `lib/screens/restaurant_dashboard_screen.dart` e `lib/screens/partner_reservations_screen.dart`: 0 usos confirmados (git grep em lib/ e test/),
  mas o `git rm` foi BLOQUEADO pelo classificador de permissões ("destruição local irreversível"). Ficam no ramo; ver PRECISA DE CONFIRMAÇÃO.
- Promoções próprias do parceiro e relatórios: não são pequenos (precisam de tabela de promoções ligada ao create_order/quote — zona do checkout).
- Ecrã para o cliente avaliar a marcação e para a barbearia responder (RPCs prontas) — ver PEDIDOS.

## PRECISA DE CONFIRMAÇÃO
- Apagar os ecrãs mortos: `git rm lib/screens/restaurant_dashboard_screen.dart lib/screens/partner_reservations_screen.dart` (0 usos).

## PEDIDOS A OUTROS AGENTES
- PEDIDO A cliente-app: (a) `RestaurantModel.isOpenNow()/statusLabel()` não lê `business_hours.special_dates` — num feriado marcado pelo parceiro a
  loja aparece aberta e só o servidor recusa (STORE_CLOSED); ler `special_dates` (entrada com `closed:true` = fechada o dia todo).
  (b) Em "As minhas marcações" (concluídas): botão "Avaliar" → `rpc('avaliar_marcacao', {p_appointment_id, p_stars, p_comment})`; mostrar
  `service_providers.avg_rating/ratings_count`. `restaurants.pausa_ate` criada com o nome/tipo pedidos.
- PEDIDO A admin-geral: no detalhe do parceiro mostrar/limpar `pausa_ate`, ver produtos `esgotado_ate`, dias fechados (special_dates já tem
  `admin_set_partner_special_date`) e as avaliações das barbearias (`appointment_ratings`, sinalizar via `flagged_inappropriate`).
- PEDIDO A dinheiro-entregas/admin-dinheiro: pedidos "parceiro chama estafeta" (user_id NULL, order_type partnerRestaurant) — no fecho,
  `post_order_to_ledger`/`apply_order_financial_split` creditam à loja `partner_store_share(subtotal)` (85,7 %), mas aqui o subtotal JÁ é o
  preço de balcão e a loja fica com o subtotal inteiro, recebendo o total em dinheiro do estafeta (deve à Bora comissão+taxa+entrega).
  O caminho nunca foi usado em produção (0 pedidos), mas tem de ser tratado antes de um parceiro o usar a sério.
- PEDIDO A quem for dono de `_notify_partner_status_change`: chama notify-partner com a chave ANÓNIMA e `restaurant_id` — já falhava
  (400) e agora dá 403; passar a usar a chave de serviço do cofre (como `_reservas_pro_notify_partner_push`).
- PEDIDO A despacho: nada novo — o `prep_time_minutes` passa a ser gravado ao aceitar (5–120 min).

## RISCOS
- Ficou no GitHub o ramo de comparação `analise-parceiro-base` (só base + workflow; não publica). Pode ser apagado.
- iPhone: com o alerta do sistema e a notificação local da app em primeiro plano pode aparecer o aviso duas vezes (preferível a nenhum).
- O som do parceiro já não pára sozinho: se um pedido ficar "created" sem nunca mudar (bug noutra parte), toca até alguém agir.
- A guarda C1 recusa com erro (não ignora): uma versão antiga da app que tentasse gravar um destes campos passa a ver erro — nenhuma o faz hoje.
- `orders_insert_partner` fechado: versões antigas da app do parceiro deixam de conseguir "Chamar estafeta" até atualizarem (nunca usado: 0 pedidos).
