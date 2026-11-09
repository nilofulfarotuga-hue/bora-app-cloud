-- =============================================================================
-- PROVA EM ROLLBACK · M10 item 2.5 · chamada de reforço (migração 20261109050000)
-- GERADO por gerar_prova_chamada_reforco.mjs (não editar à mão: editar o modelo
-- prova_chamada_reforco.modelo.sql e voltar a gerar).
--
-- Corre TUDO num único DO que acaba em RAISE EXCEPTION 'PROVA_OK ...': a exceção
-- desfaz tudo (funções, tabelas, definições, linhas de teste). Garantias:
--   * os gatilhos da migração são criados em CLONES temporários de orders,
--     tvde_rides e tvde_ride_events (CREATE TEMP TABLE ... LIKE, sem gatilho
--     nenhum — nem tr_notify_driver_on_offer nem tr_notify_tvde_driver_on_offer,
--     os únicos que chamam pg_net numa oferta). Nenhum UPDATE em public.orders,
--     public.tvde_rides nem public.drivers;
--   * as funções novas só LEEM public.orders/drivers; escritas reais só em
--     ofertas_prestador_log, platform_settings, chamada_reforco_consentimento e
--     tvde_ride_events (nenhuma destas tabelas tem gatilho com pg_net — o passo
--     12 confere) e tudo é desfeito no fim;
--   * a varredura dispatch_fases_sweep (relança o motor por pg_net) só é chamada
--     DESLIGADA; admin_forcar_chamada só nos caminhos que respondem antes de
--     escrever (desligado / pedido entregue);
--   * o cron da migração NÃO entra (bloco [CRON-INICIO..FIM] retirado).
-- =============================================================================
do $prova$
declare
  v_mig  text := $mig_m10_20261109$__MIGRACAO__$mig_m10_20261109$;
  v_r    text := '';
  v_txt  text;
  v_txt2 text;
  v_j    jsonb;
  v_n    int;
  v_md5_antes text;
  v_val  uuid := 'e355fde0-b634-48ba-bce1-e2a4466c4cc2';  -- Valdemir (user_id)
  v_admin uuid;
  v_ped  text;
  v_ride uuid;
  a  uuid := '00000000-0000-0000-0000-00000000000a';
  b  uuid := '00000000-0000-0000-0000-00000000000b';
  f1 uuid := '00000000-0000-0000-0000-0000000000f1';
  f2 uuid := '00000000-0000-0000-0000-0000000000f2';
  v_dec int := 0;
