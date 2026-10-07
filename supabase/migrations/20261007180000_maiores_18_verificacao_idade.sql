-- ════════════════════════════════════════════════════════════════════════════
-- Missão maiores-18 (07/10/2026) — tabaco e álcool com verificação de idade na
-- entrega, igual à Glovo e à Uber Eats. Autorizada pelo Danilo a 07/10 às 17:36.
--
-- Aditiva. NÃO mexe em preços, taxas, carteira, tokens, nem em create_order:
-- o pedido ganha a marca +18 por um gatilho próprio (padrão "trigger aditivo"
-- do PADRAO_BORA §6), que serve todos os caminhos que criam pedidos.
--
-- O que nasce aqui:
--   products.age_restricted                      (marca +18 do produto)
--   orders.has_age_restricted                    (marca do pedido, posta ao nascer)
--   order_age_checks                             (a verificação do estafeta: confirmado | recusado)
--   produto_e_maior_18(...)                      (classificador, só lê)
--   texto_pede_maior_18(text)                    (descrição dos Favores, só lê)
--   trg_products_maior_18_novo                   (produto novo já nasce marcado)
--   trg_orders_maior_18_criacao                  (pedido nasce com a marca)
--   trg_orders_maior_18_guarda                   (sem documento confirmado não há "entregue")
--   driver_confirm_age_check(order, ok)          (o passo do estafeta)
--   admin_* (marcar/desmarcar, em massa, listar) (painel admin)
--
-- Porque a verificação vive numa tabela própria e não em colunas de orders:
-- a tranca do PC (bora-mods, regra 16/09) recusa qualquer SQL com UPDATE em orders,
-- mesmo dentro de uma função oficial. Não se contornou: a verificação é um registo
-- novo (como delivery_pin_attempts e order_receipts_v2) e orders não é escrita aqui.
--
-- Recusa ("não mostrou documento / é menor"): NÃO cria regra de dinheiro nova.
-- Segue o caminho que já existe para cancelar depois da compra: abre um pedido de
-- cancelamento do estafeta (cancellation_requests), o admin aprova e a Edge
-- Function execute-cancellation aplica o escalão after_pickup que já existe.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Cópia de segurança (o que a marcação em massa toca) ──────────────────
create table if not exists public.bkp_products_maior18_20261007 as
  select id, updated_at from public.products;
alter table public.bkp_products_maior18_20261007 enable row level security;

-- ── 1. Colunas e tabela da verificação ──────────────────────────────────────
alter table public.products
  add column if not exists age_restricted boolean not null default false;
alter table public.orders
  add column if not exists has_age_restricted boolean not null default false;

comment on column public.products.age_restricted is
  'Produto para maiores de 18 (tabaco ou bebida alcoólica). Etiqueta +18 no cartão; o estafeta pede documento.';
comment on column public.orders.has_age_restricted is
  'Pedido com produtos +18 (ou Favor de tabaco/álcool). Posto ao nascer pelo gatilho trg_orders_maior_18_criacao.';

create index if not exists idx_products_age_restricted
  on public.products (restaurant_id) where age_restricted;

create table if not exists public.order_age_checks (
  order_id                text primary key references public.orders(id) on delete cascade,
  status                  text not null check (status in ('confirmado', 'recusado')),
  checked_at              timestamptz not null default now(),
  driver_uid              uuid not null,
  order_status_at_check   text,
  service_type            text,
  cancellation_request_id uuid
);
comment on table public.order_age_checks is
  'Missão maiores-18: verificação de idade na entrega (uma por pedido). Só se escreve por driver_confirm_age_check.';
create index if not exists idx_order_age_checks_status
  on public.order_age_checks (status, checked_at desc);

alter table public.order_age_checks enable row level security;
drop policy if exists order_age_checks_admin_select on public.order_age_checks;
create policy order_age_checks_admin_select on public.order_age_checks
  for select to authenticated using (public.is_admin());
drop policy if exists order_age_checks_driver_select on public.order_age_checks;
create policy order_age_checks_driver_select on public.order_age_checks
  for select to authenticated using (driver_uid = auth.uid());
drop policy if exists order_age_checks_client_select on public.order_age_checks;
create policy order_age_checks_client_select on public.order_age_checks
  for select to authenticated using (
    exists (select 1 from public.orders o where o.id = order_age_checks.order_id and o.user_id = auth.uid()));
