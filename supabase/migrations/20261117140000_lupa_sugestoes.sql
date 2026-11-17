-- Missão lupa-sugestoes-17-11, BLOCO 1. APLICA A CLAUDE.AI (a trava do PC não deixa).
-- Guia: docs/propostas/lupa-sugestoes-2026-11-17/APLICAR.md
--
-- O que o Danilo pediu (17/11 08:41): "se a pessoa coloca a letra A, aparece lá as opções que tem na
-- loja, sem carregar o servidor. Como é que os grandes fazem."
-- Como a Uber Eats / Glovo fazem: com 1-2 letras NÃO se pesquisa no catálogo inteiro; lê-se uma
-- lista pequena, já pronta, de "sugestões" (palavras do catálogo, produtos mais pedidos, secções e
-- lojas), procurada pelo começo do texto num índice. Custa um salto no índice + ordenar umas
-- centenas de linhas (< 10 ms), em vez de 63 mil produtos.
--
-- Peças:
--   * lupa_norm(texto)          minúsculas, sem acentos, só letras/algarismos/espaços.
--   * lupa_sugestoes            3-5 mil linhas, FORA do tempo real (não entra na publicação realtime).
--                               restaurant_id null = lupa geral (página inicial); senão só a lupa
--                               dessa loja. loja_origem = loja de onde vem a linha (para esconder as
--                               lojas escondidas a quem não as vê, como products_lista_permissao).
--   * lupa_sugestoes(p_q, p_restaurant_id)  RPC para a app: 8 melhores pelo começo do texto.
--   * lupa_sugestoes_recalcular()           reconstrução em lote; PARA se o vigia passar 50%.
--   * pg_cron 'lupa-sugestoes' de 5 em 5 min: só recalcula se passou ~1 hora ou se uma loja mudou.
--   * gatilho leve em restaurants: loja desaprovada/desligada sai já das sugestões; qualquer
--     mudança de aprovação/escondida/nome marca "recalcular" (feito no máximo 5 min depois).
--   * admin_lupa_sugestoes_* para o ecrã "Sugestões da lupa" do painel.
--   * platform_settings.lupa_sugestoes_enabled (nasce ligado).
--
-- Regras de visibilidade (iguais às de products):
--   * prémios do check-in (id 'premio-checkin-%') nunca entram;
--   * lojas escondidas (so_lista_permissao): as palavras GERAIS saem só das lojas NÃO escondidas;
--     as linhas da própria loja (palavras, produtos, secções, a loja) levam loja_origem e a RPC
--     tira-as com lojas_escondidas_para_mim() — o dono, quem está na lista e o admin continuam a vê-las;
--   * só lojas aprovadas e ligadas pelo admin (approval_status='approved', is_active_admin).
--
-- Como voltar atrás: ver APLICAR.md (desligar lupa_sugestoes_enabled chega para a app voltar ao de
-- hoje; para tirar tudo: cron.unschedule('lupa-sugestoes'), drop trigger, drop das funções e tabelas).

-- 1. Normalização (a mesma na tabela e na pesquisa)
create or replace function public.lupa_norm(p_texto text)
returns text
language sql
immutable parallel safe
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select btrim(regexp_replace(
           lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_texto, ''))),
           '[^a-z0-9]+', ' ', 'g'))
$$;

-- 2. Tabelas
create table if not exists public.lupa_sugestoes (
  id                bigint generated always as identity primary key,
  texto             text not null,
  texto_normalizado text not null,
  tipo              text not null check (tipo in ('palavra', 'produto', 'seccao', 'loja')),
  restaurant_id     text null,
  ref               text null,
  loja_origem       text null,
  peso              real not null default 0,
  escondida         boolean not null default false,
  atualizado_em     timestamptz not null default now()
);
comment on table public.lupa_sugestoes is
  'Sugestões da lupa (1-2 letras). restaurant_id null = lupa geral; ref = produto/loja/secção a abrir; loja_origem = loja de onde vem (lojas escondidas); escondida = o admin escondeu (o recálculo não desfaz). Fora do tempo real.';

