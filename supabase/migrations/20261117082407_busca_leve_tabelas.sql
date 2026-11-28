-- Missão servidor-busca-leve-2026-11-17, bloco B1 (1.1, 1.2 e 1.4). Preparada pelo Claude Code no
-- ramo ai/2026-11-17-busca-leve; APLICA A CLAUDE.AI (a trava do modo automático não deixa o executor
-- aplicar migrações em produção). Ordem e provas: docs/propostas/busca-leve-2026-11-17/APLICAR.md.
--
-- Esta migração NÃO muda resultado nenhum: só cria funções, duas tabelas pequenas e gatilhos.
-- A pesquisa só passa a usá-las na migração seguinte (20261117100100_busca_leve_pesquisa.sql).
--
-- Porquê: em cada pesquisa, pesquisa_produtos refazia ~12 regex sobre o nome e a categoria de cada
-- candidato (CTE catn/cn/fzc). Medido a 17/11 07:40 no plano de "frango" (4110 candidatos depois dos
-- sinónimos): ~215 ms de 462 ms só nisso. E search_products fazia DISTINCT nos ~51 mil produtos
-- disponíveis em cada pesquisa (~33 ms, mesmo com 2 letras).
--
-- products está na publicação supabase_realtime: NADA aqui faz UPDATE em products. As tabelas novas
-- ficam fora do tempo real (a publicação não é FOR ALL TABLES: puballtables=false, lido a 17/11).