-- Sem políticas de escrita: só a função driver_confirm_age_check (security definer) escreve.

-- ── 2. Classificador de produtos (só lê) ────────────────────────────────────
create or replace function public.produto_e_maior_18(p_name text, p_category text, p_tax text, p_root text)
returns boolean
language sql
immutable
set search_path = public
as $$
  with v as (
    select lower(coalesce(p_name,'')) n,
           lower(coalesce(p_category,'')) c,
           coalesce(p_tax,'') t,
           lower(coalesce(p_root,'')) r
  ), f as (
    select n, c, t, r,
      -- palavras que só existem em bebida alcoólica
      n ~ '(\mvinhos?\M|\mcervejas?\M|\mcervezas?\M|\mbeer\M|whisk(e)?y\M|vodka|\mgin\M|\mginebra\M|\mrum\M|(?<!-)\mron\M(?!-)|\mlicor(es)?\M|aguardente|aguardiente|baga[cç]o|brandy|conhaque|cognac|tequila|champanhe|champagne|espumante|sangria|\msidras?\M|\mcidra\M|moscatel|verm(u|o)uth|vermute|\mmartini\M|absinto|cacha[cç]a|prosecco|lambrusco|medronho|\mginjas?\M|ginjinha|amarguinha|pachar[aá]n|\mpisco\M|\maperol\M|campari|\mpastis\M|\mricard\M|baileys|beir[aã]o|j[aä]germeister|vinho do porto|\mtawny\M|\mlbv\M|\mporto\M.*(\mruby\M|\d+ ?anos|vintage|reserva|colheita|branco|tinto|ros[eé]))' as forte_nome,
      (t = 'Vinhos & Espirituosas'
         or r ~ '^(.lcool|vinhos e espumantes|bebidas espirituosas|cervejas e sidras)$'
         or c ~ '(\mvinhos?\M|cervej|espirituos|whisk(e)?y|\mgin\M|vodka|\mrum\M|licor|aguardente|champanhe|espumante|sangria|\msidras?\M|cocktails?\M|garrafeira exclusiva|^.lcool)') as forte_cat
    from v
  )
  select case
    -- 1. Tabaco e nicotina (não os ambientadores "anti-tabaco" nem as gomas para deixar de fumar)
    when n ~ '(\mtabaco|\mcigarr(o|os|ilha|ilhas)\M|\mcharutos?\M|\miqos\M|\mheets\M|\mterea\M|\mvapes?\M|nicotina|cigarro eletr)'
         and n !~ '(ambientador|\mvelas?\M|anti[- ]?tabaco|\maroma|\mgomas?\M|pastilh|adesivo|nicotinell|\mspray\M|chocolate|brinquedo|guloseima)'
      then true
    -- 2. Explicitamente sem álcool
    when n ~ '(sem [aá]lcool|sin alcohol|alcohol[ -]?free|non[ -]?alcoholic|(^|[^0-9,.])0[,.]0(?![0-9])|(^|[^0-9,.])0 ?%|(?<!cola )\mzero\M|bock free)'
      then false
    -- 3. Não é bebida, diga o nome o que disser
    when n ~ '(vinagre|\mmolhos?\M|tempero|especiaria|levedura|whiskas|c[aá]psulas?|saca[- ]?rolhas|abridor|decanta|ambientador|\mvelas?\M|sabonete|\mbanho\M|barbear|champ[oô]\M|perfume|col[oó]nia|desodori|iluminador|batom|verniz|\mlego\M|brinquedo|\mra[cç][aã]o\M|frutos secos|desidrat|^caixa|ginger (ale|beer)|cervejeir|\mbomb(om|ons|ons)\M|ballotin|\mgelados?\M|\mbolos?\M|bolacha|biscoit|\mpudim|presunto|chouri|salsich|bacalhau|compota|frigor[ií]fico|\mbaldes?\M|salva[- ]?gotas)'
      then false
    when c ~ '(acess[oó]rios|copos e|/mesa/|casa e jardim|casa, bricolage|bricolage|pintura|drogaria|animais|brinquedos|papelaria|ilumina|roupa|ferramentas|decora|beleza|higiene|cabelo|frutos secos|limpeza|velas|molhos|tempero|medicamentos)'
      then false
    -- 4. O nome diz bebida alcoólica
    when forte_nome then true
    -- 5. A categoria diz bebida alcoólica (excepto petiscos e copos mal arrumados na secção)
    when forte_cat and n !~ '(\mcaju\M|am[eê]ndoa|amendoim|pinh[aã]o|gengibre|\mmanga\M|\mbanana\M|(?<!com )\mcopos?\M|(?<!com )c[aá]lice|\mflutes?\M|(?<!com )ch[aá]venas?)'
      then true
    -- 6. Marcas de bebida alcoólica, só com contexto de bebida (volume, garrafa, lata, pack)
    when n ~ '(\msagres\M|super ?bock|heineken|\mcorona\M|desperados|somersby|carlsberg|guinness|budweiser|stella artois|\mmahou\M|estrella damm|\mcoral\M|bohemia|leffe|hoegaarden|erdinger|\mtagus\M|smirnoff|\mabsolut\M|bacardi|jameson|johnnie walker|jack daniel|famous grouse|chivas|ballantine|\mgordon|bombay|beefeater|tanqueray|eristoff|malibu|macieira|casal garcia|\mmateus\M)'
         and n ~ '(\d+ ?(cl|ml|l|lt|litros?)\M|garrafa|\mlatas?\M|\mpack\M|\mbarril|\mmini\M|long ?neck|\mcaneca|imperial|\mcopo)'
      then true
    else false
  end
  from f;
