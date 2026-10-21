-- 2026-10-21 · fechar-pendencias-2026-10-20 · BLOCO A1 · RONDA 1 do revisor (defeito E)
-- O tipo DECLARADO (caminho cartão/MB Way pela Edge tvde-payment, que não se toca)
-- passa a valer SÓ para a corrida do pagamento que o declarou: a mesma forma de
-- pagamento online e a mesma origem e destino, dentro de 2 minutos. Qualquer
-- pedido (com ou sem p_ride_kind) gasta a declaração; um pedido a DINHEIRO nunca
-- a herda; outro trajecto ou outra forma de pagamento também não.
-- Antes: tentar uma encomenda por cartão, falhar na Edge antes de criar a corrida
-- e pedir um Bora Motorista a dinheiro nos 5 min seguintes fazia nascer a corrida
-- de passageiros como 'encomendas' (provado pelo revisor, REVISAO-A1 §5.E).
-- Preço e despacho: nada muda. As 3 RPCs só trocam a linha que chama o resolver
-- (a mesma linha do tipo que a migração 20261021083355 pôs); md5 conferido antes
-- e prova byte a byte depois (desfeitas TODAS as linhas do tipo = md5 de 20/10).

create or replace function pg_temp._a1_troca(p_txt text, p_de text, p_para text, p_vezes int, p_onde text)
returns text language plpgsql as $f$
declare v_n int;
begin
  v_n := (length(p_txt) - length(replace(p_txt, p_de, ''))) / greatest(length(p_de), 1);
  if v_n <> p_vezes then
    raise exception 'A1 âncora % apareceu % vez(es), esperava % — nada foi mudado', p_onde, v_n, p_vezes;
  end if;
  return replace(p_txt, p_de, p_para);
end $f$;

-- 1. A declaração guarda o pedido concreto ----------------------------------------
alter table public.tvde_tipo_pedido
  add column if not exists payment_method text,
  add column if not exists origin_lat double precision,
  add column if not exists origin_lng double precision,
  add column if not exists dest_lat   double precision,
  add column if not exists dest_lng   double precision;
comment on table public.tvde_tipo_pedido is
  'Tipo (passageiros/encomendas) declarado pela app MESMO antes de chamar a Edge tvde-payment (cartão/MB Way). Só vale para a corrida desse pagamento: mesma forma de pagamento, mesma origem e destino, até 2 minutos. Qualquer pedido o gasta; a dinheiro nunca o herda. 21/10/2026 (A1, ronda 1).';