-- 1.1 ---------------------------------------------------------------------------------------------
-- bora_ns: EXATAMENTE a expressão "ns" de pesquisa_produtos (cn, catn e fzc), com o argumento no
-- lugar de c.name / k.category / p.name. Mesmo texto, carácter a carácter (prova em
-- supabase/tests/busca_leve_igualdade.sql, parte 1).
create or replace function public.bora_ns(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ')
$$;

-- bora_nr: EXATAMENTE a expressão "nr" de pesquisa_produtos (o nome tal como foi escrito, só sem
-- acentos e com espaços à volta).
create or replace function public.bora_nr(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select (' ' || regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g') || ' ')
$$;

-- pesquisa_produtos é SECURITY INVOKER e chama-as (no caminho de reserva) como quem pesquisa,
-- e a lupa funciona antes do login: por isso anon e authenticated executam.
revoke all on function public.bora_ns(text) from public;
revoke all on function public.bora_nr(text) from public;
grant execute on function public.bora_ns(text) to anon, authenticated, service_role;
grant execute on function public.bora_nr(text) to anon, authenticated, service_role;

-- 1.2 ---------------------------------------------------------------------------------------------
-- Nomes normalizados guardados. Além de ns/nr/cs guarda o nome, a categoria e a loja de origem:
--  * nome/categoria: a pesquisa só usa ns/nr/cs se o nome e a categoria guardados forem iguais aos
--    do produto; se não forem (gatilho desligado, linha em falta, etc.) calcula na hora como antes.
--    Assim o resultado é SEMPRE igual ao de hoje, mesmo com a tabela atrasada.
--  * restaurant_id: para as regras de leitura serem as mesmas de products (lojas escondidas).
create table if not exists public.produtos_busca_ns (
  product_id    text primary key
                references public.products(id) on delete cascade on update cascade,
  restaurant_id text,
  nome          text,
  categoria     text,
  ns            text not null,
  nr            text not null,
  cs            text not null,
  atualizado_em timestamptz not null default now()
);

comment on table public.produtos_busca_ns is
  'Nome e categoria de cada produto já normalizados para a lupa (bora_ns/bora_nr). Mantida por '
  'gatilho em products e acertada de 5 em 5 min (busca_leve_reconciliar). Fora do tempo real. '
  'Missão servidor-busca-leve-2026-11-17.';

-- Leitura: as MESMAS regras de products para SELECT (products_public_read + as 3 restritivas:
-- lojas escondidas e prémios do check-in). Escolhi isto em vez de uma função SECURITY DEFINER porque
-- pesquisa_produtos tem de continuar SECURITY INVOKER (a visibilidade de products é por pessoa) e
-- uma tabela aberta a todos mostraria nomes de produtos de lojas escondidas. Se as regras de leitura
-- de products mudarem, mudam também aqui (e em seccoes_disponiveis).
alter table public.produtos_busca_ns enable row level security;
revoke all on public.produtos_busca_ns from anon, authenticated;
grant select on public.produtos_busca_ns to anon, authenticated;
grant all on public.produtos_busca_ns to service_role;

drop policy if exists produtos_busca_ns_ler on public.produtos_busca_ns;
create policy produtos_busca_ns_ler on public.produtos_busca_ns
  for select to anon, authenticated using (true);

drop policy if exists produtos_busca_ns_lista_permissao on public.produtos_busca_ns;
create policy produtos_busca_ns_lista_permissao on public.produtos_busca_ns
  as restrictive for select to anon, authenticated
  using (not (restaurant_id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

drop policy if exists produtos_busca_ns_premio_anon on public.produtos_busca_ns;
create policy produtos_busca_ns_premio_anon on public.produtos_busca_ns
  as restrictive for select to anon
  using (product_id !~~ 'premio-checkin-%');

drop policy if exists produtos_busca_ns_premio on public.produtos_busca_ns;
create policy produtos_busca_ns_premio on public.produtos_busca_ns
  as restrictive for select to authenticated
  using ((product_id !~~ 'premio-checkin-%') or (select public.is_admin()));

-- Gatilho: quando um produto nasce, ou muda de nome, categoria ou loja, a linha acompanha.
-- WHEN em vez de "UPDATE OF": os gatilhos BEFORE de products podem mexer no nome/categoria e o
-- "UPDATE OF" só olha para as colunas escritas no UPDATE. Mudança de preço não chama nada.
-- SECURITY DEFINER: quem edita o produto (parceiro, admin) não tem escrita nesta tabela.
create or replace function public.produtos_busca_ns_manter()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
begin
  insert into public.produtos_busca_ns as b
         (product_id, restaurant_id, nome, categoria, ns, nr, cs, atualizado_em)
  values (new.id, new.restaurant_id, new.name, new.category,
          public.bora_ns(new.name), public.bora_nr(new.name), public.bora_ns(new.category), now())
  on conflict (product_id) do update
     set restaurant_id = excluded.restaurant_id,
         nome          = excluded.nome,
         categoria     = excluded.categoria,
         ns            = excluded.ns,
         nr            = excluded.nr,
         cs            = excluded.cs,
         atualizado_em = excluded.atualizado_em;
  return null;
end
$$;
revoke all on function public.produtos_busca_ns_manter() from public, anon, authenticated;

drop trigger if exists trg_products_busca_ns_ins on public.products;
create trigger trg_products_busca_ns_ins
  after insert on public.products
  for each row execute function public.produtos_busca_ns_manter();

drop trigger if exists trg_products_busca_ns_upd on public.products;
create trigger trg_products_busca_ns_upd
  after update on public.products
  for each row
  when (old.name is distinct from new.name
        or old.category is distinct from new.category
        or old.restaurant_id is distinct from new.restaurant_id)
  execute function public.produtos_busca_ns_manter();

-- Preencher / acertar em lotes. Insere as linhas que faltam e corrige as desatualizadas, no máximo
-- p_lote por lote, com pausa entre lotes, e PARA se o último registo do vigia (últimos 6 min) passar
-- de 50%. Devolve quantas linhas escreveu. Preenchimento inicial: ver APLICAR.md.
create or replace function public.produtos_busca_ns_preencher(
  p_lote integer default 2000,
  p_max_lotes integer default 1,
  p_pausa_s numeric default 0.2)
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_lote    integer := greatest(1, least(coalesce(p_lote, 2000), 10000));
  v_lotes   integer := greatest(1, least(coalesce(p_max_lotes, 1), 100));
  v_pausa   numeric := greatest(0, least(coalesce(p_pausa_s, 0.2), 5));
  v_total   integer := 0;
  v_n       integer;
  v_ocupado numeric;
begin
  for i in 1..v_lotes loop
    select r.ocupado_pct into v_ocupado
      from public.vigia_servidor_registos r
     where r.criado_em > now() - interval '6 minutes'
     order by r.id desc
     limit 1;
    if coalesce(v_ocupado, 0) > 50 then
      raise notice 'produtos_busca_ns_preencher: servidor a % por cento, paro no lote %', v_ocupado, i;
      exit;
    end if;

    insert into public.produtos_busca_ns as b
           (product_id, restaurant_id, nome, categoria, ns, nr, cs, atualizado_em)
    select p.id, p.restaurant_id, p.name, p.category,
           public.bora_ns(p.name), public.bora_nr(p.name), public.bora_ns(p.category), now()
      from public.products p
      left join public.produtos_busca_ns x on x.product_id = p.id
     where x.product_id is null
        or x.nome is distinct from p.name
        or x.categoria is distinct from p.category
        or x.restaurant_id is distinct from p.restaurant_id
     order by p.id
     limit v_lote
    on conflict (product_id) do update
       set restaurant_id = excluded.restaurant_id,
           nome          = excluded.nome,
           categoria     = excluded.categoria,
           ns            = excluded.ns,
           nr            = excluded.nr,
           cs            = excluded.cs,
           atualizado_em = excluded.atualizado_em;
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;
    exit when v_n < v_lote;
    perform pg_sleep(v_pausa);
  end loop;
  return v_total;
end
$$;
revoke all on function public.produtos_busca_ns_preencher(integer, integer, numeric) from public, anon, authenticated;

-- 1.4 ---------------------------------------------------------------------------------------------
-- Secções com produtos disponíveis, por loja. search_products passa a ler daqui (390 linhas) em vez
-- de fazer DISTINCT nos ~51 mil produtos em cada pesquisa. "premio" separa as secções que só existem
-- por causa de produtos do prémio do check-in (escondidos a anon e a quem não é admin, como em
-- products), para o resultado ser igual para todos os papéis.
create table if not exists public.seccoes_disponiveis (
  restaurant_id text    not null,
  category_root text    not null,
  premio        boolean not null default false,
  primary key (restaurant_id, category_root, premio)
);

comment on table public.seccoes_disponiveis is
  'Pares (loja, secção) com pelo menos um produto disponível. Mantida por gatilho em products e '
  'acertada de 5 em 5 min (busca_leve_reconciliar). Fora do tempo real. Missão servidor-busca-leve-2026-11-17.';

alter table public.seccoes_disponiveis enable row level security;
revoke all on public.seccoes_disponiveis from anon, authenticated;
grant select on public.seccoes_disponiveis to anon, authenticated;
grant all on public.seccoes_disponiveis to service_role;

drop policy if exists seccoes_disponiveis_ler on public.seccoes_disponiveis;
create policy seccoes_disponiveis_ler on public.seccoes_disponiveis
  for select to anon, authenticated using (true);

drop policy if exists seccoes_disponiveis_lista_permissao on public.seccoes_disponiveis;
create policy seccoes_disponiveis_lista_permissao on public.seccoes_disponiveis
  as restrictive for select to anon, authenticated
  using (not (restaurant_id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

drop policy if exists seccoes_disponiveis_premio_anon on public.seccoes_disponiveis;
create policy seccoes_disponiveis_premio_anon on public.seccoes_disponiveis
  as restrictive for select to anon
  using (not premio);

drop policy if exists seccoes_disponiveis_premio on public.seccoes_disponiveis;
create policy seccoes_disponiveis_premio on public.seccoes_disponiveis
  as restrictive for select to authenticated
  using ((not premio) or (select public.is_admin()));

create or replace function public.seccoes_disponiveis_manter()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if tg_op in ('INSERT', 'UPDATE')
     and new.is_available and new.category_root is not null and new.restaurant_id is not null then
    insert into public.seccoes_disponiveis (restaurant_id, category_root, premio)
    values (new.restaurant_id, new.category_root, new.id like 'premio-checkin-%')
    on conflict do nothing;
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and old.is_available and old.category_root is not null and old.restaurant_id is not null then
    -- o gatilho AFTER já vê o estado novo: só sai o par se não sobrar nenhum produto disponível
    if not exists (select 1
                     from public.products p
                    where p.restaurant_id = old.restaurant_id
                      and p.category_root = old.category_root
                      and p.is_available
                      and (p.id like 'premio-checkin-%') = (old.id like 'premio-checkin-%')) then
      delete from public.seccoes_disponiveis s
       where s.restaurant_id = old.restaurant_id
         and s.category_root = old.category_root
         and s.premio = (old.id like 'premio-checkin-%');
    end if;
  end if;
  return null;
end
$$;
revoke all on function public.seccoes_disponiveis_manter() from public, anon, authenticated;

drop trigger if exists trg_products_seccoes_ins on public.products;
create trigger trg_products_seccoes_ins
  after insert on public.products
  for each row
  when (new.is_available and new.category_root is not null)
  execute function public.seccoes_disponiveis_manter();

drop trigger if exists trg_products_seccoes_upd on public.products;
create trigger trg_products_seccoes_upd
  after update on public.products
  for each row
  when (old.is_available is distinct from new.is_available
        or old.category_root is distinct from new.category_root
        or old.restaurant_id is distinct from new.restaurant_id
        or old.id is distinct from new.id)
  execute function public.seccoes_disponiveis_manter();

drop trigger if exists trg_products_seccoes_del on public.products;
create trigger trg_products_seccoes_del
  after delete on public.products
  for each row
  when (old.is_available and old.category_root is not null)
  execute function public.seccoes_disponiveis_manter();

-- Acerto completo (arranque e de 5 em 5 min): junta os pares que faltam e tira os que já não têm
-- produto disponível (corridas raras entre duas edições ao mesmo tempo). Lê os ~51 mil produtos uma
-- vez (~40-65 ms), o que antes se fazia em CADA pesquisa.
create or replace function public.seccoes_disponiveis_reconciliar()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_ins integer;
  v_del integer;
begin
  insert into public.seccoes_disponiveis (restaurant_id, category_root, premio)
  select distinct p.restaurant_id, p.category_root, p.id like 'premio-checkin-%'
    from public.products p
   where p.is_available and p.category_root is not null and p.restaurant_id is not null
  on conflict do nothing;
  get diagnostics v_ins = row_count;

  delete from public.seccoes_disponiveis s
   where not exists (select 1
                       from public.products p
                      where p.restaurant_id = s.restaurant_id
                        and p.category_root = s.category_root
                        and p.is_available
                        and (p.id like 'premio-checkin-%') = s.premio);
  get diagnostics v_del = row_count;
  return v_ins + v_del;
end
$$;
revoke all on function public.seccoes_disponiveis_reconciliar() from public, anon, authenticated;

-- Lote de 5 em 5 min (cron_lote só aceita public.nome() sem argumentos).
create or replace function public.busca_leve_reconciliar()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public.seccoes_disponiveis_reconciliar();
  perform public.produtos_busca_ns_preencher(2000, 1, 0);
end
$$;
revoke all on function public.busca_leve_reconciliar() from public, anon, authenticated;

-- Enchimento inicial das secções (pequeno: ~390 linhas). O dos nomes normalizados (~63 mil linhas)
-- NÃO vai aqui: faz-se em lotes, com o vigia a olhar (APLICAR.md, passo 2).
select public.seccoes_disponiveis_reconciliar();

select cron.schedule('lote-5min-busca', '4-59/5 * * * *',
  $$select public.cron_lote('5min-busca', '{public.busca_leve_reconciliar()}'::text[])$$);
