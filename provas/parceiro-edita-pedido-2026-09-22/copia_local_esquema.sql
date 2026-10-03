CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS vault; CREATE SCHEMA IF NOT EXISTS net;
CREATE TABLE auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role','anon') $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('request.jwt.claims', true),'{}')::jsonb $$;
CREATE TABLE vault.decrypted_secrets (name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('project_url','https://x.supabase.co'),('service_role_key','k');
CREATE TABLE net.http_request_queue (id serial, url text, body jsonb);
CREATE FUNCTION net.http_post(url text, headers jsonb, body jsonb) RETURNS bigint LANGUAGE sql AS $$ INSERT INTO net.http_request_queue(url, body) VALUES (url, body) RETURNING id $$;
DO $$ BEGIN CREATE ROLE authenticated; CREATE ROLE anon; CREATE ROLE service_role; EXCEPTION WHEN OTHERS THEN NULL; END $$;

CREATE TABLE public.platform_settings (key text primary key, value jsonb, description text, category text, updated_at timestamptz, updated_by uuid, is_secret boolean default false);
INSERT INTO public.platform_settings(key,value) VALUES ('delivery_base_fee_cents','250'::jsonb),('delivery_per_km_cents','50'::jsonb),('delivery_base_distance_km','4'::jsonb),('driver_base_fee_cents','380'::jsonb),('driver_per_km_cents','20'::jsonb),('driver_surcharge_cents','80'::jsonb),('partner_driver_stacking_bonus_cents','300'::jsonb),('bag_fee_restaurant_cents','30'::jsonb),('bag_fee_supermarket_per_bag_cents','10'::jsonb),('max_cash_amount_cents','4000'::jsonb),('wallet_split_free_pct','0.80'::jsonb),('apartment_surcharge_total_cents','150'::jsonb),('apartment_driver_share_cents','100'::jsonb),('apartment_platform_share_cents','50'::jsonb),('logistics_driver_base_cents','400'::jsonb),('logistics_driver_per_km_cents','50'::jsonb),('package_base_fee_cents','600'::jsonb),('package_platform_share_cents','200'::jsonb),('non_partner_service_fee_cents','99'::jsonb),('min_order_cents','1500'::jsonb),('small_order_fee_cents','139'::jsonb),('small_order_fee_enabled','true'::jsonb),('order_edit_enabled','false'::jsonb),
('partner_visible_commission_pct','0.10'::jsonb),('client_service_fee_pct','0.05'::jsonb),('partner_hidden_markup_pct','0.05'::jsonb),('non_partner_markup_pct','0.15'::jsonb),('driver_profit_share_pct','0.30'::jsonb);

CREATE TABLE public.restaurants (id text primary key, name text, user_id uuid, app_markup_pct numeric, is_partner boolean, coming_soon boolean default false, min_order_cents_override int, small_order_fee_cents_override int);
INSERT INTO public.restaurants(id,name,user_id,app_markup_pct,is_partner) VALUES ('12aa2cbb-01bd-443b-a17e-633c169d4864','Sabores de Casa Açaí','033e0fef-1a93-4c1b-b738-18572a936285',NULL,'t'),('mrkebab-guarda','Mr Kebab & Restaurant','355fdb3f-e118-427f-9385-458a0acc202a',0.15,'t');
CREATE TABLE public.products (id text primary key, restaurant_id text, name text, price numeric, is_available boolean);
INSERT INTO public.products VALUES ('mrk-menu-taco-kebab','mrkebab-guarda','Menu Taco Kebab',11.50,true),('mrk-agua-33','mrkebab-guarda','Água 33cl',0.92,true),('94f425c1-3765-404c-98e0-4e4e195c725f','12aa2cbb-01bd-443b-a17e-633c169d4864','Paçoca Moreninha do Rio',1.17,true),('06deb41d-7570-47bb-a69d-a4a7f4284465','12aa2cbb-01bd-443b-a17e-633c169d4864','Água',1.17,true),('49b857ce-112b-4e73-88c7-034be24b2ce8','12aa2cbb-01bd-443b-a17e-633c169d4864','Filtro para Bomba de Chimarrão (2 un)',0.93,true),('8e3e4fc8-d382-46ec-8e14-bf7c3106b24a','12aa2cbb-01bd-443b-a17e-633c169d4864','Copo Mega 500ml',14.00,true);
CREATE TABLE public.product_option_groups (id text, product_id text, name text);
INSERT INTO public.product_option_groups VALUES ('8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g0','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a','Escolha os Acompanhamentos:'),('8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g1','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a','Deseja Extras?');
CREATE TABLE public.product_option_items (id text, group_id text, name text, price_add numeric, is_available boolean);
INSERT INTO public.product_option_items VALUES ('g0i4','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g0','Mel',0,'t'),('g0i9','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g0','Kiwi',0,'t'),('g1i0','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g1','Mel',1,'t'),('g1i8','8e3e4fc8-d382-46ec-8e14-bf7c3106b24a-g1','Kiwi',1,'t');
INSERT INTO auth.users VALUES ('033e0fef-1a93-4c1b-b738-18572a936285','dono@x'),('355fdb3f-e118-427f-9385-458a0acc202a','keb@x'),('c9fccf85-03ee-4efc-83bf-613f211a78ff','cli@x');

CREATE TABLE public.orders (id text primary key default gen_random_uuid()::text, created_at timestamptz default now(), user_id uuid, status text, service_type text, is_partner_store boolean, restaurant_id text, vendor_name text,
 payment_method text, payment_status text default 'pending', payment_intent_id text, items jsonb default '[]', subtotal numeric, delivery_fee numeric, service_fee numeric, bag_fee numeric default 0, bag_count int default 0,
 platform_commission numeric, partner_commission_visible numeric, partner_markup_hidden numeric, partner_service_fee_client numeric, driver_earnings numeric, distance_km numeric,
 price numeric, total numeric, customer_total numeric, final_total numeric, payment_buffer_total double precision, small_order_fee numeric default 0, is_test_order boolean default false,
 pickup_address text, dropoff_address text, apartment_delivery boolean, takeaway_picked_up_at timestamptz, assigned_driver_id text, cash_total_due numeric, items_added jsonb default '[]');
CREATE TABLE public.client_wallets (user_id uuid primary key, free_balance_cents integer default 0, created_at timestamptz default now(), updated_at timestamptz);
CREATE TABLE public.wallet_transactions (id uuid default gen_random_uuid(), user_id uuid, amount_cents integer, kind text, reason text, related_order_id text, related_admin_id uuid, created_at timestamptz default clock_timestamp(), balance_after_cents integer, idempotency_key text unique);
CREATE TABLE public.in_app_notifications (id uuid default gen_random_uuid(), user_id uuid, kind text, title text, body text, related_id text, read_at timestamptz, created_at timestamptz default now());
CREATE TABLE public.admin_audit_log (id uuid default gen_random_uuid(), admin_id uuid, admin_email text, action text, entity_type text, entity_id uuid, details jsonb, ip_address text, created_at timestamptz default now(), entity_id_text text);
CREATE TABLE public.admin_logs (action_type text, entity_type text, entity_id text, details jsonb, created_at timestamptz);
CREATE TABLE public.tokens_stub (user_id uuid, n int, ref text);

CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND (raw_app_meta_data->>'role' = 'admin')) $$;
CREATE FUNCTION public.get_setting(p_key text) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT value FROM public.platform_settings WHERE key = p_key $$;
CREATE FUNCTION public.add_tokens(p_user uuid, p_role text, p_n int, p_ref text) RETURNS uuid LANGUAGE sql AS $$ INSERT INTO public.tokens_stub VALUES (p_user, p_n, p_ref); SELECT gen_random_uuid() $$;
CREATE OR REPLACE FUNCTION public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb DEFAULT NULL::jsonb) RETURNS void LANGUAGE plpgsql AS $$
BEGIN INSERT INTO admin_logs VALUES (p_action_type, p_entity_type, p_entity_id, p_details, now()); END $$;
CREATE FUNCTION public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text DEFAULT NULL, p_related_id text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; BEGIN IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN RETURN NULL; END IF;
INSERT INTO in_app_notifications(user_id,kind,title,body,related_id) VALUES (p_user_id,p_kind,p_title,p_body,p_related_id) RETURNING id INTO v; RETURN v; END $$;

CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric) RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT ROUND(p_subtotal * (1 - COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = 'partner_visible_commission_pct'), 0.10))
      / (1 + COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = 'partner_hidden_markup_pct'), 0.05)), 2); $function$;
CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric, p_restaurant_id text) RETURNS numeric LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    ELSE public.partner_store_share(p_subtotal) END; $function$;

CREATE OR REPLACE FUNCTION public.small_order_fee_calc(p_service_type text, p_subtotal numeric, p_restaurant_id text DEFAULT NULL::text) RETURNS numeric LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE v_enabled BOOLEAN; v_min_cents INTEGER; v_fee_cents INTEGER;
BEGIN
  SELECT COALESCE((value::text)::BOOLEAN, false) INTO v_enabled FROM public.platform_settings WHERE key = 'small_order_fee_enabled';
  IF COALESCE(v_enabled, false) IS NOT TRUE THEN RETURN 0; END IF;
  IF p_service_type IS NULL OR p_service_type NOT IN ('restaurant','storeShopping') THEN RETURN 0; END IF;
  IF p_subtotal IS NULL OR p_subtotal <= 0 THEN RETURN 0; END IF;
  IF p_restaurant_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id = p_restaurant_id AND COALESCE(r.is_partner, false)) THEN RETURN 0; END IF;
  SELECT (value::text)::INTEGER INTO v_min_cents FROM public.platform_settings WHERE key = 'min_order_cents';
  SELECT (value::text)::INTEGER INTO v_fee_cents FROM public.platform_settings WHERE key = 'small_order_fee_cents';
  IF p_restaurant_id IS NOT NULL THEN
    SELECT COALESCE(r.min_order_cents_override, v_min_cents), COALESCE(r.small_order_fee_cents_override, v_fee_cents) INTO v_min_cents, v_fee_cents FROM public.restaurants r WHERE r.id = p_restaurant_id;
  END IF;
  IF v_min_cents IS NULL OR v_fee_cents IS NULL OR v_min_cents <= 0 OR v_fee_cents <= 0 THEN RETURN 0; END IF;
  IF ROUND(p_subtotal * 100)::INTEGER >= v_min_cents THEN RETURN 0; END IF;
  RETURN ROUND(v_fee_cents / 100.0, 2);