drop function if exists public.tvde_definir_tipo_pedido(text);
create or replace function public.tvde_definir_tipo_pedido(
  p_ride_kind text, p_payment_method text,
  p_origin_lat double precision, p_origin_lng double precision,
  p_dest_lat double precision, p_dest_lng double precision)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_ride_kind is null or p_ride_kind not in ('passageiros', 'encomendas') then
    raise exception 'invalid_ride_kind: %', p_ride_kind;
  end if;
  -- Só o caminho da Edge (pagamento online) precisa de declarar; a dinheiro
  -- a app manda o tipo directamente à RPC.
  if p_payment_method is null or p_payment_method not in ('card', 'mbway') then
    raise exception 'invalid_payment_method: %', p_payment_method;
  end if;
  if p_origin_lat is null or p_origin_lng is null or p_dest_lat is null or p_dest_lng is null then
    raise exception 'missing_route';
  end if;
  if p_ride_kind = 'encomendas'
     and not coalesce((public.get_setting('tvde_encomendas_enabled') #>> '{}')::boolean, false)
     and not public.is_admin() then
    raise exception 'encomendas_desligadas';
  end if;
  insert into public.tvde_tipo_pedido
    (client_id, ride_kind, definido_em, payment_method, origin_lat, origin_lng, dest_lat, dest_lng)
  values (v_uid, p_ride_kind, now(), p_payment_method, p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng)
  on conflict (client_id) do update
    set ride_kind = excluded.ride_kind, definido_em = excluded.definido_em,
        payment_method = excluded.payment_method,
        origin_lat = excluded.origin_lat, origin_lng = excluded.origin_lng,
        dest_lat = excluded.dest_lat, dest_lng = excluded.dest_lng;
  return p_ride_kind;
end $$;
revoke all on function public.tvde_definir_tipo_pedido(text, text, double precision, double precision, double precision, double precision) from public, anon;
grant execute on function public.tvde_definir_tipo_pedido(text, text, double precision, double precision, double precision, double precision) to authenticated, service_role;

-- 2. A regra única do tipo, agora com o pedido concreto ----------------------------
create or replace function public._tvde_ride_kind_resolver(
  p_uid uuid, p_ride_kind text, p_payment_method text,
  p_origin_lat double precision, p_origin_lng double precision,
  p_dest_lat double precision, p_dest_lng double precision)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare d public.tvde_tipo_pedido; v_kind text;
begin
  if p_ride_kind is not null and p_ride_kind not in ('passageiros', 'encomendas') then
    raise exception 'invalid_ride_kind: %', p_ride_kind;
  end if;
  -- Gasta SEMPRE a declaração deste cliente (nunca sobra para o pedido seguinte).
  if p_uid is not null then
    delete from public.tvde_tipo_pedido t where t.client_id = p_uid returning t.* into d;
  end if;
  v_kind := p_ride_kind;
  if v_kind is null
     and d.client_id is not null
     and coalesce(p_payment_method, 'cash') in ('card', 'mbway')
     and d.payment_method = p_payment_method
     and d.definido_em > now() - interval '2 minutes'
     and abs(d.origin_lat - p_origin_lat) < 1e-6 and abs(d.origin_lng - p_origin_lng) < 1e-6
     and abs(d.dest_lat - p_dest_lat) < 1e-6 and abs(d.dest_lng - p_dest_lng) < 1e-6 then
    v_kind := d.ride_kind;
  end if;
  v_kind := coalesce(v_kind, 'passageiros');
  if v_kind = 'encomendas'
     and not coalesce((public.get_setting('tvde_encomendas_enabled') #>> '{}')::boolean, false)
     and not public.is_admin() then
    raise exception 'encomendas_desligadas';
  end if;
  return v_kind;
end $$;
revoke all on function public._tvde_ride_kind_resolver(uuid, text, text, double precision, double precision, double precision, double precision) from public, anon, authenticated;
grant execute on function public._tvde_ride_kind_resolver(uuid, text, text, double precision, double precision, double precision, double precision) to service_role;

-- 3. As 3 RPCs chamam o resolver novo (só essa linha muda) --------------------------
do $r1$
declare
  c_old constant text := E'  v_ride_kind := public._tvde_ride_kind_resolver(v_uid, p_ride_kind);\n';
  c_new constant text := E'  v_ride_kind := public._tvde_ride_kind_resolver(v_uid, p_ride_kind, p_payment_method, p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng);\n';
  c_gate_ori constant text := E'  PERFORM public._tvde_exige_acesso(v_uid);\n';
  c_gate_ifp constant text := E'  IF v_ride_kind = ''passageiros'' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;\n';
  r record; v_oid oid; v_def text; v_src text; v_back text; v_acl_old text; v_acl_new text;
begin
  for r in select * from (values
      ('tvde_request_ride', 'double precision, double precision, text, double precision, double precision, text, numeric, text, integer, text',
       '8040a532f11f676ba8eccae5f2ece92e', '2a60a458a08fdca190c1c6875a7cc45d'),
      ('tvde_schedule_ride', 'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text, text',
       '72acbc58d18ddbca9e5c67b38a734aff', '9ab25a911968650cf1f83fda6207c3b9'),
      ('tvde_schedule_roundtrip', 'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, timestamp with time zone, text, text, text',
       '6bbcc4772c08a394d283b12eb4627fd2', '15c6d850789b1272ad78702c1d80fe40')
    ) as t(nome, sig, md5_a1, md5_ori)
  loop
    v_oid := to_regprocedure(format('public.%I(%s)', r.nome, r.sig));
    if v_oid is null then raise exception 'A1-r1 % não existe', r.nome; end if;
    if (select md5(prosrc) from pg_proc where oid = v_oid) <> r.md5_a1 then
      raise exception 'A1-r1 % mudou no ar desde a migração 20261021083355 — nada foi mudado', r.nome;
    end if;
    select proacl::text into v_acl_old from pg_proc where oid = v_oid;
    v_def := pg_temp._a1_troca(pg_get_functiondef(v_oid), c_old, c_new, 1, r.nome);
    execute v_def;
    select prosrc, proacl::text into v_src, v_acl_new from pg_proc where oid = v_oid;
    if v_acl_new is distinct from v_acl_old then
      raise exception 'A1-r1 % permissões mudaram (% -> %)', r.nome, v_acl_old, v_acl_new;
    end if;
    -- prova: desfeitas TODAS as linhas do tipo, o corpo é o de 20/10
    v_back := pg_temp._a1_troca(v_src, c_new || c_gate_ifp, c_gate_ori, 1, r.nome || ':portao');
    if r.nome = 'tvde_request_ride' then
      v_back := pg_temp._a1_troca(v_back, E'  v_km_declarado NUMERIC;\n  v_ride_kind TEXT;\nBEGIN', E'  v_km_declarado NUMERIC;\nBEGIN', 1, 'rr:declare');
      v_back := pg_temp._a1_troca(v_back, E'tokens_applied_count, tokens_applied_value_cents, ride_kind)', E'tokens_applied_count, tokens_applied_value_cents)', 1, 'rr:col');
      v_back := pg_temp._a1_troca(v_back, E'    v_tokens_discount_cents, v_ride_kind)\n', E'    v_tokens_discount_cents)\n', 1, 'rr:val');
    elsif r.nome = 'tvde_schedule_ride' then
      v_back := pg_temp._a1_troca(v_back, E'  v_fixed_driver int;\n  v_ride_kind text;\nBEGIN', E'  v_fixed_driver int;\nBEGIN', 1, 'sr:declare');
      v_back := pg_temp._a1_troca(v_back, E'customer_note, payment_status, ride_kind)', E'customer_note, payment_status)', 1, 'sr:col');
      v_back := pg_temp._a1_troca(v_back, E'ELSE NULL END, v_ride_kind)\n', E'ELSE NULL END)\n', 1, 'sr:val');
    else
      v_back := pg_temp._a1_troca(v_back, E'  v_ret_earn int;\n  v_ride_kind text;\nBEGIN', E'  v_ret_earn int;\nBEGIN', 1, 'rt:declare');
      v_back := pg_temp._a1_troca(v_back, E'p_payment_method, p_note, v_ride_kind);', E'p_payment_method, p_note);', 1, 'rt:call');
    end if;
    if md5(v_back) <> r.md5_ori then
      raise exception 'A1-r1 % sem as linhas do tipo NÃO é o corpo de 20/10 (% <> %)', r.nome, md5(v_back), r.md5_ori;
    end if;
    raise notice 'A1-r1 % ok: % -> % (desfeito %)', r.nome, r.md5_a1, md5(v_src), md5(v_back);
  end loop;
end $r1$;

-- 4. O resolver antigo (sem o pedido) deixa de existir ------------------------------
drop function if exists public._tvde_ride_kind_resolver(uuid, text);

notify pgrst, 'reload schema';