$$;

comment on function public.produto_e_maior_18(text,text,text,text) is
  'Missão maiores-18 (07/10/2026): diz se um produto é tabaco ou bebida alcoólica, pelo nome e pela categoria. Só lê.';
revoke all on function public.produto_e_maior_18(text,text,text,text) from public, anon;
grant execute on function public.produto_e_maior_18(text,text,text,text) to authenticated, service_role;

-- ── 3. Descrição de um Favor que pede tabaco ou álcool (só lê) ──────────────
create or replace function public.texto_pede_maior_18(p_texto text)
returns boolean
language sql
immutable
set search_path = public
as $$
  with t as (
    select regexp_replace(
             regexp_replace(
               regexp_replace(lower(coalesce(p_texto,'')),
                 'vinagre de (vinho|sidra)', ' ', 'g'),
               '\m(cervejas?|vinhos?|sidras?|espumantes?|bebidas?|gin|sangria)\s+(sem [aá]lcool|0[,.]0\s?%?)', ' ', 'g'),
             '[aá]lcool\s+(et[ií]lico|70|96|gel|desinfe|sanit|para (a |as |os )?(feridas|limpe|desinfe))', ' ', 'g') s
  )
  select s ~ '(\+18|\mtabaco|\mcigarr|\mcharutos?\M|\miqos\M|\mheets\M|\mterea\M|\mvapes?\M|nicotina|marlboro|chesterfield|\mcamel\M|winston|lucky strike|pall mall|davidoff|gauloises|\mventil\M|portugu[eê]s suave|\m[aá]lcool\M|alco[oó]lic|\mcervejas?\M|\mvinhos?\M|whisk(e)?y|vodka|\mgin\M|\mrum\M|\mlicor(es)?\M|aguardente|baga[cç]o|brandy|conhaque|tequila|champanhe|champagne|espumante|sangria|\msidras?\M|moscatel|\mmartini\M|absinto|cacha[cç]a|\msagres\M|super ?bock|heineken|somersby|baileys|beir[aã]o|\mginjas?\M|ginjinha)'
  from t;
$$;

comment on function public.texto_pede_maior_18(text) is
  'Missão maiores-18: a descrição de um Favor fala de tabaco ou álcool? (cerveja sem álcool e álcool etílico não contam). Só lê.';
revoke all on function public.texto_pede_maior_18(text) from public, anon;
grant execute on function public.texto_pede_maior_18(text) to authenticated, service_role;

-- ── 4. Marcação inicial do catálogo (sem mexer no updated_at dos produtos) ──
alter table public.products disable trigger trg_products_set_updated_at;
update public.products
   set age_restricted = true
 where not age_restricted
   and public.produto_e_maior_18(name, category, taxonomy_section, category_root);
alter table public.products enable trigger trg_products_set_updated_at;

