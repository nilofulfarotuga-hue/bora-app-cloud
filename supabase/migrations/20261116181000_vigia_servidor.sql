-- Missão servidor-nao-travar-2026-11-16, bloco B3.3 — vigia do servidor.
-- 16/11 16:20-17:15 a app de UMA cliente (canais de tempo real fantasma) fez 23 890
-- leituras de pedidos e ocupou 90% do servidor Micro: login, painel e estafetas deram
-- 504. Ninguém soube a tempo. Esta vigia corre de 5 em 5 min e avisa o Danilo
-- (sininho do painel + push + Telegram, pelo notify_admin_urgent_push) quando:
--   (a) o servidor passou metade dos 5 min ocupado E uma só consulta levou 40% disso; ou
--   (b) uma conta tem 10 ou mais canais de tempo real abertos na mesma tabela
--       (a assinatura do defeito de 16/11: canais que se acumulam).
-- Diz o quê (consulta, quantas vezes, % do servidor) e quem (nome da conta dos canais).
-- No máximo um aviso a cada 30 min. Não mexe em dinheiro nem em despacho: só lê
-- pg_stat_statements e realtime.subscription e escreve nas tabelas dela.
-- Limitação: o 504 do login não se vê de dentro da base (só nos registos da Supabase);
-- quando o servidor fica cheio a regra (a) dispara antes do login cair.

create table if not exists public.vigia_servidor_foto (
  queryid  bigint not null,
  userid   oid    not null,
  dbid     oid    not null,
  total_ms double precision not null,
  calls    bigint not null,
  primary key (queryid, userid, dbid)
);
alter table public.vigia_servidor_foto enable row level security;

create table if not exists public.vigia_servidor_estado (
  id                int primary key default 1 check (id = 1),
  tirada_em         timestamptz,
  ultimo_alerta_em  timestamptz
);
alter table public.vigia_servidor_estado enable row level security;
insert into public.vigia_servidor_estado (id) values (1) on conflict do nothing;

create table if not exists public.vigia_servidor_registos (
  id            bigserial primary key,
  criado_em     timestamptz not null default now(),
  intervalo_s   numeric not null,
  ocupado_pct   numeric not null,       -- tempo de consultas / tempo do intervalo × 100
  top_pct       numeric,                -- % desse tempo gasto pela consulta mais pesada
  top_papel     text,
  top_vezes     bigint,
  top_media_ms  numeric,
  top_consulta  text,
  canais_top    jsonb,                  -- [{user_id, nome, tabela, canais}]
  alertou       boolean not null default false,
  motivo        text
);
alter table public.vigia_servidor_registos enable row level security;
create index if not exists vigia_servidor_registos_criado_idx
  on public.vigia_servidor_registos (criado_em desc);

revoke all on public.vigia_servidor_foto, public.vigia_servidor_estado,
  public.vigia_servidor_registos from anon, authenticated;

create or replace function public._cron_vigia_servidor()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $fn$
declare
  v_agora      timestamptz := clock_timestamp();
  v_antes      timestamptz;
  v_ult_alerta timestamptz;
  v_int_ms     double precision;
  v_total_ms   double precision;
  v_top        record;
  v_canais     jsonb;
  v_canal_max  int;
  v_ocupado    numeric;
  v_top_pct    numeric;
  v_motivo     text;
  v_msg        text;