create unique index if not exists lupa_sugestoes_chave
  on public.lupa_sugestoes ((coalesce(restaurant_id, '')), tipo, texto_normalizado);
-- índice por prefixo: "texto_normalizado começa por X" lê-se como intervalo [X, X||'{') no índice
create index if not exists lupa_sugestoes_prefixo
  on public.lupa_sugestoes (restaurant_id, texto_normalizado text_pattern_ops);
create index if not exists lupa_sugestoes_loja_origem
  on public.lupa_sugestoes (loja_origem) where loja_origem is not null;

alter table public.lupa_sugestoes enable row level security;
revoke all on public.lupa_sugestoes from anon, authenticated;

create table if not exists public.lupa_sugestoes_estado (
  id                integer primary key default 1 check (id = 1),
  ultimo_recalculo  timestamptz,
  pendente          boolean not null default true,
  ultimo_resultado  jsonb
);
insert into public.lupa_sugestoes_estado (id) values (1) on conflict (id) do nothing;
alter table public.lupa_sugestoes_estado enable row level security;
revoke all on public.lupa_sugestoes_estado from anon, authenticated;

-- 3. Interruptor (nasce ligado)
insert into public.platform_settings (key, value, description, category)
values ('lupa_sugestoes_enabled', 'true'::jsonb,
        'Sugestões da lupa desde a 1.ª letra (palavras, produtos, secções e lojas). Desligado: a lupa volta a esperar 3 letras.',
        'pesquisa')
on conflict (key) do nothing;

