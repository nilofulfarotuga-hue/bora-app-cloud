-- Missão servidor-busca-leve-2026-11-17, bloco B4. APLICA A CLAUDE.AI.
--
-- O aviso do vigia-servidor passa a dizer em palavras simples QUEM gerou a carga e O QUÊ (nome da
-- função ou do ecrã em vez do SQL). E junta só o MESMO aviso: antes, depois de um aviso, qualquer
-- outro (mesmo de outra causa) ficava calado 30 min. Agora a chave é causa + quem + o quê; o mesmo
-- aviso repetido junta-se num só durante 30 min (e o seguinte diz quantas vezes se repetiu); um
-- aviso novo sai logo. O resto de _cron_vigia_servidor é o texto de produção lido a 17/11.

-- quem: o papel (role) da base em palavras de gente
create or replace function public.vigia_quem(p_papel text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select case p_papel
    when 'anon' then 'pessoas sem login (pode ser o robô de teste da Google depois de uma versão nova)'
    when 'authenticated' then 'clientes com conta'
    when 'service_role' then 'os robôs e funções internas da Bora'
    when 'supabase_admin' then 'o próprio Supabase (tempo real e manutenção)'
    when 'postgres' then 'tarefas agendadas e administração'
    when 'authenticator' then 'a ligação da API'
    else coalesce(nullif(p_papel, ''), 'desconhecido')
  end
$$;

-- o quê: o nome da função (RPC) ou da tabela lida, em vez do SQL
create or replace function public.vigia_o_que(p_consulta text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  with f as (
    select coalesce(substring(p_consulta from '"public"\."([A-Za-z0-9_]+)"\('),
                    substring(p_consulta from 'public\.([A-Za-z0-9_]+)\(')) as rpc,
           substring(p_consulta from 'FROM "public"\."([A-Za-z0-9_]+)"') as tabela
  )
  select case
    when p_consulta is null or btrim(p_consulta) = '' then 'desconhecido'
    when f.rpc = 'search_products' then 'a lupa dentro das lojas (search_products)'
    when f.rpc = 'cliente_pesquisar' then 'a lupa da página inicial (cliente_pesquisar)'
    when f.rpc = 'pesquisa_produtos' then 'a pesquisa de produtos (pesquisa_produtos)'
    when f.rpc = 'assistant_search_products' then 'o assistente de compras (assistant_search_products)'
    when f.rpc = 'agent_search_products' then 'o robô de suporte (agent_search_products)'
    when f.rpc is not null then 'a função ' || f.rpc
    when p_consulta ~ 'wal->>' then 'o tempo real do Supabase a ler as alterações'
    when f.tabela = 'orders' then 'a leitura dos pedidos (tabela orders)'
    when f.tabela = 'products' then 'a leitura dos produtos (tabela products)'
    when f.tabela = 'restaurants' then 'a leitura das lojas (tabela restaurants)'
    when f.tabela is not null then 'a leitura da tabela ' || f.tabela
    else 'uma consulta: ' || left(regexp_replace(p_consulta, '\s+', ' ', 'g'), 80)
  end
  from f
$$;

revoke all on function public.vigia_quem(text) from public, anon;
revoke all on function public.vigia_o_que(text) from public, anon;
grant execute on function public.vigia_quem(text) to authenticated, service_role;
grant execute on function public.vigia_o_que(text) to authenticated, service_role;

alter table public.vigia_servidor_registos add column if not exists quem text;
alter table public.vigia_servidor_registos add column if not exists o_que text;

-- um aviso por chave (causa + quem + o quê) de 30 em 30 min; "juntados" conta os calados
create table if not exists public.vigia_servidor_avisos (
  chave     text primary key,
  ultimo_em timestamptz not null,
  juntados  integer not null default 0
);
alter table public.vigia_servidor_avisos enable row level security;
revoke all on public.vigia_servidor_avisos from anon, authenticated;

create or replace function public._cron_vigia_servidor()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_agora      timestamptz := clock_timestamp();
  v_antes      timestamptz;
  v_int_ms     double precision;
  v_total_ms   double precision;
  v_top        record;
  v_canais     jsonb;
  v_canal_max  int;
  v_ocupado    numeric;
  v_top_pct    numeric;
  v_motivo     text;
  v_msg        text;
  v_quem       text;
  v_o_que      text;
  v_chave      text;
  v_aviso      record;
  v_juntados   int := 0;
begin
  select tirada_em into v_antes
    from public.vigia_servidor_estado where id = 1 for update;

  create temp table if not exists _vs_agora (
    queryid bigint, userid oid, dbid oid, total_ms double precision, calls bigint, query text
  ) on commit drop;
  truncate _vs_agora;
  insert into _vs_agora
    select s.queryid, s.userid, s.dbid, sum(s.total_exec_time), sum(s.calls)::bigint, min(s.query)
      from extensions.pg_stat_statements s
     where s.queryid is not null
       -- 23/11: esperas (pg_sleep) nao gastam processador; contavam como carga e davam alarme falso
       and s.query !~* 'pg_sleep'
     group by s.queryid, s.userid, s.dbid;

  -- canais de tempo real por conta e tabela (a assinatura do defeito de 16/11)
  select coalesce(jsonb_agg(x order by x.canais desc), '[]'::jsonb), coalesce(max(x.canais), 0)
    into v_canais, v_canal_max
    from (
      select g.user_id,
             (select coalesce(nullif(u.name, ''), u.email) from public.users u
               where u.id::text = g.user_id) as nome,
             g.tabela, g.canais
        from (
          select r.claims->>'sub' as user_id,
                 r.entity::regclass::text as tabela,
                 count(*)::int as canais
            from realtime.subscription r
           group by 1, 2
           order by 3 desc
           limit 5
        ) g
    ) x;

  if v_antes is not null and v_agora - v_antes between interval '1 minute' and interval '30 minutes' then
    v_int_ms := extract(epoch from (v_agora - v_antes)) * 1000;

    with d as (
      select a.userid, a.calls - coalesce(f.calls, 0) as vezes, a.query,
             case when f.total_ms is null or a.total_ms < f.total_ms then a.total_ms
                  else a.total_ms - f.total_ms end as ms
        from _vs_agora a
        left join public.vigia_servidor_foto f
          on f.queryid = a.queryid and f.userid = a.userid and f.dbid = a.dbid
    )
    select coalesce(sum(ms), 0) into v_total_ms from d;

    select d2.ms, d2.vezes, d2.query, r.rolname
      into v_top
      from (
        select a.userid, a.query,
               greatest(a.calls - coalesce(f.calls, 0), 0) as vezes,
               case when f.total_ms is null or a.total_ms < f.total_ms then a.total_ms
                    else a.total_ms - f.total_ms end as ms
          from _vs_agora a
          left join public.vigia_servidor_foto f
            on f.queryid = a.queryid and f.userid = a.userid and f.dbid = a.dbid
      ) d2
      left join pg_roles r on r.oid = d2.userid
     order by d2.ms desc
     limit 1;

    v_ocupado := round((100 * v_total_ms / v_int_ms)::numeric, 1);
    v_top_pct := case when v_total_ms > 0 then round((100 * v_top.ms / v_total_ms)::numeric, 1) end;
    v_quem := public.vigia_quem(v_top.rolname);
    v_o_que := public.vigia_o_que(v_top.query);

    if v_ocupado >= 50 and coalesce(v_top_pct, 0) >= 40 then
      v_motivo := 'consulta_pesada';
      v_chave := v_motivo || '|' || coalesce(v_top.rolname, '?') || '|' || v_o_que;
    elsif v_canal_max >= 10 then
      v_motivo := 'canais_acumulados';
      v_chave := v_motivo || '|' || coalesce(v_canais->0->>'user_id', '?') || '|'
                 || coalesce(v_canais->0->>'tabela', '?');
    end if;

    if v_motivo is not null then
      select * into v_aviso from public.vigia_servidor_avisos where chave = v_chave for update;
      if found and v_agora - v_aviso.ultimo_em < interval '30 minutes' then
        -- o mesmo aviso há menos de 30 min: junta-se, não sai outra vez
        update public.vigia_servidor_avisos set juntados = juntados + 1 where chave = v_chave;
      else
        v_juntados := coalesce(v_aviso.juntados, 0);
        v_msg := case v_motivo
          when 'consulta_pesada' then
            '🚨 SERVIDOR CARREGADO' || E'\n'
            || 'Nos últimos ' || round((v_int_ms / 60000)::numeric) || ' min o servidor esteve '
            || v_ocupado || '% ocupado.' || E'\n'
            || 'Quem: ' || v_quem || '.' || E'\n'
            || 'O quê: ' || v_o_que || ', ' || coalesce(v_top.vezes, 0) || ' vezes'
            || case when coalesce(v_top.vezes, 0) > 0
                    then ', ' || round((v_top.ms / v_top.vezes)::numeric) || ' ms cada' else '' end
            || ' (' || v_top_pct || '% do trabalho).'
          else
            '🚨 APP A ABRIR CANAIS SEM PARAR' || E'\n'
            || 'Uma conta tem ' || v_canal_max || ' canais de tempo real abertos na mesma tabela'
          end
          || case when v_canal_max >= 3 then
               E'\n' || 'Mais canais: ' || coalesce(v_canais->0->>'nome', v_canais->0->>'user_id', '?')
               || ' (' || (v_canais->0->>'canais') || ' em ' || (v_canais->0->>'tabela') || ')'
             else '' end
          || case when v_juntados > 0 then
               E'\n' || 'O mesmo aviso repetiu-se ' || v_juntados || ' vez(es) desde o anterior.'
             else '' end;
        begin
          perform public.notify_admin_urgent_push(
            'servidor_carregado', v_msg, 'servidor', v_motivo,
            jsonb_build_object('ocupado_pct', v_ocupado, 'top_pct', v_top_pct,
                               'top_vezes', v_top.vezes, 'quem', v_quem, 'o_que', v_o_que,
                               'juntados', v_juntados, 'canais_top', v_canais),
            '/admin/vigia-servidor');
          insert into public.vigia_servidor_avisos (chave, ultimo_em, juntados)
          values (v_chave, v_agora, 0)
          on conflict (chave) do update set ultimo_em = excluded.ultimo_em, juntados = 0;
          update public.vigia_servidor_estado set ultimo_alerta_em = v_agora where id = 1;
        exception when others then
          raise notice '_cron_vigia_servidor: aviso falhou: %', sqlerrm;
          v_msg := null;
        end;
      end if;
    end if;

    insert into public.vigia_servidor_registos
      (intervalo_s, ocupado_pct, top_pct, top_papel, top_vezes, top_media_ms, top_consulta,
       canais_top, alertou, motivo, quem, o_que)
    values
      (round((v_int_ms / 1000)::numeric), v_ocupado, v_top_pct, v_top.rolname, v_top.vezes,
       case when coalesce(v_top.vezes, 0) > 0 then round((v_top.ms / v_top.vezes)::numeric, 1) end,
       left(regexp_replace(coalesce(v_top.query, ''), '\s+', ' ', 'g'), 300),
       v_canais, v_msg is not null, v_motivo, v_quem, v_o_que);
  end if;

  -- nova fotografia
  delete from public.vigia_servidor_foto where true;
  insert into public.vigia_servidor_foto (queryid, userid, dbid, total_ms, calls)
    select queryid, userid, dbid, total_ms, calls from _vs_agora;
  update public.vigia_servidor_estado set tirada_em = v_agora where id = 1;

  delete from public.vigia_servidor_registos where criado_em < now() - interval '14 days';
  delete from public.vigia_servidor_avisos where ultimo_em < now() - interval '2 days';
end
$function$;

-- Prova (correr depois de aplicar; esperado = os textos de gente):
-- select public.vigia_quem('anon'), public.vigia_o_que('WITH pgrst_source AS (SELECT "pgrst_call".* FROM (SELECT $1 AS json_data) pgrst_payload, LATERAL (SELECT "search_products".* FROM "public"."search_products"("query_text" := $2)) pgrst_call)');
