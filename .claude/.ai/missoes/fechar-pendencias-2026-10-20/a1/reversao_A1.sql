-- REVERSÃO do Bloco A1 (encomendas = TVDE) — 21/10/2026.
-- Desfaz as migrações 20261021083257_encomendas_base, 20261021083355_encomendas_rpcs_ride_kind
-- , 20261021083510_encomendas_avisos_e_painel, 20261021090625_encomendas_sem_preferencias_de_passageiro
-- 20261021095810_encomendas_tipo_declarado_preso_ao_pedido, 20261021100840_encomendas_acertos_com_gorjetas
-- e 20261021101037_encomendas_recibo_com_palavras_de_entrega (ronda 1),
-- repondo as 8 funções EXACTAMENTE como estavam
-- (texto guardado em public.bkp_fn_encomendas_20261021, md5 conferido) e as permissões de antes.
-- Provada em transacção desfeita a 21/10 (ver RELATORIO-A1.md). Só correr com ordem.
--
-- Não apaga: as 2 chaves de platform_settings (sem código a lê-las não fazem nada) nem a
-- tabela de backup. A coluna ride_kind só sai se não houver NENHUMA encomenda gravada;
-- se houver, fica (perder-se-ia que aquelas corridas eram encomendas) e o aviso diz quantas.

do $rev$
declare
  r record; v_n int;
begin
  -- 1. as 3 RPCs: tira a assinatura nova e repõe a antiga a partir do backup
  for r in select * from (values
      ('tvde_request_ride',
       'double precision, double precision, text, double precision, double precision, text, numeric, text, integer, text',
       'double precision, double precision, text, double precision, double precision, text, numeric, text, integer'),
      ('tvde_schedule_roundtrip',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, timestamp with time zone, text, text, text',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, timestamp with time zone, text, text'),
      ('tvde_schedule_ride',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text, text',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text')
    ) as t(nome, sig_nova, sig_antiga)
  loop
    execute format('DROP FUNCTION IF EXISTS public.%I(%s)', r.nome, r.sig_nova);
    execute (select b.definicao from public.bkp_fn_encomendas_20261021 b where b.nome = r.nome);
    execute format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon', r.nome, r.sig_antiga);
    execute format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', r.nome, r.sig_antiga);
  end loop;

  -- 2. aviso ao cliente, listas do painel e preferências: mesma assinatura, volta o texto antigo
  for r in select b.nome, b.definicao from public.bkp_fn_encomendas_20261021 b
            where b.nome in ('fn_notify_tvde_client_on_status', 'admin_tvde_rides_list_v2', 'admin_tvde_reservations_list',
                             'fn_tvde_rides_prefs', '_tvde_recibo')
  loop
    execute r.definicao;
  end loop;

  -- 3. confere o md5 das 8 com o backup
  select count(*) into v_n
    from public.bkp_fn_encomendas_20261021 b
    join pg_proc p on p.proname = b.nome
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where md5(p.prosrc) = b.prosrc_md5;
  if v_n <> 8 then raise exception 'REVERSAO A1: só % de 8 funções voltaram ao md5 de antes', v_n; end if;

  -- 4. o que a A1 criou
  drop function if exists public.admin_tvde_acertos_por_tipo(timestamptz);
  drop trigger if exists trg_tvde_ride_kind_da_volta on public.tvde_rides;
  drop function if exists public.fn_tvde_ride_kind_da_volta();
  drop function if exists public._tvde_ride_kind_resolver(uuid, text, text, double precision, double precision, double precision, double precision);
  drop function if exists public._tvde_ride_kind_resolver(uuid, text);
  drop function if exists public.tvde_definir_tipo_pedido(text, text, double precision, double precision, double precision, double precision);
  drop function if exists public.tvde_definir_tipo_pedido(text);
  drop table if exists public.tvde_tipo_pedido;

  select count(*) into v_n from public.tvde_rides where ride_kind = 'encomendas';
  if v_n = 0 then
    drop index if exists public.tvde_rides_encomendas_idx;
    alter table public.tvde_rides drop constraint if exists tvde_rides_ride_kind_check;
    alter table public.tvde_rides drop column if exists ride_kind;
  else
    raise notice 'REVERSAO A1: % encomenda(s) gravada(s) — a coluna ride_kind FICA (nada mais a lê).', v_n;
  end if;
end $rev$;

notify pgrst, 'reload schema';
