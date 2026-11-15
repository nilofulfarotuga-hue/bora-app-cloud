-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115150004); antes não estava em supabase/migrations.
-- No servidor, statements guardou um carregador (copiado abaixo, comentado) que: 1) guardou a definição antiga de
-- admin_soft_delete_driver na tabela bkp_fn_admin_soft_delete_driver_20261115; 2) executou a cópia de
-- docs/propostas/painel-admin-15-11/P5_estafeta_admin.PROPOSTA.sql (commit 540d0253; net._http_response 157769;
-- sha256 b911b042898446e0095f32ded71674da70f40b5fd6f9e0f45ab85d6ea598f919) SEM a parte P5.3 (admin_revogar_sessoes)
-- e com o motivo mínimo de 10 letras em vez de 3 na P5.4; 3) ligou RLS na tabela de cópia.
-- Abaixo vem exatamente isso, pela mesma ordem.
--
-- >>> carregador gravado em schema_migrations.statements (versão 20261115150004):
-- do $$
-- declare
--   v_sql text;
--   p3 int;
--   p4 int;
-- begin
--   select content into v_sql from net._http_response where id = 157769;
--   if v_sql is null or encode(sha256(convert_to(v_sql,'UTF8')),'hex') <> 'b911b042898446e0095f32ded71674da70f40b5fd6f9e0f45ab85d6ea598f919' then
--     raise exception 'sha256 nao confere ou resposta vazia';
--   end if;
--   create table if not exists public.bkp_fn_admin_soft_delete_driver_20261115 as
--     select now() as guardado_em, pg_get_functiondef('public.admin_soft_delete_driver(uuid,text)'::regprocedure) as def;
--   -- tirar a P5.3 (apagar sessoes no auth por SQL fica de fora)
--   p3 := position(E'\n-- P5.3  admin_revogar_sessoes' in v_sql);
--   p4 := position(E'\n-- P5.4  admin_soft_delete_driver' in v_sql);
--   if p3 = 0 or p4 = 0 or p4 < p3 then raise exception 'marcadores P5.3/P5.4 nao encontrados'; end if;
--   v_sql := substr(v_sql, 1, p3) || substr(v_sql, p4 + 1);
--   if v_sql ilike '%delete from auth%' then raise exception 'ainda ha delete no auth'; end if;
--   -- P5.4: motivo minimo 10 letras, igual ao gatilho trg_suspensao_so_com_humano
--   v_sql := replace(v_sql, 'length(trim(p_reason)) < 3 THEN', 'length(trim(p_reason)) < 10 THEN');
--   v_sql := replace(v_sql, '(min 3 chars)', '(min 10 chars)');
--   execute v_sql;
-- end $$;
-- alter table public.bkp_fn_admin_soft_delete_driver_20261115 enable row level security;
-- <<< fim do carregador; a seguir, o que ele executou.

create table if not exists public.bkp_fn_admin_soft_delete_driver_20261115 as
  select now() as guardado_em, pg_get_functiondef('public.admin_soft_delete_driver(uuid,text)'::regprocedure) as def;

-- PROPOSTA P5 (missão painel-admin-15-11, 15/11/2026, Claude Code, agente backend-supabase).
-- Aplica a Claude.ai com execute_sql, UMA PARTE DE CADA VEZ e pela ordem. NADA disto foi aplicado.
-- Tudo foi lido em produção só com SELECT a 15/11/2026 (pg_get_functiondef, pg_trigger, pg_constraint,
-- information_schema, pg_roles, cron.job) e no código da app (lib/).
--
-- Área do estafeta no painel: as funções que faltam para o painel fazer POR ELE o que hoje só a app
-- dele faz (AUDITORIA.md, "Área do estafeta e Área do parceiro").
--
--   P5.1  admin_set_driver_online      ligar / desligar o estafeta por ele   sensível (presença)
--   P5.2  admin_estafeta_avancar       "recolhido" / "a caminho" por ele     PRECISA DE ORDEM EXPLÍCITA DO DANILO
--   P5.3  admin_revogar_sessoes        o "Sair" a sério (com a Edge nova)     sensível (sessões de login)
--   P5.4  admin_soft_delete_driver     as 3 guardas pelos dois ids           PRECISA DE ORDEM EXPLÍCITA DO DANILO
--   P5.5  admin_update_driver          nada aqui: o apagar da de 8 está no P1 + ficheiro de documentação
--   P5.6  admin_fatura_mes_estafeta    fatura do mês do estafeta, só leitura
--
-- Regras de todas: SECURITY DEFINER, search_path 'public', fechadas a PUBLIC e anon, abertas a
-- authenticated (a P5.3 só ao service_role). Porteiro: public.is_admin() (o mesmo das 266 regras de
-- acesso); a P5.4 mantém o dela (_admin_op_guard, ver P3). Nenhuma chama o dispatch-engine nem mexe em
-- preços, carteiras, ledger ou tokens.
-- Identidade (skill identidade-estafeta): user_id manda. 15 dos 19 estafetas ativos têm drivers.id
-- diferente de user_id (contado a 15/11); pedidos (assigned_driver_id), saldos e acertos estão quase
-- todos pelo user_id. Por isso tudo aceita os dois ids e procura pelos dois.
--
-- Impressões digitais do que estas propostas copiam (se mudarem antes de aplicar, reler e rever):
--   select p.oid::regprocedure, md5(pg_get_functiondef(p.oid)) from pg_proc p
--    where p.oid in ('public.driver_advance_order(text,text)'::regprocedure,
--                    'public.prestador_pode_ficar_online()'::regprocedure,
--                    'public.fn_prestador_online_so_aprovado()'::regprocedure,
--                    'public.driver_monthly_invoice_summary(integer,integer)'::regprocedure,
--                    'public.admin_soft_delete_driver(uuid,text)'::regprocedure);
--   15/11/2026: driver_advance_order 5cc6eca6362f4b006fbcee68ee469e96 · prestador_pode_ficar_online
--   8852d09ebed5da730a67e2ad7e890b2c · fn_prestador_online_so_aprovado a2d84d11c0ed4d32751a469bf8bff588 ·
--   driver_monthly_invoice_summary 043a91c9c80aa6f2a6d57750e58d1731 · admin_soft_delete_driver
--   e0050c31fdac84c93a52405ac2d5af71.


