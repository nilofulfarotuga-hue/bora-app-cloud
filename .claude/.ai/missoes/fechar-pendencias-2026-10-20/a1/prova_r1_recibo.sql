-- A1 ronda 1 · prova em ROLLBACK (termina em RAISE EXCEPTION 'RESULT' -> nada fica gravado)
-- corrida 21/10/2026 via MCP execute_sql, projecto ojykpzwqrtusfeakzrna
create or replace function pg_temp._a1_troca(p_txt text, p_de text, p_para text, p_vezes int, p_onde text)
returns text language plpgsql as $f$
declare v_n int;
begin
  v_n := (length(p_txt) - length(replace(p_txt, p_de, ''))) / greatest(length(p_de), 1);
  if v_n <> p_vezes then raise exception 'A1 ancora % apareceu % vez(es), esperava %', p_onde, v_n, p_vezes; end if;
  return replace(p_txt, p_de, p_para);
end $f$;
do $m7$
declare v_def text; v_src text; v_back text;
  c_ini_old constant text := E'  return jsonb_build_object(\n    ''ride_id'', r.id,';
  c_ini_new constant text := E'  return (jsonb_build_object(\n    ''ride_id'', r.id,';
  c_fim_old constant text := E'pela Autoridade Tributária.'');\nend';
  c_fim_new constant text := E'pela Autoridade Tributária.''))\n'
    || E'    -- 21/10/2026 (A1 r1): numa encomenda as palavras são de entrega (os números não mudam).\n'
    || E'    || case when r.ride_kind = ''encomendas'' then jsonb_strip_nulls(jsonb_build_object(\n'
    || E'         ''titulo'', ''Resumo da entrega'',\n'
    || E'         ''razao'', case\n'
    || E'           when v_total = 0 then ''Entrega incluída num pacote ou assinatura já pago.''\n'
    || E'           when not v_bate then ''Entrega com ajuste de pacote ida-e-volta: a divisão entre estafeta e Bora está no teu extrato de pacote.''\n'
    || E'           end,\n'
    || E'         ''aviso_legal'', ''Resumo da entrega. Não é uma fatura: a fatura é emitida por software certificado pela Autoridade Tributária.''))\n'
    || E'       else ''{}''::jsonb end;\nend';
begin
  if (select md5(prosrc) from pg_proc where oid = 'public._tvde_recibo(uuid)'::regprocedure) <> 'a75fdb28685713f3a3ba70e8e9af2c68' then
    raise exception 'mudou'; end if;
  v_def := pg_get_functiondef('public._tvde_recibo(uuid)'::regprocedure);
  v_def := pg_temp._a1_troca(v_def, c_ini_old, c_ini_new, 1, 'recibo:inicio');
  v_def := pg_temp._a1_troca(v_def, c_fim_old, c_fim_new, 1, 'recibo:fim');
  execute v_def;
  select prosrc into v_src from pg_proc where oid = 'public._tvde_recibo(uuid)'::regprocedure;
  v_back := pg_temp._a1_troca(pg_temp._a1_troca(v_src, c_fim_new, c_fim_old, 1, 'desfaz:fim'), c_ini_new, c_ini_old, 1, 'desfaz:inicio');
  if md5(v_back) <> 'a75fdb28685713f3a3ba70e8e9af2c68' then raise exception 'desfeito diferente %', md5(v_back); end if;
end $m7$;
do $t$
declare
  c_cli constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  c_drv constant uuid := 'dede0000-0000-4000-8000-000000000001';
  r public.tvde_rides; v_k text; v_out jsonb := '{}'; v_rec jsonb; v_ids uuid[] := '{}';
begin
  set constraints all immediate;
  update public.platform_settings set value = 'true'::jsonb where key = 'tvde_encomendas_enabled';
  update public.drivers set is_online = false, last_heartbeat_at = now() - interval '1 day'
   where user_id is distinct from c_drv and (is_online or last_heartbeat_at > now() - interval '15 minutes');
  update public.driver_locations set is_online = false, last_updated = now() - interval '1 day'
   where driver_id not in (c_drv, 'dede0000-0000-4000-8000-000000000002'::uuid) and (is_online or last_updated > now() - interval '15 minutes');
  update public.drivers set vehicle_type = 'carro_passageiros', is_online = true, last_heartbeat_at = now() where user_id = c_drv;
  update public.driver_locations set is_online = true, last_updated = now(), latitude = 40.5380, longitude = -7.2680 where driver_id = c_drv;
  foreach v_k in array array['encomendas','passageiros'] loop
    perform set_config('request.jwt.claim.sub', c_cli::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
    r := public.tvde_request_ride(40.5373, -7.2675, 'A', 40.5650, -7.2675, 'B', 4.0, 'cash', 0, case when v_k='encomendas' then 'encomendas' end);
    perform set_config('request.jwt.claim.sub', c_drv::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
    perform public.tvde_accept_ride(r.id); perform public.tvde_driver_arrived(r.id); perform public.tvde_start_ride(r.id);
    perform public.tvde_finish_ride(r.id, 4.0, 'prova_a1_r1', 0);
    v_rec := public._tvde_recibo(r.id);
    v_out := v_out || jsonb_build_object(v_k, jsonb_build_object('titulo', v_rec->>'titulo', 'aviso', v_rec->>'aviso_legal',
      'total', v_rec->'total_pago_cents', 'transporte', v_rec->'transporte_cents', 'taxa', v_rec->'taxa_intermediacao_cents', 'chaves', (select count(*) from jsonb_object_keys(v_rec))));
  end loop;
  raise exception 'RESULT %', v_out::text;
end $t$;