-- 4. Reconstrução em lote
create or replace function public.lupa_sugestoes_recalcular(p_forcar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_ocupado numeric;
  v_ins     integer;
  v_del     integer;
  v_res     jsonb;
  v_t0      timestamptz := clock_timestamp();
begin
  if not coalesce(p_forcar, false) then
    select r.ocupado_pct into v_ocupado
      from public.vigia_servidor_registos r
     where r.criado_em > now() - interval '6 minutes'
     order by r.id desc
     limit 1;
    if coalesce(v_ocupado, 0) > 50 then
      v_res := jsonb_build_object('parado', true, 'motivo', 'servidor ocupado', 'ocupado_pct', v_ocupado, 'em', now());
      update public.lupa_sugestoes_estado set ultimo_resultado = v_res where id = 1;
      return v_res;
    end if;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('lupa_sugestoes_recalcular')) then
    return jsonb_build_object('parado', true, 'motivo', 'já está a correr');
  end if;

  create temp table if not exists _lupa_novas (
    texto text, texto_normalizado text, tipo text, restaurant_id text, ref text, loja_origem text, peso real
  ) on commit drop;
  truncate pg_temp._lupa_novas;

  insert into pg_temp._lupa_novas (texto, texto_normalizado, tipo, restaurant_id, ref, loja_origem, peso)
  with
  lojas as (
    select r.id, r.name, coalesce(r.so_lista_permissao, false) as escondida, coalesce(r.is_partner, false) as parceira
      from public.restaurants r
     where r.approval_status = 'approved' and coalesce(r.is_active_admin, true)
  ),
  -- palavras dos nomes das lojas não são "palavras" (a loja já aparece como loja)
  nomes_lojas as (
    select distinct w from lojas l, regexp_split_to_table(public.lupa_norm(l.name), ' ') w where length(w) >= 4
  ),
  prods as (
    select p.id, p.name, p.restaurant_id, p.category_root, coalesce(p.is_popular, false) as popular, l.escondida
      from public.products p
      join lojas l on l.id = p.restaurant_id
     where p.is_available and p.id !~~ 'premio-checkin-%'
  ),
  pedidos as (
    select e->>'productId' as pid, count(distinct o.id) as n
      from public.orders o
      cross join lateral jsonb_array_elements(case when jsonb_typeof(o.items) = 'array' then o.items else '[]'::jsonb end) e
     where o.created_at > now() - interval '90 days'
       and o.status not in ('cancelled', 'rejected')
     group by 1
  ),
  sem_res as (
    select distinct public.lupa_norm(s.termo) as tn
      from public.pesquisa_sem_resultado s
     where s.resolvido_em is null
  ),
  escolhas as (
    select public.lupa_norm(e.termo) as tn, e.restaurant_id, min(e.termo) as termo, count(*) as n
      from public.pesquisa_escolhas e
     where e.criado_em > now() - interval '90 days'
     group by 1, 2
  ),
  pal as (
    select pr.restaurant_id, pr.escondida, pr.id as pid, x.w, x.o
      from prods pr
      cross join lateral regexp_split_to_table(lower(pr.name), '[^[:alpha:][:digit:]]+') with ordinality x(w, o)
     where x.w <> ''
  ),
  -- cada palavra diferente normaliza-se UMA vez (medido 17/11: 2,5 s em vez de 15,3 s por produto)
  mapa as materialized (
    select d.w, d.wn, btrim(public.bora_ns(d.wn)) as k
      from (select u.w, public.lupa_norm(u.w) as wn from (select distinct pal.w from pal) u) d
     where length(d.wn) >= 3 and d.wn !~ '^[0-9]' and strpos(d.wn, ' ') = 0
       and d.wn not in (select nl.w from nomes_lojas nl)
       and d.wn not in ('com','sem','para','por','pelo','pela','das','dos','nas','nos','uma','uns','umas',
                        'que','the','and','with','mais','tipo','emb','pack','unid','und','uni','grs','kgs',
                        'lts','ltr','litro','litros','quilo','quilos','kilo','embalagem','unidade','unidades',
                        'cada','aprox','ref')
  ),
  ok as (
    select pal.restaurant_id, pal.escondida, pal.pid, pal.w, pal.o, m.wn, m.k
      from pal join mapa m on m.w = pal.w
  ),
  pal_geral as (
    select ok.k, mode() within group (order by ok.w) as disp,
           count(distinct ok.pid) as n, count(distinct ok.pid) filter (where ok.o = 1) as n1,
           coalesce(sum(pe.n), 0) as ped
      from ok left join pedidos pe on pe.pid = ok.pid
     where not ok.escondida
     group by ok.k
    having count(distinct ok.pid) >= 2
  ),
  pal_loja as (
    select z.* from (
      select ok.restaurant_id, ok.k, mode() within group (order by ok.w) as disp,
             count(distinct ok.pid) as n, count(distinct ok.pid) filter (where ok.o = 1) as n1,
             coalesce(sum(pe.n), 0) as ped,
             row_number() over (partition by ok.restaurant_id
                                order by ln(1 + 2 * count(distinct ok.pid) filter (where ok.o = 1)
                                            + 0.5 * count(distinct ok.pid)) desc, ok.k) as rk
        from ok left join pedidos pe on pe.pid = ok.pid
       group by ok.restaurant_id, ok.k
    ) z where z.rk <= 120
  ),
  prod_peso as (
    select pr.id, pr.name, pr.restaurant_id, pr.popular, coalesce(pe.n, 0) as ped,
           (3 + 2 * ln(1 + coalesce(pe.n, 0)) + case when pr.popular then 0.5 else 0 end)::real as peso
      from prods pr left join pedidos pe on pe.pid = pr.id
     where coalesce(pe.n, 0) > 0 or pr.popular
  ),
  sec_loja as (
    select s.restaurant_id, s.category_root, count(pr.id) as n
      from public.seccoes_disponiveis s
      join lojas l on l.id = s.restaurant_id
      left join prods pr on pr.restaurant_id = s.restaurant_id and pr.category_root = s.category_root
     where not s.premio and coalesce(s.category_root, '') <> ''
     group by 1, 2
  )
  -- palavras da lupa geral (só lojas não escondidas)
  select upper(left(g.disp, 1)) || substr(g.disp, 2), public.lupa_norm(g.disp), 'palavra', null, null, null,
         (ln(1 + 2 * g.n1 + 0.5 * g.n) + 1.5 * ln(1 + g.ped))::real
    from (select * from pal_geral order by ln(1 + 2 * n1 + 0.5 * n) desc limit 1500) g
  union all
  -- palavras de cada loja
  select upper(left(pl.disp, 1)) || substr(pl.disp, 2), public.lupa_norm(pl.disp), 'palavra', pl.restaurant_id,
         null, pl.restaurant_id, (ln(1 + 2 * pl.n1 + 0.5 * pl.n) + 1.5 * ln(1 + pl.ped))::real
    from pal_loja pl
  union all
  -- o que as pessoas procuraram e escolheram (na loja e na lupa geral)
  select upper(left(e.termo, 1)) || substr(e.termo, 2), e.tn, 'palavra', e.restaurant_id, null, e.restaurant_id,
         (6 + 2 * ln(1 + e.n))::real
    from escolhas e
   where length(e.tn) >= 2 and e.tn not in (select sr.tn from sem_res sr)
     and (e.restaurant_id is null or e.restaurant_id in (select l.id from lojas l))
  union all
  select upper(left(e.termo, 1)) || substr(e.termo, 2), e.tn, 'palavra', null, null, e.restaurant_id,
         (6 + 2 * ln(1 + e.n))::real
    from escolhas e
   where e.restaurant_id is not null and length(e.tn) >= 2 and e.tn not in (select sr.tn from sem_res sr)
     and e.restaurant_id in (select l.id from lojas l)
  union all
  -- produtos mais pedidos / populares de cada loja (30 por loja)
  select z.name, public.lupa_norm(z.name), 'produto', z.restaurant_id, z.id, z.restaurant_id, z.peso
    from (select pp.*, row_number() over (partition by pp.restaurant_id order by pp.ped desc, pp.popular desc, pp.name) as rk
            from prod_peso pp) z
   where z.rk <= 30
  union all
  -- produtos mais pedidos na lupa geral (200)
  select z.name, public.lupa_norm(z.name), 'produto', null, z.id, z.restaurant_id, z.peso
    from (select pp.* from prod_peso pp order by pp.ped desc, pp.popular desc, pp.name limit 200) z
  union all
  -- secções de cada loja
  select upper(left(sl.category_root, 1)) || substr(sl.category_root, 2), public.lupa_norm(sl.category_root), 'seccao',
         sl.restaurant_id, sl.category_root, sl.restaurant_id, (5 + ln(1 + sl.n))::real
    from sec_loja sl
  union all
  -- secções na lupa geral (só de lojas não escondidas)
  select upper(left(min(sl.category_root), 1)) || substr(min(sl.category_root), 2), public.lupa_norm(sl.category_root),
         'seccao', null, min(sl.category_root), null, (4 + ln(1 + count(distinct sl.restaurant_id)))::real
    from sec_loja sl
    join lojas l on l.id = sl.restaurant_id and not l.escondida
   group by public.lupa_norm(sl.category_root)
  union all
  -- as lojas (lupa geral)
  select l.name, public.lupa_norm(l.name), 'loja', null, l.id, l.id,
         (9 + case when l.parceira then 0.5 else 0 end)::real
    from lojas l;

  insert into public.lupa_sugestoes as s
         (texto, texto_normalizado, tipo, restaurant_id, ref, loja_origem, peso, atualizado_em)
  select distinct on (coalesce(n.restaurant_id, ''), n.tipo, n.texto_normalizado)
         n.texto, n.texto_normalizado, n.tipo, n.restaurant_id, n.ref, n.loja_origem, n.peso, now()
    from pg_temp._lupa_novas n
   where n.texto_normalizado <> '' and n.texto is not null
   order by coalesce(n.restaurant_id, ''), n.tipo, n.texto_normalizado, n.peso desc
  on conflict ((coalesce(restaurant_id, '')), tipo, texto_normalizado) do update
     set texto = excluded.texto, ref = excluded.ref, loja_origem = excluded.loja_origem,
         peso = excluded.peso, atualizado_em = excluded.atualizado_em;
  get diagnostics v_ins = row_count;

  -- o que já não sai do catálogo vai embora (as que o admin escondeu ficam, para não voltarem)
  delete from public.lupa_sugestoes s where s.atualizado_em < now() and not s.escondida;
  get diagnostics v_del = row_count;

  v_res := jsonb_build_object('parado', false, 'escritas', v_ins, 'removidas', v_del,
                              'total', (select count(*) from public.lupa_sugestoes),
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                              'em', now());
  update public.lupa_sugestoes_estado
     set ultimo_recalculo = now(), pendente = false, ultimo_resultado = v_res
   where id = 1;
  return v_res;