END; $function$;

CREATE OR REPLACE FUNCTION public.order_line_options_extras(p_product_id text, p_selected_options jsonb) RETURNS TABLE(extras_total numeric, options_priced jsonb) LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  WITH sel AS (SELECT g.value->>'group' AS group_name, it.item_name FROM jsonb_array_elements(COALESCE(p_selected_options, '[]'::jsonb)) g
    CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE(g.value->'items', '[]'::jsonb)) it(item_name)),
  matched AS (SELECT s.group_name, s.item_name, COALESCE(MIN(poi.price_add) FILTER (WHERE poi.is_available), 0) AS price_add FROM sel s
    LEFT JOIN product_option_groups pog ON pog.product_id = p_product_id AND pog.name = s.group_name
    LEFT JOIN product_option_items poi ON poi.group_id = pog.id AND poi.name = s.item_name GROUP BY s.group_name, s.item_name),
  grouped AS (SELECT group_name, jsonb_agg(jsonb_build_object('name', item_name, 'price_add', price_add)) AS items_priced, SUM(price_add) AS group_total FROM matched GROUP BY group_name)
  SELECT COALESCE((SELECT SUM(group_total) FROM grouped), 0)::NUMERIC, COALESCE((SELECT jsonb_agg(jsonb_build_object('group', group_name, 'items', items_priced)) FROM grouped), '[]'::jsonb); $function$;

CREATE OR REPLACE FUNCTION public.pricing_calculate(p_service_type text, p_subtotal numeric, p_distance_km numeric, p_is_partner_store boolean DEFAULT false, p_apartment_delivery boolean DEFAULT false, p_is_stacked_partner boolean DEFAULT false, p_bag_count integer DEFAULT 0)
 RETURNS TABLE(delivery_fee numeric, service_fee numeric, platform_commission numeric, driver_earnings numeric, customer_total numeric, partner_markup_hidden numeric, bag_fee numeric)
 LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE
  v_settings jsonb; c_driver_base_pay NUMERIC; c_driver_per_km NUMERIC; c_partner_delivery_base NUMERIC; c_partner_commission_rate NUMERIC; c_partner_service_fee_rate NUMERIC;
  c_partner_markup_hidden_rate NUMERIC; c_partner_stacking_bonus NUMERIC; c_package_base_distance_km NUMERIC; c_package_extra_per_km NUMERIC;
  c_apartment_surcharge_total NUMERIC; c_apartment_driver_share NUMERIC; c_apartment_platform_share NUMERIC; c_restaurant_bag_fee NUMERIC; c_supermarket_bag_fee_per_bag NUMERIC;
  v_distance NUMERIC; v_subtotal NUMERIC; v_apt_surcharge NUMERIC; v_apt_driver NUMERIC; v_apt_platform NUMERIC; v_extra_dist NUMERIC;
  v_delivery_fee NUMERIC := 0; v_service_fee NUMERIC := 0; v_platform_commission NUMERIC := 0; v_driver_earnings NUMERIC := 0; v_partner_markup_hidden NUMERIC := 0; v_store_share NUMERIC := 0; v_bag_fee NUMERIC := 0;