-- ── 5. Produto novo (raspagem, parceiro) já nasce marcado ───────────────────
create or replace function public.fn_products_maior_18_novo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not coalesce(new.age_restricted, false) then
    new.age_restricted := public.produto_e_maior_18(new.name, new.category, new.taxonomy_section, new.category_root);
  end if;
  return new;
end;
$$;

create or replace trigger trg_products_maior_18_novo
  before insert on public.products
  for each row execute function public.fn_products_maior_18_novo();

-- ── 6. O pedido nasce com a marca +18 ───────────────────────────────────────
create or replace function public.pedido_tem_produto_maior_18(p_items jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case when jsonb_typeof(p_items) = 'array' then exists (
    select 1
      from jsonb_array_elements(p_items) e
      join public.products p
        on p.id = coalesce(e->>'productId', e->>'product_id')
     where p.age_restricted
  ) else false end;
$$;
revoke all on function public.pedido_tem_produto_maior_18(jsonb) from public, anon;
grant execute on function public.pedido_tem_produto_maior_18(jsonb) to authenticated, service_role;

create or replace function public.fn_orders_maior_18_criacao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.has_age_restricted :=
       public.pedido_tem_produto_maior_18(new.items)
    or (new.service_type = 'errand' and public.texto_pede_maior_18(new.errand_description));
  return new;
exception when others then
  -- Nunca impedir um pedido por causa da marca; fica no registo do Postgres.
  raise warning 'fn_orders_maior_18_criacao (pedido %): %', new.id, sqlerrm;
  return new;
end;
$$;

create or replace trigger trg_orders_maior_18_criacao
  before insert on public.orders
  for each row execute function public.fn_orders_maior_18_criacao();

-- ── 7. Guarda: a marca não se tira, e sem documento confirmado o pedido +18
--       não passa a "entregue" (qualquer caminho: PIN, dinheiro, Favor, fila
--       offline). Só lê; nunca escreve em orders. ───────────────────────────
create or replace function public.fn_orders_maior_18_guarda()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.has_age_restricted is distinct from old.has_age_restricted
     and not coalesce(public.is_admin(), false) then
    raise exception 'AGE_RESTRICTED_PROTECTED: a marca +18 do pedido só a muda um admin'
      using errcode = '42501';
  end if;

  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and coalesce(new.has_age_restricted, false)
     and not exists (select 1 from public.order_age_checks c
                      where c.order_id = new.id and c.status = 'confirmado')
     and not coalesce(public.is_admin(), false) then
    raise exception 'AGE_CHECK_REQUIRED: este pedido tem produtos para maiores de 18. Confirma o documento do cliente antes de entregar.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace trigger trg_orders_maior_18_guarda
  before update on public.orders
  for each row execute function public.fn_orders_maior_18_guarda();

-- ── 8. O passo do estafeta ──────────────────────────────────────────────────
create or replace function public.driver_confirm_age_check(p_order_id text, p_ok boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_order   record;
  v_check   record;
  v_is_mine boolean;
  v_req_id  uuid;
  v_key     text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  if p_ok is null then
    return jsonb_build_object('ok', false, 'error', 'choice_required');
  end if;

  select id, status, assigned_driver_id, has_age_restricted, user_id, service_type
    into v_order from public.orders where id = p_order_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  -- Mesmo critério do driver_validate_delivery_pin (assigned guarda o uid OU o drivers.id).
  v_is_mine := v_order.assigned_driver_id = v_uid::text
    or v_order.assigned_driver_id in (select d.id::text from public.drivers d where d.user_id = v_uid)
    or exists (select 1 from public.drivers d
                where d.id::text = v_order.assigned_driver_id and d.user_id = v_uid);
  if not v_is_mine then
    return jsonb_build_object('ok', false, 'error', 'not_your_order');
  end if;

  if not coalesce(v_order.has_age_restricted, false) then
    return jsonb_build_object('ok', true, 'not_required', true);
  end if;

  select status, checked_at into v_check from public.order_age_checks where order_id = p_order_id;
  if found then
    -- Idempotente: a decisão já foi tomada (outro toque, outro aparelho).
    return jsonb_build_object('ok', true, 'already', true, 'status', v_check.status, 'at', v_check.checked_at);
  end if;

  if v_order.status not in ('pickedUp', 'onTheWay') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'status', v_order.status);
  end if;

  insert into public.order_age_checks (order_id, status, driver_uid, order_status_at_check, service_type)
  values (p_order_id, case when p_ok then 'confirmado' else 'recusado' end, v_uid,
          v_order.status, v_order.service_type)
  on conflict (order_id) do nothing;
  if not found then
    select status, checked_at into v_check from public.order_age_checks where order_id = p_order_id;
    return jsonb_build_object('ok', true, 'already', true, 'status', v_check.status, 'at', v_check.checked_at);
  end if;

  if p_ok then
    return jsonb_build_object('ok', true, 'status', 'confirmado');
  end if;

  -- Recusado: o caminho de cancelamento que já existe depois da compra.
  -- Pedido de cancelamento do estafeta -> o admin aprova -> execute-cancellation (escalão after_pickup).
  begin
    insert into public.cancellation_requests (order_id, requester_role, requester_id, reason, status)
    values (p_order_id, 'driver', v_uid,
            'Verificação de idade recusada: o cliente não mostrou documento ou é menor de 18. Os produtos +18 não foram entregues.',
            'pending')
    returning id into v_req_id;
  exception when unique_violation then
    select id into v_req_id from public.cancellation_requests
     where order_id = p_order_id and status = 'pending' limit 1;
  end;
  update public.order_age_checks set cancellation_request_id = v_req_id where order_id = p_order_id;

  begin
    perform public.notify_admin_event(
      'order_age_check_refused', 'critical',
      format('Pedido #%s não entregue: cliente sem documento ou menor de 18. Falta aprovar o cancelamento.',
             substring(p_order_id, 1, 8)),
      'order', p_order_id,
      jsonb_build_object('cancellation_request_id', v_req_id, 'driver_uid', v_uid,
                         'order_status', v_order.status, 'service_type', v_order.service_type),
      '/admin/cancellations');
  exception when others then
    raise warning 'driver_confirm_age_check: aviso ao admin falhou (%): %', p_order_id, sqlerrm;
  end;

  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_key is not null and v_order.user_id is not null then
      perform net.http_post(
        url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-client',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
        body := jsonb_build_object(
          'clientId', v_order.user_id,
          'orderId',  p_order_id,
          'type',     'age_check_refused',
          'title',    'Pedido não entregue',
          'body',     'O teu pedido tem produtos para maiores de 18 e não foi mostrado um documento válido na entrega. A Bora vai tratar do cancelamento.'));
    end if;
  exception when others then
    raise warning 'driver_confirm_age_check: aviso ao cliente falhou (%): %', p_order_id, sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'status', 'recusado', 'cancellation_request_id', v_req_id);