end
$$;
revoke all on function public.lupa_sugestoes_recalcular(boolean) from public, anon, authenticated;

-- 5. A RPC da app
create or replace function public.lupa_sugestoes(p_q text, p_restaurant_id text default null)
returns table(texto text, tipo text, ref text, restaurant_id text)
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
#variable_conflict use_column
declare
  v_q   text := left(public.lupa_norm(p_q), 60);
  v_fim text;
  v_esc text[];
begin
  if v_q = '' then return; end if;
  if exists (select 1 from public.platform_settings ps
              where ps.key = 'lupa_sugestoes_enabled'
                and lower(coalesce(ps.value #>> '{}', '')) in ('false', '0', 'off')) then
    return;
  end if;
  v_esc := coalesce(public.lojas_escondidas_para_mim(), '{}'::text[]);
  if p_restaurant_id is not null and p_restaurant_id = any (v_esc) then return; end if;
  v_fim := v_q || '{';  -- '{' vem logo a seguir a 'z': [v_q, v_fim) = tudo o que começa por v_q

  if p_restaurant_id is null then
    return query
    select z.texto, z.tipo, z.ref, z.loja
      from (select distinct on (s.texto_normalizado)
                   s.texto, s.tipo, s.ref, coalesce(s.restaurant_id, s.loja_origem) as loja, s.peso
              from public.lupa_sugestoes s
             where s.restaurant_id is null
               and s.texto_normalizado ~>=~ v_q and s.texto_normalizado ~<~ v_fim
               and not s.escondida
               and (s.loja_origem is null or not (s.loja_origem = any (v_esc)))
             order by s.texto_normalizado,
                      case s.tipo when 'loja' then 0 when 'seccao' then 1 when 'produto' then 2 else 3 end,
                      s.peso desc) z
     order by z.peso desc, z.texto
     limit 8;
  else
    return query
    select z.texto, z.tipo, z.ref, z.loja
      from (select distinct on (s.texto_normalizado)
                   s.texto, s.tipo, s.ref, coalesce(s.restaurant_id, s.loja_origem) as loja, s.peso
              from public.lupa_sugestoes s
             where s.restaurant_id = p_restaurant_id
               and s.texto_normalizado ~>=~ v_q and s.texto_normalizado ~<~ v_fim
               and not s.escondida
               and (s.loja_origem is null or not (s.loja_origem = any (v_esc)))
             order by s.texto_normalizado,
                      case s.tipo when 'loja' then 0 when 'seccao' then 1 when 'produto' then 2 else 3 end,
                      s.peso desc) z
     order by z.peso desc, z.texto
     limit 8;
  end if;
end
$$;
grant execute on function public.lupa_sugestoes(text, text) to anon, authenticated, service_role;

-- 6. De hora a hora (e 5 min depois de uma loja mudar)
create or replace function public.lupa_sugestoes_cron()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_e public.lupa_sugestoes_estado;
begin
  select * into v_e from public.lupa_sugestoes_estado where id = 1;
  if v_e.id is null or v_e.pendente or v_e.ultimo_recalculo is null
     or v_e.ultimo_recalculo < now() - interval '55 minutes' then
    perform public.lupa_sugestoes_recalcular(false);
  end if;
end
$$;
revoke all on function public.lupa_sugestoes_cron() from public, anon, authenticated;

select cron.schedule('lupa-sugestoes', '3-59/5 * * * *', $$select public.lupa_sugestoes_cron()$$);

-- 7. Gatilho leve: loja desaprovada / desligada sai já; o resto marca "recalcular"
create or replace function public.lupa_sugestoes_loja_mudou()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.approval_status is distinct from 'approved' or not coalesce(new.is_active_admin, true) then
    delete from public.lupa_sugestoes s
     where (s.restaurant_id = new.id or s.loja_origem = new.id) and not s.escondida;
  end if;
  update public.lupa_sugestoes_estado set pendente = true where id = 1;
  return null;
end
$$;

drop trigger if exists lupa_sugestoes_loja on public.restaurants;
create trigger lupa_sugestoes_loja
  after update of approval_status, is_active_admin, so_lista_permissao, name on public.restaurants
  for each row
  when (old.approval_status is distinct from new.approval_status
        or old.is_active_admin is distinct from new.is_active_admin
        or old.so_lista_permissao is distinct from new.so_lista_permissao
        or old.name is distinct from new.name)
  execute function public.lupa_sugestoes_loja_mudou();

-- 8. Painel admin
create or replace function public.admin_lupa_sugestoes_listar(
  p_q text default null, p_tipo text default null, p_restaurant_id text default null,
  p_so_geral boolean default false, p_limit integer default 100, p_offset integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare v_q text := nullif(public.lupa_norm(p_q), '');
begin
  if not coalesce(public.is_admin(), false) then raise exception 'admin_required'; end if;
  return jsonb_build_object(
    'ligado', not exists (select 1 from public.platform_settings ps
                           where ps.key = 'lupa_sugestoes_enabled'
                             and lower(coalesce(ps.value #>> '{}', '')) in ('false', '0', 'off')),
    'estado', (select to_jsonb(e) from public.lupa_sugestoes_estado e where e.id = 1),
    'contagem', (select coalesce(jsonb_object_agg(z.tipo, z.n), '{}'::jsonb)
                   from (select s.tipo, count(*) as n from public.lupa_sugestoes s group by s.tipo) z),
    'total', (select count(*) from public.lupa_sugestoes s
               where (v_q is null or s.texto_normalizado like v_q || '%')
                 and (p_tipo is null or s.tipo = p_tipo)
                 and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
                 and (not coalesce(p_so_geral, false) or s.restaurant_id is null)),
    'linhas', (select coalesce(jsonb_agg(to_jsonb(z) order by z.peso desc, z.texto), '[]'::jsonb) from (
                 select s.id, s.texto, s.tipo, s.restaurant_id, r.name as loja_nome, s.ref,
                        s.loja_origem, round(s.peso::numeric, 2) as peso, s.escondida, s.atualizado_em
                   from public.lupa_sugestoes s
                   left join public.restaurants r on r.id = coalesce(s.restaurant_id, s.loja_origem)
                  where (v_q is null or s.texto_normalizado like v_q || '%')
                    and (p_tipo is null or s.tipo = p_tipo)
                    and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
                    and (not coalesce(p_so_geral, false) or s.restaurant_id is null)
                  order by s.peso desc, s.texto
                  limit greatest(1, least(coalesce(p_limit, 100), 500))
                 offset greatest(0, coalesce(p_offset, 0))) z)
  );
end
$$;
grant execute on function public.admin_lupa_sugestoes_listar(text, text, text, boolean, integer, integer) to authenticated;

create or replace function public.admin_lupa_sugestoes_recalcular()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_res jsonb;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'admin_required'; end if;
  v_res := public.lupa_sugestoes_recalcular(false);
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'lupa_sugestoes_recalcular', 'lupa_sugestoes', 'todas', v_res);
  return v_res;
end
$$;
grant execute on function public.admin_lupa_sugestoes_recalcular() to authenticated;

create or replace function public.admin_lupa_sugestoes_esconder(p_id bigint, p_escondida boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_texto text;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'admin_required'; end if;
  update public.lupa_sugestoes s set escondida = coalesce(p_escondida, true)
   where s.id = p_id
  returning s.texto into v_texto;
  if v_texto is null then raise exception 'sugestao_nao_existe'; end if;
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), case when coalesce(p_escondida, true) then 'lupa_sugestao_esconder' else 'lupa_sugestao_mostrar' end,
          'lupa_sugestoes', p_id::text, jsonb_build_object('texto', v_texto));
  return jsonb_build_object('id', p_id, 'texto', v_texto, 'escondida', coalesce(p_escondida, true));
end
$$;
grant execute on function public.admin_lupa_sugestoes_esconder(bigint, boolean) to authenticated;

-- 9. Primeiro enchimento (respeita os 50% do vigia; se parar, o cron enche nos 5 min seguintes)
select public.lupa_sugestoes_recalcular(false);