begin
  select tirada_em, ultimo_alerta_em into v_antes, v_ult_alerta
    from public.vigia_servidor_estado where id = 1 for update;

  create temp table if not exists _vs_agora (
    queryid bigint, userid oid, dbid oid, total_ms double precision, calls bigint, query text
  ) on commit drop;
  truncate _vs_agora;
  insert into _vs_agora
    select s.queryid, s.userid, s.dbid, sum(s.total_exec_time), sum(s.calls)::bigint, min(s.query)
      from extensions.pg_stat_statements s
     where s.queryid is not null
     group by s.queryid, s.userid, s.dbid;

  -- canais de tempo real por conta e tabela (a assinatura do defeito de 16/11)
  select coalesce(jsonb_agg(x order by x.canais desc), '[]'::jsonb), coalesce(max(x.canais), 0)
    into v_canais, v_canal_max
    from (
      select r.claims->>'sub' as user_id,
             (select coalesce(nullif(u.name, ''), u.email) from public.users u
               where u.id::text = r.claims->>'sub') as nome,
             r.entity::regclass::text as tabela,
             count(*)::int as canais
        from realtime.subscription r
       group by 1, 3
       order by 4 desc
       limit 5
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

    if v_ocupado >= 50 and coalesce(v_top_pct, 0) >= 40 then
      v_motivo := 'consulta_pesada';
    elsif v_canal_max >= 10 then
      v_motivo := 'canais_acumulados';
    end if;

    if v_motivo is not null
       and (v_ult_alerta is null or v_agora - v_ult_alerta >= interval '30 minutes') then
      v_msg := case v_motivo
        when 'consulta_pesada' then
          '🚨 SERVIDOR CARREGADO' || E'\n'
          || 'Nos últimos ' || round((v_int_ms / 60000)::numeric) || ' min o servidor esteve '
          || v_ocupado || '% ocupado; uma só consulta levou ' || v_top_pct || '% ('
          || v_top.vezes || ' vezes, papel ' || coalesce(v_top.rolname, '?') || '): '
          || left(regexp_replace(coalesce(v_top.query, ''), '\s+', ' ', 'g'), 140)
        else
          '🚨 APP A ABRIR CANAIS SEM PARAR' || E'\n'
          || 'Uma conta tem ' || v_canal_max || ' canais de tempo real abertos na mesma tabela'
        end
        || case when v_canal_max >= 3 then
             ' · mais canais: ' || coalesce(v_canais->0->>'nome', v_canais->0->>'user_id', '?')
             || ' (' || (v_canais->0->>'canais') || ' em ' || (v_canais->0->>'tabela') || ')'
           else '' end;
      begin
        perform public.notify_admin_urgent_push(
          'servidor_carregado', v_msg, 'servidor', v_motivo,
          jsonb_build_object('ocupado_pct', v_ocupado, 'top_pct', v_top_pct,
                             'top_vezes', v_top.vezes, 'canais_top', v_canais),
          '/admin/vigia-servidor');
        update public.vigia_servidor_estado set ultimo_alerta_em = v_agora where id = 1;
      exception when others then
        raise notice '_cron_vigia_servidor: aviso falhou: %', sqlerrm;
      end;
    end if;

    insert into public.vigia_servidor_registos
      (intervalo_s, ocupado_pct, top_pct, top_papel, top_vezes, top_media_ms, top_consulta,
       canais_top, alertou, motivo)
    values
      (round((v_int_ms / 1000)::numeric), v_ocupado, v_top_pct, v_top.rolname, v_top.vezes,
       case when coalesce(v_top.vezes, 0) > 0 then round((v_top.ms / v_top.vezes)::numeric, 1) end,
       left(regexp_replace(coalesce(v_top.query, ''), '\s+', ' ', 'g'), 300),
       v_canais, v_msg is not null, v_motivo);
  end if;

  -- nova fotografia
  delete from public.vigia_servidor_foto where true;
  insert into public.vigia_servidor_foto (queryid, userid, dbid, total_ms, calls)
    select queryid, userid, dbid, total_ms, calls from _vs_agora;
  update public.vigia_servidor_estado set tirada_em = v_agora where id = 1;

  delete from public.vigia_servidor_registos where criado_em < now() - interval '14 days';
end
$fn$;
revoke all on function public._cron_vigia_servidor() from public, anon, authenticated;

-- Painel admin (PT-BR): últimos registos da vigia. Só admin.
create or replace function public.admin_vigia_servidor(p_horas int default 24)
returns setof public.vigia_servidor_registos
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_admin() then
    raise exception 'só admin' using errcode = '42501';
  end if;
  return query
    select * from public.vigia_servidor_registos
     where criado_em > now() - make_interval(hours => greatest(1, least(coalesce(p_horas, 24), 336)))
     order by criado_em desc
     limit 500;
end
$fn$;
revoke all on function public.admin_vigia_servidor(int) from public, anon;
grant execute on function public.admin_vigia_servidor(int) to authenticated;

select cron.schedule('vigia-servidor', '2-59/5 * * * *', 'select public._cron_vigia_servidor();');