BEGIN
  SELECT jsonb_object_agg(key, value) INTO v_settings FROM platform_settings;
  c_driver_base_pay := ((v_settings->>'driver_base_fee_cents')::NUMERIC) / 100.0;
  c_driver_per_km := ((v_settings->>'driver_per_km_cents')::NUMERIC) / 100.0;
  c_partner_delivery_base := ((v_settings->>'delivery_base_fee_cents')::NUMERIC) / 100.0;
  c_partner_commission_rate := (v_settings->>'partner_visible_commission_pct')::NUMERIC;
  c_partner_service_fee_rate := (v_settings->>'client_service_fee_pct')::NUMERIC;
  c_partner_markup_hidden_rate := (v_settings->>'partner_hidden_markup_pct')::NUMERIC;
  c_partner_stacking_bonus := ((v_settings->>'partner_driver_stacking_bonus_cents')::NUMERIC) / 100.0;
  c_package_base_distance_km := (v_settings->>'delivery_base_distance_km')::NUMERIC;
  c_package_extra_per_km := ((v_settings->>'delivery_per_km_cents')::NUMERIC) / 100.0;
  c_apartment_surcharge_total := ((v_settings->>'apartment_surcharge_total_cents')::NUMERIC) / 100.0;
  c_apartment_driver_share := ((v_settings->>'apartment_driver_share_cents')::NUMERIC) / 100.0;
  c_apartment_platform_share := ((v_settings->>'apartment_platform_share_cents')::NUMERIC) / 100.0;
  c_restaurant_bag_fee := ((v_settings->>'bag_fee_restaurant_cents')::NUMERIC) / 100.0;
  c_supermarket_bag_fee_per_bag := ((v_settings->>'bag_fee_supermarket_per_bag_cents')::NUMERIC) / 100.0;
  v_distance := GREATEST(1.0, COALESCE(p_distance_km, 1.0));
  v_subtotal := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));
  v_apt_surcharge := CASE WHEN p_apartment_delivery THEN c_apartment_surcharge_total ELSE 0 END;
  v_apt_driver := CASE WHEN p_apartment_delivery THEN c_apartment_driver_share ELSE 0 END;
  v_apt_platform := CASE WHEN p_apartment_delivery THEN c_apartment_platform_share ELSE 0 END;
  -- só o ramo PARCEIRO (o único que a edição usa), copiado do de produção
  v_extra_dist := GREATEST(0, v_distance - c_package_base_distance_km);
  v_delivery_fee := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
  v_service_fee := ROUND(v_subtotal * c_partner_service_fee_rate, 2);
  v_store_share := public.partner_store_share(v_subtotal);
  v_partner_markup_hidden := ROUND(v_store_share * c_partner_markup_hidden_rate, 2);
  v_platform_commission := ROUND(v_subtotal - v_store_share - v_partner_markup_hidden, 2) + v_apt_platform;
  IF p_is_stacked_partner THEN v_driver_earnings := ROUND(c_partner_stacking_bonus + v_apt_driver, 2);
  ELSE v_driver_earnings := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver, 2); END IF;
  v_bag_fee := CASE WHEN p_service_type = 'restaurant' THEN c_restaurant_bag_fee WHEN p_service_type = 'storeShopping' THEN c_supermarket_bag_fee_per_bag * GREATEST(1, p_bag_count) ELSE 0 END;
  RETURN QUERY SELECT ROUND(v_delivery_fee, 2), ROUND(v_service_fee, 2), ROUND(v_platform_commission, 2), ROUND(v_driver_earnings, 2),
    ROUND(v_subtotal + v_service_fee + v_delivery_fee + v_bag_fee, 2), ROUND(v_partner_markup_hidden, 2), ROUND(v_bag_fee, 2);
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_relabel_partner_split_por_loja() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
DECLARE v_pct numeric; v_rate numeric; v_sub numeric; v_old_share numeric; v_old_markup numeric; v_new_share numeric; v_new_markup numeric;
BEGIN
  IF COALESCE(NEW.is_partner_store,false) IS NOT TRUE OR NEW.restaurant_id IS NULL THEN RETURN NEW; END IF;
  SELECT app_markup_pct INTO v_pct FROM public.restaurants WHERE id = NEW.restaurant_id::text;
  IF COALESCE(v_pct,0) <= 0 THEN RETURN NEW; END IF;
  v_sub := COALESCE(NEW.subtotal,0);
  IF v_sub <= 0 OR NEW.partner_markup_hidden IS NULL THEN RETURN NEW; END IF;
  v_rate := COALESCE((SELECT (value::text)::numeric FROM public.platform_settings WHERE key='partner_hidden_markup_pct'),0.05);
  v_old_share := public.partner_store_share(v_sub); v_old_markup := NEW.partner_markup_hidden;
  v_new_share := public.partner_store_share(v_sub, NEW.restaurant_id::text); v_new_markup := ROUND(v_new_share * v_rate, 2);
  NEW.partner_markup_hidden := v_new_markup;
  IF NEW.partner_commission_visible IS NOT NULL THEN NEW.partner_commission_visible := NEW.partner_commission_visible + (v_old_share - v_new_share) + (v_old_markup - v_new_markup); END IF;
  IF NEW.platform_commission IS NOT NULL THEN NEW.platform_commission := NEW.platform_commission + (v_old_share - v_new_share) + (v_old_markup - v_new_markup); END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER zz_relabel_partner_split_por_loja BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION fn_relabel_partner_split_por_loja();

