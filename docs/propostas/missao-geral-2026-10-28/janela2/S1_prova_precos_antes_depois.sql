-- S1_prova_precos_antes_depois.sql — prova de que o mesmo carrinho dá o mesmo total antes e depois do S1.
-- SÓ LEITURA, transação desfeita (acaba num RAISE). Correr com execute_sql ANTES do S1 e outra vez DEPOIS.
-- Este ficheiro não tem DDL de propósito: a trava do Bora recusa um SQL que junte DDL com o nome de uma
-- função de preço, por isso a prova de preços está separada do S1_prova_rollback.sql.
--
-- Ator: uma conta de cliente comum (não admin, sem loja), papel authenticated, com claims.
-- Dois carrinhos reais de hoje: loja PARCEIRA (Sabores de Casa Açaí, 2 unidades) e loja NÃO PARCEIRA
-- (Continente, 3 unidades). Também confirma que a função de partilha do parceiro (INVOKER) dá o mesmo
-- número à conta normal e ao anon (que já hoje não vê a tabela) — logo não muda com o S1.
--
-- BASELINE de 29/10/2026 (ANTES do S1), conta normal:
--   PARCEIRA     subtotal=13.76 delivery_fee=2.50 service_fee=0.69 small_order_fee=0 customer_total=17.25
--                platform_commission=1.38 driver_earnings=4.04              md5_q1=2a3fb771b124c53c98687c9dfca3af1e
--   NAO_PARCEIRA subtotal=11.40 delivery_fee=2.50 service_fee=0.99 small_order_fee=0 customer_total=14.99
--                platform_commission=0.99 driver_earnings=4.92              md5_q2=2eccb40e207bcfa8625306ece211000f
--   partilha do parceiro sobre 100: postgres=85.71 cliente=85.71 anon=85.71
-- DEPOIS do S1 os dois md5 e o 85.71 têm de ser iguais. Se não forem: reverter o S1.

do $prova$
declare
  v_cli uuid; r text := ''; q1 jsonb; q2 jsonb; a numeric; b numeric; c numeric;
  ks text[] := array['subtotal','delivery_fee','service_fee','small_order_fee','customer_total','charge_total','platform_commission','driver_earnings'];
  k text;
begin
  select u.id into v_cli from auth.users u
   where coalesce(u.raw_app_meta_data->>'role','') <> 'admin'
     and not exists (select 1 from public.restaurants q where q.user_id = u.id or q.user_ = u.id)
   order by u.created_at desc limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
  set local role authenticated;
  q1 := public.quote_order_pricing(jsonb_build_object('service_type','restaurant','is_partner_store',true,
          'restaurant_id','12aa2cbb-01bd-443b-a17e-633c169d4864','vendor_name','Sabores de Casa Açaí','items','[]'::jsonb,
          'product_lines',jsonb_build_array(jsonb_build_object('product_id','018e1f14-fcc2-4294-8cab-5de92037bf66','quantity',2,'unit_price',6.88,'name','teste')),
          'distance_km',1.2,'apartment_delivery',false,'pickup_lat',40.5369,'pickup_lng',-7.2681,'dropoff_lat',40.5420,'dropoff_lng',-7.2750,
          'wallet_applied_cents',0,'include_debt',true,'payment_method','card'));
  q2 := public.quote_order_pricing(jsonb_build_object('service_type','storeShopping','is_partner_store',false,
          'restaurant_id','continente-guarda','vendor_name','Continente','items','[]'::jsonb,
          'product_lines',jsonb_build_array(jsonb_build_object('product_id','cnt-2000022','quantity',3,'unit_price',3.30,'name','teste')),
          'distance_km',1.0,'apartment_delivery',false,'pickup_lat',40.546172,'pickup_lng',-7.265104,'dropoff_lat',40.5400,'dropoff_lng',-7.2700,
          'wallet_applied_cents',0,'include_debt',true,'payment_method','card'));
  b := public.partner_store_share(100::numeric);
  reset role;
  a := public.partner_store_share(100::numeric);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  c := public.partner_store_share(100::numeric);
  reset role;
  r := 'PARCEIRA: ';
  foreach k in array ks loop r := r || k || '=' || coalesce(q1->>k,'-') || ' '; end loop;
  r := r || E'\nNAO_PARCEIRA: ';
  foreach k in array ks loop r := r || k || '=' || coalesce(q2->>k,'-') || ' '; end loop;
  r := r || E'\nmd5_q1=' || md5(q1::text) || ' md5_q2=' || md5(q2::text);
  r := r || E'\npartilha do parceiro sobre 100: postgres=' || a || ' cliente=' || b || ' anon=' || c;
  raise exception 'RESULT %', r;
end
$prova$;
