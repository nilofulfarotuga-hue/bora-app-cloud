create or replace function pg_temp.c4_trocar(p_def text, p_nome text)
returns text
language plpgsql
as $t$
declare
  a1 text := '(SELECT p.price FROM products p WHERE p.id = (v_line->>''product_id'') LIMIT 1),';
  -- 30/10/2026: discount_price é double precision e price é numeric na base; converte-se para numeric com
  -- 2 casas para o COALESCE continuar numeric (sem vírgula flutuante nas contas do dinheiro).
  b1 text := '(SELECT round(p.discount_price::numeric, 2) FROM products p WHERE p.id = (v_line->>''product_id'') AND public.product_promocao_ativa(p.id) LIMIT 1),'
             || chr(10) || '            ' || a1;
  n integer;
begin
  -- já trocada: devolve a definição como está (executá-la outra vez é inofensivo)
  if position('product_promocao_ativa' in p_def) > 0 then
    return p_def;
  end if;
  n := (length(p_def) - length(replace(p_def, a1, ''))) / length(a1);
  if n <> 2 then
    raise exception '%: esperava 2 trechos do preço do produto, encontrei % — NÃO se troca nada; rever a definição viva', p_nome, n;
  end if;
  return replace(p_def, a1, b1);
end
$t$;
-- (precedido do bloco pg_temp.c4_trocar) Prova do pedido gravado com promoção, produto da Boom, tudo desfeito.
do $a$
begin
  execute pg_temp.c4_trocar(pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure), 'quote_order_pricing');
  execute pg_temp.c4_trocar(pg_get_functiondef('public.create_order(jsonb)'::regprocedure), 'create_order');
end
$a$;

DO $prova$
DECLARE
  u     uuid := 'd66d1522-ad8e-426e-9a75-76d636004186';
  rest  record;
  p_in  jsonb;
  q0    jsonb;
  q1    jsonb;
  r0    jsonb;
  r1    jsonb;
  o0    record;
  o1    record;
  sai   text := '';
  falhas integer := 0;
BEGIN
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'promotions_enabled';
  UPDATE public.restaurants SET coming_soon = false WHERE id = 'boom-burger-guarda';
  SELECT id, name, address, lat, lng INTO rest FROM public.restaurants WHERE id = 'boom-burger-guarda';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  PERFORM set_config('app.parceiro_chama_estafeta', 'on', true);  -- só para passar a loja fechada nesta prova
  p_in := jsonb_build_object(
    'service_type', 'restaurant', 'vendor_name', rest.name, 'is_partner_store', true,
    'distance_km', 1.5, 'payment_method', 'cash', 'subtotal', 6.06, 'apartment_delivery', false,
    'order_type', 'delivery', 'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', rest.lat, 'pickup_lng', rest.lng, 'pickup_address', rest.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Rua de teste, Guarda',
    'customer_name', 'Teste promo', 'client_phone', '912345678',
    'items', jsonb_build_array(jsonb_build_object('product_id', 'boom-bandida-pomar-maca-sidra', 'quantity', 2, 'name', 'Bandida', 'price', 3.03)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id', 'boom-bandida-pomar-maca-sidra', 'quantity', 2, 'unit_price', 3.03, 'name', 'Bandida')));

  -- sem promoção
  q0 := public.quote_order_pricing(p_in);
  r0 := public.create_order(p_in);
  SELECT id, subtotal, total, service_fee INTO o0 FROM public.orders WHERE id = COALESCE(r0->>'order_id', r0->>'id');

  -- com promoção de teste (2,50 em vez de 3,03), válida agora
  UPDATE public.products SET discount_price = 2.50, discount_enabled = true,
         discount_starts_at = now() - interval '1 hour', discount_ends_at = now() + interval '1 day'
   WHERE id = 'boom-bandida-pomar-maca-sidra';
  q1 := public.quote_order_pricing(p_in);
  r1 := public.create_order(p_in || jsonb_build_object('subtotal', 5.00));
  SELECT id, subtotal, total, service_fee INTO o1 FROM public.orders WHERE id = COALESCE(r1->>'order_id', r1->>'id');

  sai := format('sem promo: quote subtotal=%s total=%s | pedido %s subtotal=%s total=%s', q0->>'subtotal', q0->>'customer_total', left(o0.id, 8), o0.subtotal, o0.total);
  sai := sai || format(' || com promo: quote subtotal=%s total=%s | pedido %s subtotal=%s total=%s', q1->>'subtotal', q1->>'customer_total', left(o1.id, 8), o1.subtotal, o1.total);
  IF (q0->>'subtotal')::numeric = o0.subtotal AND o0.subtotal = 6.06 THEN sai := sai || ' || R1 ok(sem promo: mostrado = gravado = 2x3,03)';
  ELSE falhas := falhas + 1; sai := sai || ' || R1 FALHOU'; END IF;
  IF (q1->>'subtotal')::numeric = o1.subtotal AND o1.subtotal = 5.00 THEN sai := sai || ' || R2 ok(com promo: mostrado = gravado = 2x2,50)';
  ELSE falhas := falhas + 1; sai := sai || ' || R2 FALHOU'; END IF;
  IF (q1->>'customer_total')::numeric = o1.total THEN sai := sai || ' || R3 ok(total mostrado = total gravado)';
  ELSE falhas := falhas + 1; sai := sai || ' || R3 FALHOU (total)'; END IF;
  RAISE EXCEPTION 'PROVA(rollback) promo pedido falhas=% :: %', falhas, sai;
END
$prova$;