CREATE OR REPLACE FUNCTION public.fn_small_order_fee() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
DECLARE v_global NUMERIC; v_real NUMERIC; v_declarada NUMERIC; v_delta NUMERIC;
BEGIN
  v_global := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NEW.restaurant_id);
  v_real := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NEW.restaurant_id);
  IF NEW.payment_status = 'paid' AND NEW.payment_intent_id IS NOT NULL THEN v_real := v_global; END IF;
  v_declarada := COALESCE(NEW.small_order_fee, 0); NEW.small_order_fee := COALESCE(v_real, 0);
  v_delta := ROUND((COALESCE(v_real, 0) - v_declarada)::numeric, 2);
  IF v_delta = 0 THEN RETURN NEW; END IF;
  NEW.price := ROUND((COALESCE(NEW.price, 0) + v_delta)::numeric, 2);
  IF NEW.final_total IS NOT NULL THEN NEW.final_total := ROUND((NEW.final_total + v_delta)::numeric, 2); END IF;
  IF NEW.payment_buffer_total IS NOT NULL THEN NEW.payment_buffer_total := ROUND((NEW.payment_buffer_total + v_delta)::numeric, 2); END IF;
  RETURN NEW;
END; $function$;
CREATE TRIGGER orders_aa_small_order_fee BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION fn_small_order_fee();

CREATE OR REPLACE FUNCTION public.enforce_financial_immutability() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF auth.role() <> 'service_role' AND COALESCE(current_setting('app.financial_bypass', true), 'false') <> 'true' THEN
    IF NEW.price IS DISTINCT FROM OLD.price OR NEW.final_total IS DISTINCT FROM OLD.final_total OR NEW.subtotal IS DISTINCT FROM OLD.subtotal
     OR NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee OR NEW.service_fee IS DISTINCT FROM OLD.service_fee OR NEW.platform_commission IS DISTINCT FROM OLD.platform_commission
     OR NEW.driver_earnings IS DISTINCT FROM OLD.driver_earnings OR NEW.bag_fee IS DISTINCT FROM OLD.bag_fee OR NEW.payment_buffer_total IS DISTINCT FROM OLD.payment_buffer_total THEN
      RAISE EXCEPTION 'FINANCIAL_COLUMNS_IMMUTABLE';
    END IF;
  END IF;
  RETURN NEW;
END; $function$;
CREATE TRIGGER orders_financial_lock BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION enforce_financial_immutability();
CREATE OR REPLACE FUNCTION public.enforce_cash_payment_limit() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE v_total NUMERIC; BEGIN IF NEW.payment_method IS DISTINCT FROM 'cash' THEN RETURN NEW; END IF;
  v_total := COALESCE(NEW.final_total, NEW.price, 0); IF v_total > 40 THEN RAISE EXCEPTION 'CASH_LIMIT_EXCEEDED'; END IF; RETURN NEW; END; $function$;
CREATE TRIGGER orders_enforce_cash_limit BEFORE INSERT OR UPDATE OF payment_method, price, final_total ON public.orders FOR EACH ROW EXECUTE FUNCTION enforce_cash_payment_limit();