-- =====================================================================================================
-- P5.1  admin_set_driver_online(p_driver text, p_online boolean, p_motivo text) -> jsonb
-- Sensível: decide quem recebe ofertas do despacho. Não mexe em pedidos, no motor nem em dinheiro.
-- =====================================================================================================
-- O PROBLEMA: o painel não consegue ligar nem desligar um estafeta. Quando a app e o servidor
--   discordam (a app mostra "Online" e o servidor pô-lo offline, ou ao contrário) a equipa não tem
--   botão; a única saída seria um UPDATE à mão em drivers, que é proibido.
-- O QUE A APP FAZ (código lido a 15/11):
--   * Offline: DriverStore.alternarOnline (lib/stores/driver_store.dart 386-393) muda já no telemóvel e
--     grava drivers.is_online=false por user_id (_gravarOnlineNoServidor, 686-694); pára o serviço de
--     fundo e os batimentos; ao sair da conta DriverLocationPingService.goOffline() manda
--     driver_update_location(p_is_online=false), que põe driver_locations.is_online=false na linha do
--     user_id. A app não deixa desligar com pedidos em curso.
--   * Online: pergunta prestador_pode_ficar_online() e só depois grava is_online=true, confirmando
--     pela linha devolvida (o gatilho pode deixá-lo offline sem erro).
-- GATILHOS EM drivers.is_online (pg_trigger, 15/11) — correm igual para a app e para esta função:
--   trg_online_so_aprovado (fn_prestador_online_so_aprovado): recusa conta por aprovar, recusada,
--     bloqueada ou apagada (CONTA_*).
--   trg_motorista_doc_expirado_online: recusa TVDE com documento expirado (DOCUMENTO_EXPIRADO).
--   trg_tvde_conformidade_online: recusa TVDE sem conformidade ou no limite de horas (TVDE_BLOQUEADO,
--     LIMITE_HORAS), só com tvde_compliance_enforce ligado.
--   trg_driver_online_sem_push: avisa a equipa se liga sem notificações (não recusa).
--   trg_sync_drivers_to_driver_locations: espelha is_online na linha de driver_locations do drivers.id.
--   trg_tvde_work_log_online: abre / fecha o registo de horas TVDE.
--   Nenhum gatilho mexe em pedidos ou ofertas ao desligar. fn_conformidade_antes_de_ativar só corre
--   quando muda approval_status (a aprovação), não quando liga. O relógio expire_stale_driver_presence
--   põe offline quem não bate há mais de dispatch_heartbeat_offline_seconds (90 s), e a app só bate e
--   manda posição enquanto está em Online.
-- O QUE MUDA:
--   * DESLIGAR: deixa sempre (também com pedidos em curso: avisa quantos; continuam com ele, e para os
--     passar usa-se ops_reassign_order). Faz no servidor o mesmo que o botão Offline: is_online=false
--     (os gatilhos fecham o registo TVDE e espelham a linha do drivers.id) e driver_locations.is_online
--     =false também na linha do user_id, sem renovar a data do GPS (igual ao gatilho, A10). Não pára o
--     serviço de fundo do telemóvel: se a app ainda estiver em Online, as posições que ela manda já não
--     o religam (driver_update_location nunca põe is_online=true).
--   * LIGAR: só se (1) a conta passa as mesmas regras da app (prestador_pode_ficar_online, pela mesma
--     ordem: apagada, bloqueada, recusada, por aprovar) e (2) o telemóvel deu sinal (batimento ou
--     posição) nos últimos 2 minutos; sem sinal recusa com "o celular não está com ele". Depois faz o
--     MESMO UPDATE que a app; os gatilhos são o travão final (TVDE, documento expirado) e o motivo deles
--     volta na resposta. Confirma lendo a linha. Como a app em Offline não bate, ligar por ele só passa
--     quando a app dele ainda está a correr em Online (o caso "a app diz online e o servidor não").
--     Não chama o dispatch-engine (zona protegida): o lote-15s-despacho (bora_dispatch_maintenance, de
--     15 em 15 s, conferido em cron.job) oferece-lhe os pedidos à espera na volta seguinte.
--   * Audita com log_admin_action('driver_set_online', 'driver', drivers.id,
--     {user_id, antes, depois, motivo}) sempre que grava alguma coisa.