end;
$$;

comment on function public.driver_confirm_age_check(text, boolean) is
  'Missão maiores-18: o estafeta atribuído confirma (ok=true) ou recusa (ok=false) a idade do cliente na entrega. Recusa abre pedido de cancelamento (caminho já existente).';
revoke all on function public.driver_confirm_age_check(text, boolean) from public, anon;
grant execute on function public.driver_confirm_age_check(text, boolean) to authenticated;

-- ── 9. Painel admin ─────────────────────────────────────────────────────────
create or replace function public.admin_set_product_age_restricted(
  p_product_id text, p_value boolean, p_reason text default 'painel admin')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin record;
  v_old   boolean;
  v_name  text;
begin
  select admin_id, admin_email into v_admin from public._admin_op_guard();
  if p_value is null then
    raise exception 'value_required' using errcode = '23502';
  end if;
  select age_restricted, name into v_old, v_name from public.products where id = p_product_id;
  if not found then
    raise exception 'product_not_found: %', p_product_id using errcode = 'P0002';
  end if;
  if v_old = p_value then
    return jsonb_build_object('success', true, 'no_change', true);
  end if;
  update public.products set age_restricted = p_value where id = p_product_id;
  perform public.log_admin_action('product_age_restricted', 'product', p_product_id,
    jsonb_build_object('name', v_name, 'from', v_old, 'to', p_value,
                       'reason', coalesce(nullif(trim(p_reason), ''), 'painel admin')));
  return jsonb_build_object('success', true, 'product_id', p_product_id, 'age_restricted', p_value);
end;
$$;