begin
  perform set_config('lock_timeout', '3000', true);
  v_r := 'md5_migracao_executada=' || md5(v_mig);

  -- ── 0) ANTES da migração ───────────────────────────────────────────────────
  -- 0a) defeito da 070000 de 10/10: tipo enumerado comparado com ''.
  begin
    perform coalesce(x.cancellation_initiator, '') from public.orders x limit 1;
    v_r := v_r || ' | 0a enum_vazio=passou(?)';
  exception when invalid_text_representation then
    v_r := v_r || ' | 0a defeito_10_10 COALESCE(cancellation_initiator,'''')=ERRO_22P02';
  end;
  -- 0b) o registo de ofertas de hoje recusa entregas (regra de 31/10).
  begin
    insert into public.ofertas_prestador_log (categoria, booking_id, prestador_id, tem_aparelho, janela_min)
    values ('entrega', gen_random_uuid(), gen_random_uuid(), true, 1);
    v_r := v_r || ' | 0b registo_aceitava_entrega(?)';
  exception when check_violation then
    v_r := v_r || ' | 0b registo_hoje_recusa_entrega=check_violation';
  end;
  -- 0c) candidatos de hoje para os 40 pedidos mais recentes (só leitura).
  create temp table _ids as select id from public.orders order by created_at desc limit 40;
  v_md5_antes := md5(pg_get_functiondef('public.dispatch_candidatos_entrega(text)'::regprocedure));
  create temp table _antes as
    select o.id as pedido, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c;
  select count(*) into v_n from _antes;
  v_r := v_r || ' | 0c md5_candidatos_no_ar=' || v_md5_antes || ' linhas=' || v_n;

  -- Clones sem gatilhos, onde a migração da prova põe os gatilhos.
  create temp table _orders_clone (like public.orders including defaults);
  create temp table _tvde_rides_clone (like public.tvde_rides including defaults);
  create temp table _tvde_ride_events_clone (like public.tvde_ride_events including defaults);
  execute 'create function pg_temp.o(u uuid, f text) returns jsonb language sql immutable as '
       || '$x$ select jsonb_build_object(''user_id'', u, ''fase'', f) $x$';

  -- ── 1) Aplicar duas vezes (idempotente) ───────────────────────────────────
  execute v_mig;
  execute v_mig;
  v_r := v_r || ' | 1 migracao_2_vezes=ok';

  -- ── 2) Candidatos online = cópia letra a letra do corpo do ar ─────────────
  v_txt := md5(replace(pg_get_functiondef('public._dispatch_candidatos_online(text)'::regprocedure),
                       'public._dispatch_candidatos_online(', 'public.dispatch_candidatos_entrega('));
  if v_txt <> v_md5_antes then raise exception 'PROVA_FALHOU 2 copia diferente (%)', v_txt; end if;
  select md5(definicao) into v_txt from public.bkp_fn_reforco_20261109 where nome = 'dispatch_candidatos_entrega';
  if v_txt is distinct from v_md5_antes then raise exception 'PROVA_FALHOU 2 backup diferente'; end if;
  select string_agg(nome, ',' order by nome) into v_txt from public.bkp_fn_reforco_20261109;
  v_r := v_r || ' | 2 copia_online_md5=igual_ao_ar backup=' || v_txt;

  -- ── 3) Interruptores nascem desligados ────────────────────────────────────
  if coalesce((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, true)
     or coalesce((public.get_setting('tvde_forcado_ligado') #>> '{}')::boolean, true) then
    raise exception 'PROVA_FALHOU 3 interruptor ligado';
  end if;
  v_r := v_r || ' | 3 dispatch_forcado_ligado=false tvde_forcado_ligado=false';

  -- ── 4) Desligado: o motor recebe EXATAMENTE a lista de antes ───────────────
  select count(*) into v_n from (
    (select * from _antes
     except all
     select o.id, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c)
    union all
    (select o.id, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c
     except all
     select * from _antes)) d;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 4 lista mudou (% diferencas)', v_n; end if;
  v_j := public.dispatch_fase_entrega((select id from _ids limit 1));
  v_txt := (v_j->>'fase') || '/' || (v_j->>'motivo');
  v_j := public.dispatch_fases_sweep();
  v_r := v_r || ' | 4 desligado: diferencas_na_lista=0 fase=' || v_txt || ' varredura=' || v_j::text;

  -- ── 5) Decisão pura (regra do Danilo) ─────────────────────────────────────
  -- a) desligado
  v_j := public.dispatch_fase_decidir(array[a,b], '[]', array[f1], false, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5a %', v_j; end if; v_dec := v_dec + 1;
  -- b) dois online, ninguém chamado → online
  v_j := public.dispatch_fase_decidir(array[a,b], '[]', array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5b %', v_j; end if; v_dec := v_dec + 1;
  -- c) uma volta só → ainda online
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5c %', v_j; end if; v_dec := v_dec + 1;
  -- d) duas voltas → reforço ao 1.º da lista (Valdemir no ar)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5d %', v_j; end if; v_dec := v_dec + 1;
  -- e) depois do 1.º → o 2.º (um de cada vez)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f2::text then raise exception 'PROVA_FALHOU 5e %', v_j; end if; v_dec := v_dec + 1;
  -- f) depois dos dois → volta aos online
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado'), pg_temp.o(f2,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online2' then raise exception 'PROVA_FALHOU 5f %', v_j; end if; v_dec := v_dec + 1;
  -- g) depois da volta final → esgotado (só então pode cancelar pelo tempo)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado'), pg_temp.o(f2,'forcado'), pg_temp.o(a,'online2'), pg_temp.o(b,'online2')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'esgotado' then raise exception 'PROVA_FALHOU 5g %', v_j; end if; v_dec := v_dec + 1;
  -- h) só um online: volta a ele (2 voltas) antes do reforço
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1')), array[f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5h %', v_j; end if; v_dec := v_dec + 1;
  -- i) ninguém online → reforço logo
  v_j := public.dispatch_fase_decidir('{}'::uuid[], '[]', array[f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5i %', v_j; end if; v_dec := v_dec + 1;
  -- j) quem está na lista mas está online é saltado
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(a,'online1')), array[a,f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5j %', v_j; end if; v_dec := v_dec + 1;
  -- k) ninguém consentiu → volta aos online
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(a,'online1')), '{}'::uuid[], true, 2, 2, 1);
  if v_j->>'fase' <> 'online2' then raise exception 'PROVA_FALHOU 5k %', v_j; end if; v_dec := v_dec + 1;
  -- l) linha do registo sem user_id não estraga a conta
  v_j := public.dispatch_fase_decidir('{}'::uuid[], jsonb_build_array(jsonb_build_object('fase','forcado'), pg_temp.o(f1,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f2::text then raise exception 'PROVA_FALHOU 5l %', v_j; end if; v_dec := v_dec + 1;
  v_r := v_r || ' | 5 decisoes=' || v_dec || '/12';

  -- ── 6) Horário do reforço ─────────────────────────────────────────────────
  if not (public.dispatch_reforco_horario_ok('08:00', '08:00', '23:00')
          and not public.dispatch_reforco_horario_ok('07:59', '08:00', '23:00')
          and public.dispatch_reforco_horario_ok('22:59', '08:00', '23:00')
          and not public.dispatch_reforco_horario_ok('23:00', '08:00', '23:00')
          and public.dispatch_reforco_horario_ok('01:00', '22:00', '06:00')
          and not public.dispatch_reforco_horario_ok('12:00', '22:00', '06:00')) then
    raise exception 'PROVA_FALHOU 6 horario';
  end if;
  v_r := v_r || ' | 6 horario=ok';

  -- ── 7) Defeitos de 10/10 corrigidos ───────────────────────────────────────
  perform x.cancellation_initiator::text is not distinct from 'system' from public.orders x limit 1;
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, tem_aparelho, janela_min)
  values ('entrega', 'prova-m10', gen_random_uuid(), true, 1);
  v_r := v_r || ' | 7 enum_como_texto=ok registo_aceita_entrega=ok';

  -- ── 8) LIGADO só nesta transação; Valdemir consentiu; horário 00:00-23:59 ─
  update public.platform_settings set value = 'true' where key in ('dispatch_forcado_ligado', 'tvde_forcado_ligado');
  update public.platform_settings set value = '"00:00"' where key = 'dispatch_forcado_horario_inicio';
  update public.platform_settings set value = '"23:59"' where key = 'dispatch_forcado_horario_fim';
  insert into public.chamada_reforco_consentimento (user_id, ligado) values (v_val, true);
  select x.id into v_ped from public.orders x
   where x.status = 'delivered' and not coalesce(x.is_test_order, false) and x.service_type is distinct from 'errand'
   order by x.created_at desc limit 1;
  select string_agg(f.user_id::text || '#' || f.ordem, ',' order by f.ordem) into v_txt
    from public._dispatch_forcados_entrega(v_ped) f;
  select f.user_id::text into v_txt2 from public._dispatch_forcados_entrega(v_ped) f order by f.ordem, f.visto_em desc limit 1;
  if v_txt2 is distinct from v_val::text then raise exception 'PROVA_FALHOU 8 Valdemir nao e o 1.o (%)', v_txt; end if;
  select count(*) into v_n from public._dispatch_candidatos_online(v_ped);
  v_r := v_r || ' | 8 pedido_lido=' || left(v_ped, 8) || ' online_agora=' || v_n || ' lista_reforco=' || v_txt;

  -- ── 9) Gatilhos de entregas no CLONE (sem pg_net) ─────────────────────────
  insert into _orders_clone select * from public.orders where id = v_ped;
  update _orders_clone set status = 'callingDriver', assigned_driver_id = null, driver_id = null,
         current_driver_offer_id = null, driver_offer_expires_at = null, dispatch_calling_since = now(),
         cancellation_initiator = null, cancel_reason = null, dispatch_extended_until = null
   where id = v_ped;
  -- 9a) os online deste pedido já tiveram as 2 voltas (registo montado)
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
                                            janela_min, janela_s, fase, estava_online, desfecho, fechada_em)
  select 'entrega', v_ped, c.driver_id, coalesce(c.user_id, c.driver_id), 'prova', true, 1, 60, 'online1', true, 'expirou', now()
    from public._dispatch_candidatos_online(v_ped) c cross join generate_series(1, 2);
  v_j := public.dispatch_fase_entrega(v_ped);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> v_val::text then raise exception 'PROVA_FALHOU 9a %', v_j; end if;
  -- 9b) o motor recebe SÓ o Valdemir
  select string_agg(coalesce(c.user_id, c.driver_id)::text, ',') into v_txt from public.dispatch_candidatos_entrega(v_ped) c;
  if v_txt is distinct from v_val::text then raise exception 'PROVA_FALHOU 9b motor recebe %', v_txt; end if;
  -- 9c) cancelamento por tempo a meio das fases → adiado (0 linhas mudadas)
  update _orders_clone set status = 'cancelled', cancellation_initiator = 'system', cancel_reason = 'dispatch_safety_timeout'
   where id = v_ped and status = 'callingDriver';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 9c cancelou a meio das fases'; end if;
  -- 9d) oferta ao Valdemir → registo 'forcado', desligado
  update _orders_clone set current_driver_offer_id = v_val::text, driver_offer_expires_at = now() + interval '60 seconds'
   where id = v_ped;
  select l.fase || '/online=' || coalesce(l.estava_online::text, '?') || '/' || l.categoria || '/aparelho=' || l.tem_aparelho
    into v_txt from public.ofertas_prestador_log l
   where l.pedido_ref = v_ped and l.desfecho is null order by l.oferecida_em desc limit 1;
  if v_txt not like 'forcado/online=false/%' then raise exception 'PROVA_FALHOU 9d registo %', v_txt; end if;
  -- 9e) a oferta acaba → o registo fecha; fase seguinte
  update _orders_clone set current_driver_offer_id = null, driver_offer_expires_at = null where id = v_ped;
  select l.desfecho into v_txt2 from public.ofertas_prestador_log l
   where l.pedido_ref = v_ped and l.fase = 'forcado' order by l.oferecida_em desc limit 1;
  if v_txt2 is null then raise exception 'PROVA_FALHOU 9e registo nao fechou'; end if;
  v_j := public.dispatch_fase_entrega(v_ped);
  v_r := v_r || ' | 9 fase=forcado(Valdemir) motor_recebe=so_Valdemir cancelar_a_meio=adiado registo=' || v_txt
             || ' fechou=' || v_txt2 || ' depois=' || (v_j->>'fase');
  -- 9f) volta final aos online → esgotado
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
                                            janela_min, janela_s, fase, estava_online, desfecho, fechada_em)
  select 'entrega', v_ped, c.driver_id, coalesce(c.user_id, c.driver_id), 'prova', true, 1, 60, 'online2', true, 'expirou', now()
    from public._dispatch_candidatos_online(v_ped) c;
  v_j := public.dispatch_fase_entrega(v_ped);
  if v_j->>'fase' <> 'esgotado' then raise exception 'PROVA_FALHOU 9f %', v_j; end if;
  -- 9g) esgotado: o motor recebe os online de sempre (nunca menos do que hoje)
  select count(*) into v_n from (
    (select * from public.dispatch_candidatos_entrega(v_ped) except all select * from public._dispatch_candidatos_online(v_ped))
    union all
    (select * from public._dispatch_candidatos_online(v_ped) except all select * from public.dispatch_candidatos_entrega(v_ped))) d;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 9g'; end if;
  -- 9h) agora o cancelamento por tempo passa (1 linha)
  update _orders_clone set status = 'cancelled', cancellation_initiator = 'system', cancel_reason = 'dispatch_safety_timeout'
   where id = v_ped and status = 'callingDriver';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'PROVA_FALHOU 9h nao cancelou no fim'; end if;
  v_r := v_r || ' | 9 esgotado: motor=online_de_sempre cancelar_no_fim=passa';

  -- ── 10) TVDE no CLONE ─────────────────────────────────────────────────────
  select r.id into v_ride from public.tvde_rides r order by r.created_at desc limit 1;
  insert into _tvde_rides_clone select * from public.tvde_rides where id = v_ride;
  update _tvde_rides_clone set status = 'solicitada', reservation_status = null, source = 'app',
         dispatch_hold_reason = null, driver_id = null, current_offer_driver_id = null,
         offer_expires_at = null, cancel_reason = null
   where id = v_ride;
  -- 10a) só o Valdemir consentiu, mas ele desligou o TVDE na app → fecha como hoje
  update _tvde_rides_clone set status = 'sem_motorista', current_offer_driver_id = null, offer_expires_at = null
   where id = v_ride;
  select c.status into v_txt from _tvde_rides_clone c where c.id = v_ride;
  if v_txt <> 'sem_motorista' then raise exception 'PROVA_FALHOU 10a Valdemir chamado no TVDE (%)', v_txt; end if;
  v_r := v_r || ' | 10a tvde_so_Valdemir(TVDE desligado na app dele)=' || v_txt;
  -- 10b) outro motorista TVDE elegível e desligado consente → fica à procura com oferta de reforço
  select d.user_id into v_admin from public.drivers d
   where d.vehicle_type = 'carro_passageiros' and d.approval_status = 'approved' and d.user_id is not null
     and d.deleted_at is null and coalesce(d.is_banned, false) = false and d.user_id <> v_val
     and public.aceita_papel(d.user_id, 'driver')
     and not (coalesce(d.is_online, false) and d.last_heartbeat_at > now() - make_interval(
              secs => coalesce((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 90)))
     and (coalesce(d.fcm_token, '') <> '' or exists (select 1 from public.driver_push_tokens t
          where t.user_id = d.user_id and t.active and coalesce(t.platform, '') not ilike 'web%'))
     and greatest(coalesce(d.last_heartbeat_at, '-infinity'), coalesce((select max(t.last_used_at)
          from public.driver_push_tokens t where t.user_id = d.user_id and t.active), '-infinity')) > now() - interval '168 hours'
     and not public.tvde_driver_reservation_locked(d.user_id)
     and public.tvde_driver_offer_allowed(d.user_id, v_ride)
     and not exists (select 1 from public.tvde_rides r2 where r2.driver_id = d.user_id
                      and r2.status in ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
   order by d.last_heartbeat_at desc nulls last limit 1;
  if v_admin is null then
    v_r := v_r || ' | 10b sem_motorista_tvde_elegivel_desligado_agora(nao_testado)';
  else
    insert into public.chamada_reforco_consentimento (user_id, ligado) values (v_admin, true)
      on conflict (user_id) do update set ligado = true;
    update _tvde_rides_clone set status = 'solicitada', cancel_reason = null where id = v_ride;
    update _tvde_rides_clone set status = 'sem_motorista', current_offer_driver_id = null, offer_expires_at = null
     where id = v_ride;
    select c.status || '/' || coalesce(c.current_offer_driver_id::text, '-') into v_txt from _tvde_rides_clone c where c.id = v_ride;
    select l.fase into v_txt2 from public.ofertas_prestador_log l
     where l.categoria = 'tvde' and l.booking_id = v_ride and l.desfecho is null order by l.oferecida_em desc limit 1;
    if v_txt <> 'solicitada/' || v_admin::text or v_txt2 is distinct from 'forcado' then
      raise exception 'PROVA_FALHOU 10b % %', v_txt, v_txt2;
    end if;
    v_r := v_r || ' | 10b tvde_outro_consentiu=solicitada+oferta_de_reforco registo=' || v_txt2;
  end if;
  v_admin := null;
  -- 10c) reserva fecha como hoje (sem reforço)
  update _tvde_rides_clone set reservation_status = 'agendada', current_offer_driver_id = null, offer_expires_at = null,
         status = 'solicitada'
   where id = v_ride;
  update _tvde_rides_clone set status = 'sem_motorista' where id = v_ride;
  select c.status into v_txt2 from _tvde_rides_clone c where c.id = v_ride;
  if v_txt2 <> 'sem_motorista' then raise exception 'PROVA_FALHOU 10c reserva %', v_txt2; end if;
  v_r := v_r || ' | 10c tvde_reserva=sem_motorista(como_hoje)';

  -- ── 11) Painel ────────────────────────────────────────────────────────────
  begin
    perform public.admin_reforco_lista();
    raise exception 'PROVA_FALHOU 11 sem admin passou';
  exception when others then
    if sqlerrm like 'PROVA_FALHOU%' then raise; end if;
    v_txt := sqlerrm;
  end;
  select u.id into v_admin from auth.users u where u.email = 'nilofulfarotuga@gmail.com' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_j := public.admin_reforco_lista();
  select e->>'consentiu' || '#ordem=' || coalesce(e->>'ordem', '-') into v_txt2
    from jsonb_array_elements(v_j->'itens') e where e->>'user_id' = v_val::text;
  v_r := v_r || ' | 11 sem_admin=' || v_txt || ' lista_Valdemir_consentiu=' || coalesce(v_txt2, '?');
  v_j := public.admin_ofertas_do_pedido(v_ped);
  select string_agg(e->>'fase' || ':' || (e->>'desfecho'), ',') into v_txt
    from jsonb_array_elements(v_j->'itens') e where e->>'fase' = 'forcado';
  v_r := v_r || ' rotacao_do_pedido=' || jsonb_array_length(v_j->'itens') || '_linhas reforco=' || coalesce(v_txt, '-');
  v_j := public.admin_ofertas_log(null, 1, 20);
  v_r := v_r || ' log_resumo_tem_reforco=' || (v_j->'resumo' ? 'reforco');
  v_j := public.admin_forcar_chamada(v_ped);
  if v_j->>'motivo' is distinct from 'pedido_nao_esta_a_chamar' then raise exception 'PROVA_FALHOU 11 botao %', v_j; end if;
  v_txt := v_j->>'motivo';
  update public.platform_settings set value = 'false' where key = 'dispatch_forcado_ligado';
  v_j := public.admin_forcar_chamada(v_ped);
  if v_j->>'motivo' is distinct from 'reforco_desligado' then raise exception 'PROVA_FALHOU 11 botao desligado %', v_j; end if;
  v_r := v_r || ' botao_pedido_entregue=' || v_txt || ' botao_desligado=' || (v_j->>'motivo');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- ── 12) Quem pode chamar; tabelas escritas sem pg_net; cron fora ──────────
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('dispatch_reforco_horario_ok','dispatch_fase_decidir','_dispatch_candidatos_online',
                       '_dispatch_forcados_entrega','dispatch_fase_entrega','dispatch_candidatos_entrega',
                       '_registar_oferta_entrega','_dispatch_nao_cancelar_cedo','dispatch_fases_sweep',
                       '_tvde_forcados','_tvde_chamada_de_reforco','_registar_oferta_tvde','_registar_toque_tvde',
                       '_reforco_carimbo','admin_ofertas_do_pedido','admin_reforco_lista','admin_ofertas_log',
                       'admin_forcar_chamada')
     and has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 0 then raise exception 'PROVA_FALHOU 12 anon executa % funcoes', v_n; end if;
  select string_agg(p.proname, ',' order by p.proname) into v_txt from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('dispatch_reforco_horario_ok','dispatch_fase_decidir','_dispatch_candidatos_online',
                       '_dispatch_forcados_entrega','dispatch_fase_entrega','dispatch_candidatos_entrega',
                       '_registar_oferta_entrega','_dispatch_nao_cancelar_cedo','dispatch_fases_sweep',
                       '_tvde_forcados','_tvde_chamada_de_reforco','_registar_oferta_tvde','_registar_toque_tvde',
                       '_reforco_carimbo','admin_ofertas_do_pedido','admin_reforco_lista','admin_ofertas_log',
                       'admin_forcar_chamada')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_txt is distinct from 'admin_forcar_chamada,admin_ofertas_do_pedido,admin_ofertas_log,admin_reforco_lista' then
    raise exception 'PROVA_FALHOU 12 authenticated executa %', v_txt;
  end if;
  if has_table_privilege('anon', 'public.chamada_reforco_consentimento', 'select')
     or has_table_privilege('authenticated', 'public.bkp_fn_reforco_20261109', 'select') then
    raise exception 'PROVA_FALHOU 12 tabela aberta';
  end if;
  select count(*) into v_n
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid in ('public.ofertas_prestador_log'::regclass, 'public.platform_settings'::regclass,
                       'public.chamada_reforco_consentimento'::regclass, 'public.tvde_ride_events'::regclass,
                       'public.bkp_fn_reforco_20261109'::regclass)
     and not t.tgisinternal
     and pg_get_functiondef(p.oid) ~* 'net\.http|http_post|notify-';
  if v_n <> 0 then raise exception 'PROVA_FALHOU 12 tabela escrita tem gatilho com pg_net'; end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid in ('pg_temp._orders_clone'::regclass, 'pg_temp._tvde_rides_clone'::regclass,
                       'pg_temp._tvde_ride_events_clone'::regclass) and not t.tgisinternal;
  v_r := v_r || ' | 12 anon=0_funcoes authenticated=' || v_txt || ' tabelas_escritas_sem_pg_net=ok gatilhos_nos_clones=' || v_n
             || ' cron_na_prova=' || (select count(*) from cron.job where jobname = 'dispatch_fases_sweep');

  raise exception 'PROVA_OK %', v_r;
end $prova$;