create or replace function public.admin_set_driver_online(p_driver text, p_online boolean, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_chave     text := lower(btrim(coalesce(p_driver, '')));
  v_d         public.drivers%rowtype;
  v_antes     boolean;
  v_depois    boolean;
  v_sinal     timestamptz;
  v_em_curso  integer := 0;
  v_codigo    text;
  v_msg       text;
  v_dica      text;
  v_push      boolean;
  v_hb_off    integer;
  v_avisos    text[] := '{}';
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required: só um admin pode ligar ou desligar um entregador' using errcode = '42501';
  end if;
  if p_online is null then
    return jsonb_build_object('ok', false, 'error', 'online_obrigatorio',
      'mensagem', 'Diga se é para ligar (true) ou desligar (false).');
  end if;
  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'motivo_curto',
      'mensagem', 'Escreva o motivo (mínimo 3 letras).');
  end if;

  -- Aceita drivers.id ou user_id (user_id é único e nunca nulo, conferido a 15/11).
  select d.* into v_d
    from public.drivers d
   where d.id::text = v_chave or d.user_id::text = v_chave
   order by (d.user_id::text = v_chave) desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'driver_not_found',
      'mensagem', 'Entregador não encontrado. Atualize a lista.');
  end if;
  v_antes := coalesce(v_d.is_online, false);

  ------------------------------------------------------------------ DESLIGAR (sempre permitido)
  if not p_online then
    update public.drivers set is_online = false where id = v_d.id;
    -- A app espelha a linha do user_id (goOffline); o gatilho espelha a do drivers.id. Faz-se as duas,
    -- sem tocar em last_updated (a data do GPS).
    update public.driver_locations
       set is_online = false
     where driver_id in (v_d.id, v_d.user_id)
       and is_online;
    select count(*) into v_em_curso
      from public.orders o
     where o.assigned_driver_id in (v_d.id::text, v_d.user_id::text)
       and o.status in ('driverAccepted', 'pickedUp', 'onTheWay');
    if v_em_curso > 0 then
      v_avisos := array_append(v_avisos, format(
        'Ele tem %s pedido(s) em andamento: continuam com ele. Para passar para outro entregador use "Passar pedido" (ops_reassign_order).',
        v_em_curso));
    end if;
    perform public.log_admin_action('driver_set_online', 'driver', v_d.id::text,
      jsonb_build_object('user_id', v_d.user_id, 'antes', v_antes, 'depois', false,
                         'motivo', btrim(p_motivo), 'pedidos_em_curso', v_em_curso));
    return jsonb_build_object('ok', true, 'driver_id', v_d.id, 'user_id', v_d.user_id,
      'antes', v_antes, 'depois', false, 'pedidos_em_curso', v_em_curso,
      'avisos', to_jsonb(v_avisos));
  end if;

  ------------------------------------------------------------------ LIGAR
  if v_antes then
    return jsonb_build_object('ok', true, 'driver_id', v_d.id, 'user_id', v_d.user_id,
      'antes', true, 'depois', true, 'nada_mudou', true,
      'mensagem', 'Ele já estava online no servidor.');
  end if;

  -- (1) As mesmas regras da app, pela ordem de prestador_pode_ficar_online (lida a 15/11).
  v_codigo := case
    when v_d.deleted_at is not null                    then 'CONTA_APAGADA'
    when coalesce(v_d.is_banned, false)                then 'CONTA_BLOQUEADA'
    when coalesce(v_d.approval_status, '') = 'rejected' then 'CONTA_RECUSADA'
    when coalesce(v_d.approval_status, '') <> 'approved' then 'CONTA_NAO_APROVADA'
  end;
  if v_codigo is not null then
    return jsonb_build_object('ok', false, 'error', v_codigo,
      'driver_id', v_d.id, 'user_id', v_d.user_id,
      'mensagem', case v_codigo
        when 'CONTA_APAGADA'   then 'A conta dele foi removida. Reative primeiro.'
        when 'CONTA_BLOQUEADA' then 'A conta dele está suspensa ou banida. Reative primeiro.'
        when 'CONTA_RECUSADA'  then 'A candidatura dele foi recusada.'
        else 'A conta dele ainda não está aprovada (veja em "faltas" o que falta enviar).' end,
      'faltas', case when v_codigo = 'CONTA_NAO_APROVADA'
                     then to_jsonb(public._robo_documentos_faltas(v_d.user_id)) end);
  end if;

  -- (2) O celular tem de estar com ele: batimento ou posição nos últimos 2 minutos.
  v_sinal := greatest(coalesce(v_d.last_heartbeat_at, '-infinity'::timestamptz),
                      coalesce(public.driver_gps_last_at(v_d.user_id, v_d.id), '-infinity'::timestamptz));
  if v_sinal < now() - interval '2 minutes' then
    return jsonb_build_object('ok', false, 'error', 'SEM_SINAL',
      'driver_id', v_d.id, 'user_id', v_d.user_id,
      'ultimo_sinal', case when v_sinal = '-infinity'::timestamptz then null else v_sinal end,
      'mensagem', 'O celular dele não deu sinal nos últimos 2 minutos'
        || case when v_sinal = '-infinity'::timestamptz then ' (nunca deu sinal)'
                else ' (último sinal ' || to_char(v_sinal at time zone 'Europe/Lisbon', 'DD/MM HH24:MI') || ')' end
        || '. O celular não está com ele ou a app está fechada: peça para ele abrir a Bora e tocar em Online.');
  end if;

  -- (3) O MESMO UPDATE da app. Os gatilhos são o travão final; o motivo deles volta na resposta.
  begin
    update public.drivers set is_online = true where id = v_d.id
    returning is_online into v_depois;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v_msg = message_text, v_dica = pg_exception_hint;
    v_codigo := split_part(v_msg, ':', 1);
    if coalesce(v_codigo, '') not in ('CONTA_APAGADA', 'CONTA_BLOQUEADA', 'CONTA_RECUSADA',
        'CONTA_NAO_APROVADA', 'DOCUMENTO_EXPIRADO', 'TVDE_BLOQUEADO', 'LIMITE_HORAS') then
      raise;
    end if;
    return jsonb_build_object('ok', false, 'error', v_codigo,
      'driver_id', v_d.id, 'user_id', v_d.user_id,
      'mensagem', 'O servidor recusou: ' || btrim(substr(v_msg, length(v_codigo) + 2)),
      'dica', v_dica);
  end;
  if not coalesce(v_depois, false) then
    return jsonb_build_object('ok', false, 'error', 'NAO_CONFIRMADO',
      'driver_id', v_d.id, 'user_id', v_d.user_id,
      'mensagem', 'O servidor não confirmou: ele continua offline.');
  end if;

  -- Avisos (não recusam).
  select r.tem_notificacoes into v_push from public._driver_reachability(v_d.id::text) r;
  if not coalesce(v_push, false) then
    v_avisos := array_append(v_avisos,
      'Ficou online, mas sem notificações ativas: não recebe pedidos até ativar as notificações na app.');
  end if;
  v_hb_off := coalesce((public.get_setting('dispatch_heartbeat_offline_seconds') #>> '{}')::int, 90);
  if v_d.last_heartbeat_at is null or v_d.last_heartbeat_at < now() - make_interval(secs => v_hb_off) then
    v_avisos := array_append(v_avisos, format(
      'O último batimento da app tem mais de %s s: se a app não bater de novo já, o servidor volta a deixá-lo offline.',
      v_hb_off));
  end if;

  perform public.log_admin_action('driver_set_online', 'driver', v_d.id::text,
    jsonb_build_object('user_id', v_d.user_id, 'antes', v_antes, 'depois', true,
                       'motivo', btrim(p_motivo), 'ultimo_sinal', v_sinal));
  return jsonb_build_object('ok', true, 'driver_id', v_d.id, 'user_id', v_d.user_id,
    'antes', v_antes, 'depois', true, 'ultimo_sinal', v_sinal,
    'mensagem', 'Ele está online. O despacho oferece os pedidos em espera na próxima volta (até 15 s).',
    'avisos', to_jsonb(v_avisos));
end
$function$;

revoke all on function public.admin_set_driver_online(text, boolean, text) from public, anon;
grant execute on function public.admin_set_driver_online(text, boolean, text) to authenticated;

-- PROVA P5.1 (depois de aplicar):
--   select p.prosecdef, p.proconfig, p.proacl from pg_proc p
--    where p.oid = 'public.admin_set_driver_online(text,boolean,text)'::regprocedure;
--     -- true | {search_path=public} | {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   Ensaio numa transação desfeita (nada fica gravado), com o uid de um admin e um estafeta de TESTE:
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uid_de_um_admin>","role":"authenticated"}', true);
--     set local role authenticated;
--     select public.admin_set_driver_online('<drivers.id ou user_id>', false, 'prova em rollback');
--       -- ok=true, depois=false
--     select public.admin_set_driver_online('<o mesmo>', true, 'prova em rollback');
--       -- com a app fechada: ok=false, error=SEM_SINAL
--     select action, details from public.admin_audit_log where action = 'driver_set_online'
--      order by created_at desc limit 1;                       -- {user_id, antes, depois:false, motivo}
--   rollback;
--   Com claims de um uid que não é admin: erro admin_required.


-- =====================================================================================================
-- P5.2  admin_estafeta_avancar(p_order_id text, p_status text, p_motivo text) -> jsonb
-- PRECISA DE ORDEM EXPLÍCITA DO DANILO: mexe no andamento do pedido (zona de pedidos / dispatch).
-- =====================================================================================================
-- O PROBLEMA: quando o estafeta recolhe o pedido e a app dele não consegue marcar "recolhido" ou
--   "a caminho" (sem rede, app presa), o pedido fica parado no painel e o cliente não é avisado. A
--   equipa não tem botão; um UPDATE à mão em orders é proibido.
-- A FUNÇÃO DO ESTAFETA é driver_advance_order(p_order_id, p_target_status) (lida a 15/11, md5 acima).
--   Ela usa auth.uid() para "o pedido é meu", por isso o admin não a pode chamar por ele. Esta versão
--   repete AS MESMAS verificações, pela mesma ordem, e o MESMO UPDATE:
--     só 'pickedUp' e 'onTheWay'; pedido preso com FOR UPDATE; já está à frente = ok (idempotente);
--     pickedUp só a partir de driverAccepted e onTheWay só a partir de pickedUp; UPDATE ... WHERE
--     status = o esperado (se outro mudou entretanto: concurrent_transition);
--     driver_id = coalesce(driver_id, user_id do estafeta).
--   O que muda: "o pedido é meu" passa a "o pedido tem estafeta e ele existe" (assigned_driver_id pelos
--   dois ids); o porteiro é is_admin(); pede motivo; app.order_transition_source =
--   'admin_estafeta_avancar' (fica em order_status_events.source, com actor_uid = o admin; o gatilho
--   zzz_audit_driver_assignment vê a origem e não o trata como ligação SQL direta). Os erros de
--   verificação dos gatilhos (23514) voltam como resposta clara em vez de rebentar.
--   Todos os gatilhos de orders correm igual ao do estafeta: aviso ao cliente da fase, fila, registo do
--   estado, e a recusa de "recolhido" em compra de loja não parceira sem talão fechado
--   (enforce_storeshopping_finalize_before_pickup).
-- ATENÇÃO DINHEIRO: no "recolhido" de um pedido "pagar na loja" pago em dinheiro, o gatilho
--   _orders_loja_pagamento marca is_purchase_finalized=true e final_purchase_value = o valor a pagar à
--   loja (é o registo de que o estafeta pagou à loja na recolha; conta no acerto dele e no fecho da
--   loja). Pelo admin acontece o mesmo: só usar quando se sabe que ele recolheu e pagou.
--   Não há "entregue" aqui: o delivered continua só pelas funções que já existem.

create or replace function public.admin_estafeta_avancar(p_order_id text, p_status text, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_order      public.orders%rowtype;
  v_expected   text;
  v_driver_uid uuid;
  v_rows       integer := 0;
  v_msg        text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required: só um admin pode avançar um pedido pelo entregador' using errcode = '42501';
  end if;
  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'motivo_curto',
      'mensagem', 'Escreva o motivo (mínimo 3 letras).');
  end if;

  -- Daqui para baixo: as verificações de driver_advance_order, pela mesma ordem.
  if coalesce(p_status, '') not in ('pickedUp', 'onTheWay') then
    return jsonb_build_object('ok', false, 'error', 'target_not_allowed',
      'mensagem', 'Só dá para avançar para pickedUp (recolhido) ou onTheWay (a caminho).');
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found', 'mensagem', 'Pedido não encontrado.');
  end if;

  -- Em vez de "o pedido é meu": o pedido tem de ter estafeta, e ele tem de existir.
  if v_order.assigned_driver_id is null then
    return jsonb_build_object('ok', false, 'error', 'sem_estafeta', 'status', v_order.status,
      'mensagem', 'Este pedido não tem entregador. Para dar um, use "Passar pedido" (ops_reassign_order).');
  end if;
  select coalesce(d.user_id, d.id) into v_driver_uid
    from public.drivers d
   where d.user_id::text = v_order.assigned_driver_id or d.id::text = v_order.assigned_driver_id
   order by (d.user_id::text = v_order.assigned_driver_id) desc
   limit 1;
  if v_driver_uid is null then
    return jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado', 'status', v_order.status,
      'mensagem', 'O entregador deste pedido não está na lista de entregadores. Chame a equipe técnica.');
  end if;

  if (p_status = 'pickedUp' and v_order.status in ('pickedUp', 'onTheWay', 'delivered'))
     or (p_status = 'onTheWay' and v_order.status in ('onTheWay', 'delivered')) then
    return jsonb_build_object('ok', true, 'status', v_order.status, 'idempotent', true);
  end if;
  v_expected := case p_status
    when 'pickedUp' then 'driverAccepted'
    when 'onTheWay' then 'pickedUp'
  end;
  if v_order.status <> v_expected then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'status', v_order.status,
      'mensagem', format('O pedido está em "%s"; para ir para "%s" tem que estar em "%s".',
                         v_order.status, p_status, v_expected));
  end if;

  perform set_config('app.order_transition_source', 'admin_estafeta_avancar', true);
  begin
    update public.orders
       set status = p_status,
           driver_id = coalesce(driver_id, v_driver_uid)
     where id = p_order_id and status = v_expected;
    get diagnostics v_rows = row_count;
  exception when check_violation then
    get stacked diagnostics v_msg = message_text;
    return jsonb_build_object('ok', false, 'error', split_part(v_msg, ':', 1), 'status', v_order.status,
      'mensagem', case when v_msg like 'finalize_purchase_before_pickup%'
                       then 'A compra ainda não foi fechada (talão): o entregador tem que finalizar a compra na app antes de recolher.'
                       else v_msg end);
  end;
  if v_rows <> 1 then
    return jsonb_build_object('ok', false, 'error', 'concurrent_transition',
      'mensagem', 'O pedido mudou nesse meio tempo. Atualize e tente de novo.');
  end if;

  perform public.log_admin_action('order_estafeta_avancar', 'order', p_order_id,
    jsonb_build_object('de', v_expected, 'para', p_status, 'motivo', btrim(p_motivo),
                       'estafeta_user_id', v_driver_uid,
                       'assigned_driver_id', v_order.assigned_driver_id));
  return jsonb_build_object('ok', true, 'status', p_status, 'de', v_expected);
end
$function$;

revoke all on function public.admin_estafeta_avancar(text, text, text) from public, anon;
grant execute on function public.admin_estafeta_avancar(text, text, text) to authenticated;

-- PROVA P5.2 (só com a ordem do Danilo; num pedido de TESTE, de cliente demo, em driverAccepted, numa
-- transação desfeita):
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uid_de_um_admin>","role":"authenticated"}', true);
--     select public.admin_estafeta_avancar('<pedido_teste>', 'onTheWay', 'prova');  -- ok=false, invalid_status
--     select public.admin_estafeta_avancar('<pedido_teste>', 'pickedUp', 'prova');  -- ok=true, de=driverAccepted
--     select public.admin_estafeta_avancar('<pedido_teste>', 'pickedUp', 'prova');  -- ok=true, idempotent=true
--     select to_status, source, actor_uid from public.order_status_events
--      where order_id = '<pedido_teste>' order by id desc limit 1;  -- pickedUp | admin_estafeta_avancar | <uid_de_um_admin>
--   rollback;
--   Comparar lado a lado com a do estafeta:
--     select pg_get_functiondef('public.driver_advance_order(text,text)'::regprocedure);


-- =====================================================================================================
-- P5.4  admin_soft_delete_driver(p_driver_id uuid, p_reason text) -> jsonb   (reescrita)
-- PRECISA DE ORDEM EXPLÍCITA DO DANILO: guarda de dinheiro (saldo, acertos) e de pedidos em curso.
-- =====================================================================================================
-- O PROBLEMA: as 3 guardas (pedido em curso, saldo diferente de zero, acertos pendentes) procuram só pelo
--   drivers.id; pedidos, driver_balances e driver_transactions estão pelo user_id (o login). Hoje (15/11,
--   só leitura) há 3 estafetas ativos com saldo diferente de zero guardado pelo user_id que a guarda
--   velha não vê: podiam ser removidos por engano com dinheiro por acertar. Pedidos em curso e acertos
--   pendentes escondidos: 0 casos hoje. (No máximo 1 linha de saldo por estafeta, conferido.)
-- O QUE MUDA: só as 3 guardas, que passam a olhar para os dois ids, como admin_suspender_prestador
--   (o.assigned_driver_id IN (id, user_id)). Tudo o resto fica igual, letra a letra, incluindo as
--   mensagens "Cannot delete: ..." que o painel traduz (lib/services/admin/admin_driver_service.dart,
--   _parsePgError) e o porteiro _admin_op_guard. O saldo soma as linhas dos dois ids e recusa se
--   alguma for diferente de zero. A auditoria passa a guardar também o user_id.
-- ERRO ENCONTRADO PELO CAMINHO (não mexido aqui, fica reportado): esta função aceita motivo com 3
--   letras, mas o gatilho trg_suspensao_so_com_humano (deleted_at passa a preenchido = "encerramento")
--   exige 10 letras e recusa com SUSPENSAO_SEM_MOTIVO. Remover com motivo de 3 a 9 letras falha sempre;
--   o painel deve pedir 10 letras.

create or replace function public.admin_soft_delete_driver(p_driver_id uuid, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_admin           RECORD;
  v_driver          RECORD;
  v_active_orders   INTEGER;
  v_balance         NUMERIC(10,2);
  v_balance_rows    INTEGER;
  v_pending_settle  INTEGER;
  v_prev_status     TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'reason_required: soft delete needs a reason (min 10 chars)'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;
  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_already_deleted: % (reactivate first if needed)',
      p_driver_id USING ERRCODE = '23514';
  END IF;

  -- 15/11/2026: as 3 guardas olham para os DOIS ids do estafeta (drivers.id e user_id), como
  -- admin_suspender_prestador. Pedidos, saldo e acertos estão pelo user_id (o login).
  SELECT COUNT(*) INTO v_active_orders
  FROM public.orders
  WHERE assigned_driver_id IN (p_driver_id::text, v_driver.user_id::text)
    AND status NOT IN ('delivered', 'cancelled', 'rejected');
  IF v_active_orders > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % active order(s)', v_active_orders
      USING ERRCODE = '23514';
  END IF;

  SELECT SUM(balance), COUNT(*) FILTER (WHERE balance <> 0)
    INTO v_balance, v_balance_rows
  FROM public.driver_balances WHERE driver_id IN (p_driver_id, v_driver.user_id);
  IF v_balance_rows > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has non-zero balance of EUR %',
      to_char(COALESCE(v_balance, 0), 'FM999990.00') USING ERRCODE = '23514';
  END IF;

  SELECT COUNT(*) INTO v_pending_settle
  FROM public.driver_transactions
  WHERE driver_id IN (p_driver_id, v_driver.user_id) AND status = 'pending';
  IF v_pending_settle > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % pending cash settlement(s)',
      v_pending_settle USING ERRCODE = '23514';
  END IF;

  v_prev_status := public.driver_effective_status(p_driver_id);

  UPDATE public.drivers
     SET deleted_at      = now(),
         deleted_by      = v_admin.admin_id,
         deletion_reason = trim(p_reason),
         is_online       = false
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      'driver_soft_delete',
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',           v_driver.name,
        'driver_email',          v_driver.email,
        'user_id',               v_driver.user_id,
        'reason',                trim(p_reason),
        'balance_at_delete',     COALESCE(v_balance, 0),
        'previous_status',       v_prev_status,
        'guards_active_orders',  v_active_orders,
        'guards_pending_settle', v_pending_settle
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_soft_delete_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',         true,
    'driver_id',       p_driver_id,
    'driver_name',     v_driver.name,
    'reason',          trim(p_reason),
    'deleted_at',      now(),
    'previous_status', v_prev_status
  );
END;
$function$;

revoke all on function public.admin_soft_delete_driver(uuid, text) from public, anon;
grant execute on function public.admin_soft_delete_driver(uuid, text) to authenticated;

-- PROVA P5.4. Antes e depois (só leitura): quantos estafetas a guarda velha deixava passar.
--   with x as (
--     select d.id, d.user_id,
--       (select count(*) from public.driver_balances b where b.driver_id = d.id and b.balance <> 0) as sal_id,
--       (select count(*) from public.driver_balances b where b.driver_id in (d.id, d.user_id) and b.balance <> 0) as sal_ambos,
--       (select count(*) from public.orders o where o.assigned_driver_id = d.id::text
--          and o.status not in ('delivered','cancelled','rejected')) as ped_id,
--       (select count(*) from public.orders o where o.assigned_driver_id in (d.id::text, d.user_id::text)
--          and o.status not in ('delivered','cancelled','rejected')) as ped_ambos,
--       (select count(*) from public.driver_transactions t where t.driver_id = d.id and t.status = 'pending') as pen_id,
--       (select count(*) from public.driver_transactions t where t.driver_id in (d.id, d.user_id) and t.status = 'pending') as pen_ambos
--     from public.drivers d where d.deleted_at is null)
--   select count(*) filter (where sal_ambos > sal_id or ped_ambos > ped_id or pen_ambos > pen_id) from x;
--     -- 15/11: 3 (todos por saldo). A guarda nova recusa estes 3.
--   Depois de aplicar, numa transação desfeita, com um desses estafetas (pelo drivers.id):
--   begin;
--     select set_config('request.jwt.claims',
--       '{"sub":"<uid_de_um_admin>","role":"authenticated","app_metadata":{"role":"admin"}}', true);
--     select public.admin_soft_delete_driver('<drivers.id>', 'prova em rollback, nao remover');
--       -- erro: Cannot delete: driver has non-zero balance of EUR ...
--   rollback;


-- =====================================================================================================
-- P5.5  admin_update_driver — NADA PARA APLICAR AQUI.
-- =====================================================================================================
-- A versão de 8 parâmetros sai na proposta P1 (P1_leitura_admin_pedidos_saldos.PROPOSTA.sql, bloco
-- "admin_update_driver: fica só a versão de 10 parâmetros"): a de 10 só muda a cor e o modelo quando
-- vêm preenchidos, por isso apagar a de 8 é seguro também para a app publicada. Não repetir o drop aqui.
-- O texto da versão de 10 (a que fica) passa a estar no repo em
-- supabase/migrations/20260702182113_admin_update_driver_10_params_doc.sql (documenta o que está no ar;
-- conferido byte a byte com o ar: 4788 caracteres, md5 0b9debea3e7db8725fdf314344fd7d59).
-- PROVA:
--   select md5(pg_get_functiondef(
--     'public.admin_update_driver(uuid,text,text,text,text,text,text,text,text,text)'::regprocedure));
--   -- 0b9debea3e7db8725fdf314344fd7d59


-- =====================================================================================================
-- P5.6  admin_fatura_mes_estafeta(p_user_id uuid, p_mes date) -> jsonb   (só leitura)
-- =====================================================================================================
-- O PROBLEMA: na Área do estafeta o painel não mostra a fatura-recibo do mês dele (o que ele vê na
--   app, no cartão do recibo verde). Hoje só o Fecho mensal mostra todos de uma vez.
-- O QUE MUDA: uma função só de leitura que chama a MESMA conta do estafeta,
--   driver_monthly_invoice_summary(ano, mês) (lida a 15/11, md5 acima): com um admin ela devolve todos
--   os estafetas do mês e esta função fica só com a linha dele. Os números são os mesmos que ele vê na
--   app, sem copiar a conta nem os dados da empresa que estão dentro dela.
--   Aceita user_id (o certo) ou drivers.id. p_mes = qualquer dia do mês (ex.: '2026-10-01').
--   Devolve {ano, mes, nome_mes, user_id, driver_id, tem_entregas, estafeta (a linha dele ou null),
--   adquirente}. Sem entregas no mês: tem_entregas=false e estafeta=null.

create or replace function public.admin_fatura_mes_estafeta(p_user_id uuid, p_mes date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_user_id   uuid;
  v_driver_id uuid;
  v_ano       integer;
  v_mes       integer;
  v_tudo      jsonb;
  v_linha     jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required: só um admin pode ver a fatura de um entregador' using errcode = '42501';
  end if;
  if p_user_id is null or p_mes is null then
    raise exception 'parametros_obrigatorios: p_user_id e p_mes' using errcode = '22023';
  end if;

  select d.user_id, d.id into v_user_id, v_driver_id
    from public.drivers d
   where d.user_id = p_user_id or d.id = p_user_id
   order by (d.user_id = p_user_id) desc
   limit 1;
  v_user_id := coalesce(v_user_id, p_user_id);
  v_ano := extract(year from p_mes)::integer;
  v_mes := extract(month from p_mes)::integer;

  -- A mesma conta do estafeta (com admin devolve todos; fica-se com a linha dele).
  v_tudo := public.driver_monthly_invoice_summary(v_ano, v_mes);
  select e into v_linha
    from jsonb_array_elements(coalesce(v_tudo -> 'estafetas', '[]'::jsonb)) e
   where e ->> 'user_id' = v_user_id::text
   limit 1;

  return jsonb_build_object(
    'ano', v_ano, 'mes', v_mes, 'nome_mes', v_tudo -> 'nome_mes',
    'user_id', v_user_id, 'driver_id', v_driver_id,
    'tem_entregas', v_linha is not null,
    'estafeta', v_linha,
    'adquirente', v_tudo -> 'adquirente');
end
$function$;

revoke all on function public.admin_fatura_mes_estafeta(uuid, date) from public, anon;
grant execute on function public.admin_fatura_mes_estafeta(uuid, date) to authenticated;

-- PROVA P5.6 (só leitura; a transação é só para as claims):
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uid_de_um_admin>","role":"authenticated"}', true);
--     select (public.admin_fatura_mes_estafeta('<user_id>', date '2026-10-01') -> 'estafeta')
--          = (select e from jsonb_array_elements(public.driver_monthly_invoice_summary(2026, 10) -> 'estafetas') e
--              where e ->> 'user_id' = '<user_id>');                                   -- true
--     select public.admin_fatura_mes_estafeta('<drivers.id do mesmo>', date '2026-10-15') ->> 'user_id';  -- '<user_id>'
--   rollback;
--   Com claims de um uid que não é admin: erro admin_required.


-- =====================================================================================================
-- ROLLBACK (NÃO CORRER COM O RESTO; só para desfazer uma parte já aplicada)
-- =====================================================================================================
--   P5.1: drop function if exists public.admin_set_driver_online(text, boolean, text);
--   P5.2: drop function if exists public.admin_estafeta_avancar(text, text, text);
--   P5.3: drop function if exists public.admin_revogar_sessoes(uuid);
--         e voltar a publicar a Edge que está no repo (supabase/functions/admin-force-driver-logout/
--         index.ts, que esta proposta não alterou).
--   P5.6: drop function if exists public.admin_fatura_mes_estafeta(uuid, date);
--   P5.4: voltar ao texto de 15/11/2026 (guardas só pelo drivers.id; md5 e0050c31fdac84c93a52405ac2d5af71),
--         copiado de pg_get_functiondef. Tirar o "-- " do início de cada linha:
-- CREATE OR REPLACE FUNCTION public.admin_soft_delete_driver(p_driver_id uuid, p_reason text)
--  RETURNS jsonb
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   v_admin           RECORD;
--   v_driver          RECORD;
--   v_active_orders   INTEGER;
--   v_balance         NUMERIC(10,2);
--   v_pending_settle  INTEGER;
--   v_prev_status     TEXT;
-- BEGIN
--   SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
--
--   IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
--     RAISE EXCEPTION 'reason_required: soft delete needs a reason (min 10 chars)'
--       USING ERRCODE = '23502';
--   END IF;
--
--   SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
--   IF NOT FOUND THEN
--     RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
--   END IF;
--   IF v_driver.deleted_at IS NOT NULL THEN
--     RAISE EXCEPTION 'driver_already_deleted: % (reactivate first if needed)',
--       p_driver_id USING ERRCODE = '23514';
--   END IF;
--
--   SELECT COUNT(*) INTO v_active_orders
--   FROM public.orders
--   WHERE assigned_driver_id = p_driver_id::text
--     AND status NOT IN ('delivered', 'cancelled', 'rejected');
--   IF v_active_orders > 0 THEN
--     RAISE EXCEPTION 'Cannot delete: driver has % active order(s)', v_active_orders
--       USING ERRCODE = '23514';
--   END IF;
--
--   SELECT COALESCE(balance, 0) INTO v_balance
--   FROM public.driver_balances WHERE driver_id = p_driver_id;
--   IF v_balance IS NOT NULL AND v_balance <> 0 THEN
--     RAISE EXCEPTION 'Cannot delete: driver has non-zero balance of EUR %',
--       to_char(v_balance, 'FM999990.00') USING ERRCODE = '23514';
--   END IF;
--
--   SELECT COUNT(*) INTO v_pending_settle
--   FROM public.driver_transactions
--   WHERE driver_id = p_driver_id AND status = 'pending';
--   IF v_pending_settle > 0 THEN
--     RAISE EXCEPTION 'Cannot delete: driver has % pending cash settlement(s)',
--       v_pending_settle USING ERRCODE = '23514';
--   END IF;
--
--   v_prev_status := public.driver_effective_status(p_driver_id);
--
--   UPDATE public.drivers
--      SET deleted_at      = now(),
--          deleted_by      = v_admin.admin_id,
--          deletion_reason = trim(p_reason),
--          is_online       = false
--    WHERE id = p_driver_id;
--
--   BEGIN
--     PERFORM public.log_admin_action(
--       'driver_soft_delete',
--       'driver',
--       p_driver_id,
--       jsonb_build_object(
--         'driver_name',           v_driver.name,
--         'driver_email',          v_driver.email,
--         'reason',                trim(p_reason),
--         'balance_at_delete',     COALESCE(v_balance, 0),
--         'previous_status',       v_prev_status,
--         'guards_active_orders',  v_active_orders,
--         'guards_pending_settle', v_pending_settle
--       )
--     );
--   EXCEPTION WHEN OTHERS THEN
--     RAISE WARNING 'admin_soft_delete_driver: audit log failed: %', SQLERRM;
--   END;
--
--   RETURN jsonb_build_object(
--     'success',         true,
--     'driver_id',       p_driver_id,
--     'driver_name',     v_driver.name,
--     'reason',          trim(p_reason),
--     'deleted_at',      now(),
--     'previous_status', v_prev_status
--   );
-- END;
-- $function$;
alter table public.bkp_fn_admin_soft_delete_driver_20261115 enable row level security;