create or replace function public.admin_set_age_restricted_by_category(
  p_field text, p_value text, p_age boolean, p_reason text default 'painel admin')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin record;
  v_n     integer;
begin
  select admin_id, admin_email into v_admin from public._admin_op_guard();
  if p_field not in ('taxonomy_section', 'category_root') then
    raise exception 'invalid_field: %', p_field using errcode = '22023';
  end if;
  if p_value is null or p_age is null then
    raise exception 'value_required' using errcode = '23502';
  end if;
  if p_field = 'taxonomy_section' then
    update public.products set age_restricted = p_age
     where taxonomy_section = p_value and age_restricted is distinct from p_age;
  else
    update public.products set age_restricted = p_age
     where category_root = p_value and age_restricted is distinct from p_age;
  end if;
  get diagnostics v_n = row_count;
  perform public.log_admin_action('product_age_restricted_bulk', 'product_category', p_field || '=' || p_value,
    jsonb_build_object('field', p_field, 'value', p_value, 'to', p_age, 'updated', v_n,
                       'reason', coalesce(nullif(trim(p_reason), ''), 'painel admin')));
  return jsonb_build_object('success', true, 'updated', v_n);
end;
$$;

create or replace function public.admin_list_products_maior_18(
  p_search text default null, p_filtro text default 'marcados',
  p_limit integer default 100, p_offset integer default 0)
returns table (
  id text, name text, photo_url text, restaurant_id text, loja text,
  category text, category_root text, taxonomy_section text,
  age_restricted boolean, sugerido boolean, total bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public._admin_op_guard();
  return query
  with base as (
    select p.id, p.name, p.photo_url, p.restaurant_id, r.name as loja,
           p.category, p.category_root, p.taxonomy_section, p.age_restricted,
           public.produto_e_maior_18(p.name, p.category, p.taxonomy_section, p.category_root) as sugerido
      from public.products p
      left join public.restaurants r on r.id = p.restaurant_id
     where (p_search is null or length(trim(p_search)) = 0
            or p.name ilike '%' || trim(p_search) || '%'
            or r.name ilike '%' || trim(p_search) || '%')
  ), filtrada as (
    select * from base b
     where case coalesce(p_filtro, 'marcados')
             when 'marcados'    then b.age_restricted
             when 'desmarcados' then not b.age_restricted
             when 'sugeridos'   then b.sugerido and not b.age_restricted
             else true
           end
  )
  select f.id, f.name, f.photo_url, f.restaurant_id, f.loja, f.category, f.category_root,
         f.taxonomy_section, f.age_restricted, f.sugerido, count(*) over () as total
    from filtrada f
   order by f.name
   limit least(greatest(coalesce(p_limit, 100), 1), 500)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_maior_18_por_categoria()
returns table (taxonomy_section text, category_root text, total bigint, marcados bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public._admin_op_guard();
  return query
  select p.taxonomy_section, p.category_root,
         count(*), count(*) filter (where p.age_restricted)
    from public.products p
   where p.taxonomy_section is not null and p.category_root is not null
   group by p.taxonomy_section, p.category_root
  having count(*) filter (where p.age_restricted) > 0
      or p.taxonomy_section in ('Vinhos & Espirituosas', 'Bebidas')
   order by 4 desc, 3 desc;
end;
$$;

revoke all on function public.admin_set_product_age_restricted(text, boolean, text) from public, anon;
revoke all on function public.admin_set_age_restricted_by_category(text, text, boolean, text) from public, anon;
revoke all on function public.admin_list_products_maior_18(text, text, integer, integer) from public, anon;
revoke all on function public.admin_maior_18_por_categoria() from public, anon;
grant execute on function public.admin_set_product_age_restricted(text, boolean, text) to authenticated, service_role;
grant execute on function public.admin_set_age_restricted_by_category(text, text, boolean, text) to authenticated, service_role;
grant execute on function public.admin_list_products_maior_18(text, text, integer, integer) to authenticated, service_role;
grant execute on function public.admin_maior_18_por_categoria() to authenticated, service_role;

revoke all on function public.fn_products_maior_18_novo() from public, anon;
revoke all on function public.fn_orders_maior_18_criacao() from public, anon;
revoke all on function public.fn_orders_maior_18_guarda() from public, anon;
