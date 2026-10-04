-- Agente parceiro (ronda 04/10/2026) — C1 + C2
--
-- C1: o parceiro (sessão "authenticated" a escrever direto na tabela) deixa de
--     poder mudar os campos que só o administrador muda. Os caminhos legítimos
--     continuam a funcionar:
--       * app do parceiro: business_hours, is_online, reservations_enabled,
--         takeaway_enabled, curbside_enabled, takeaway_default_prep_minutes,
--         photo_url, fcm_token, pausa_ate (nenhum destes está na lista);
--       * admin pela app (is_admin());
--       * Edge Functions com service_role e funções SECURITY DEFINER
--         (approve_partner, admin_update_partner_data, _update_restaurant_avg_rating,
--         apply_stripe_account_update, ...) correm como outro papel e passam.
-- C2: as regras de acesso dos pedidos do parceiro passam a ir pela loja
--     (restaurant_id) e não pelo nome da loja (vendor_name).

-- ── C1 ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._restaurants_campos_so_admin()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_campos text[] := '{}';
BEGIN
  -- Só trava escrita direta de utilizadores (PostgREST: papel authenticated/anon).
  -- service_role e funções SECURITY DEFINER (current_user = dono) passam.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.name IS DISTINCT FROM OLD.name THEN v_campos := array_append(v_campos, 'name'); END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN v_campos := array_append(v_campos, 'user_id'); END IF;
  IF NEW.user_ IS DISTINCT FROM OLD.user_ THEN v_campos := array_append(v_campos, 'user_'); END IF;
  IF NEW.is_partner IS DISTINCT FROM OLD.is_partner THEN v_campos := array_append(v_campos, 'is_partner'); END IF;
  IF NEW.app_markup_pct IS DISTINCT FROM OLD.app_markup_pct THEN v_campos := array_append(v_campos, 'app_markup_pct'); END IF;
  IF NEW.partner_commission_billing IS DISTINCT FROM OLD.partner_commission_billing THEN v_campos := array_append(v_campos, 'partner_commission_billing'); END IF;
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status THEN v_campos := array_append(v_campos, 'approval_status'); END IF;
  IF NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN v_campos := array_append(v_campos, 'approved_at'); END IF;
  IF NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN v_campos := array_append(v_campos, 'approved_by'); END IF;
  IF NEW.is_active_admin IS DISTINCT FROM OLD.is_active_admin THEN v_campos := array_append(v_campos, 'is_active_admin'); END IF;
  IF NEW.avg_rating IS DISTINCT FROM OLD.avg_rating THEN v_campos := array_append(v_campos, 'avg_rating'); END IF;
  IF NEW.ratings_count IS DISTINCT FROM OLD.ratings_count THEN v_campos := array_append(v_campos, 'ratings_count'); END IF;
  IF NEW.stripe_account_id IS DISTINCT FROM OLD.stripe_account_id THEN v_campos := array_append(v_campos, 'stripe_account_id'); END IF;
  IF NEW.stripe_account_status IS DISTINCT FROM OLD.stripe_account_status THEN v_campos := array_append(v_campos, 'stripe_account_status'); END IF;
  IF NEW.stripe_charges_enabled IS DISTINCT FROM OLD.stripe_charges_enabled THEN v_campos := array_append(v_campos, 'stripe_charges_enabled'); END IF;
  IF NEW.stripe_payouts_enabled IS DISTINCT FROM OLD.stripe_payouts_enabled THEN v_campos := array_append(v_campos, 'stripe_payouts_enabled'); END IF;
  IF NEW.stripe_requirements IS DISTINCT FROM OLD.stripe_requirements THEN v_campos := array_append(v_campos, 'stripe_requirements'); END IF;
  IF NEW.stripe_onboarded_at IS DISTINCT FROM OLD.stripe_onboarded_at THEN v_campos := array_append(v_campos, 'stripe_onboarded_at'); END IF;
  IF NEW.min_order_cents_override IS DISTINCT FROM OLD.min_order_cents_override THEN v_campos := array_append(v_campos, 'min_order_cents_override'); END IF;
  IF NEW.small_order_fee_cents_override IS DISTINCT FROM OLD.small_order_fee_cents_override THEN v_campos := array_append(v_campos, 'small_order_fee_cents_override'); END IF;

  IF cardinality(v_campos) > 0 THEN
    RAISE EXCEPTION 'ADMIN_ONLY_FIELDS: % (só o administrador pode mudar)',
      array_to_string(v_campos, ', ')
      USING ERRCODE = '42501', HINT = 'ADMIN_ONLY_FIELDS';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE TRIGGER trg_restaurants_campos_so_admin
  BEFORE UPDATE ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public._restaurants_campos_so_admin();

-- ── C2 ─────────────────────────────────────────────────────────────────────
-- Lojas do utilizador em sessão (SECURITY DEFINER: não depende do RLS de
-- restaurants, que esconde lojas ainda não aprovadas).
CREATE OR REPLACE FUNCTION public.parceiro_minhas_lojas()
RETURNS SETOF text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT r.id FROM public.restaurants r
   WHERE auth.uid() IS NOT NULL
     AND (r.user_id = auth.uid() OR r.user_ = auth.uid());
$fn$;
REVOKE ALL ON FUNCTION public.parceiro_minhas_lojas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parceiro_minhas_lojas() TO authenticated, service_role;

-- Cópia antes de preencher restaurant_id em pedidos de parceiro antigos.
CREATE TABLE IF NOT EXISTS public.bkp_orders_restaurant_id_20261004 AS
  SELECT o.id, o.restaurant_id, o.vendor_name, now() AS copiado_em
    FROM public.orders o
   WHERE o.restaurant_id IS NULL AND COALESCE(o.is_partner_store, false);
ALTER TABLE public.bkp_orders_restaurant_id_20261004 ENABLE ROW LEVEL SECURITY;

-- Preenche só quando o nome aponta para UMA loja parceira (sem ambiguidade).
UPDATE public.orders o
   SET restaurant_id = (SELECT r.id FROM public.restaurants r WHERE r.name = o.vendor_name AND COALESCE(r.is_partner, false))
 WHERE o.restaurant_id IS NULL
   AND COALESCE(o.is_partner_store, false)
   AND (SELECT count(*) FROM public.restaurants r WHERE r.name = o.vendor_name AND COALESCE(r.is_partner, false)) = 1;

CREATE OR REPLACE FUNCTION public._orders_preenche_restaurant_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ids text[];
BEGIN
  IF NEW.restaurant_id IS NOT NULL OR NOT COALESCE(NEW.is_partner_store, false)
     OR NEW.vendor_name IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT array_agg(r.id) INTO v_ids
    FROM public.restaurants r
   WHERE r.name = NEW.vendor_name AND COALESCE(r.is_partner, false);
  IF cardinality(v_ids) = 1 THEN
    NEW.restaurant_id := v_ids[1];
  END IF;
  RETURN NEW;
END;
$fn$;

-- "a0_" para correr antes dos outros BEFORE INSERT (ordem alfabética), que
-- dependem de restaurant_id (horário, markup por loja, ...).
CREATE OR REPLACE TRIGGER a0_orders_preenche_restaurant_id
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_preenche_restaurant_id();

ALTER POLICY orders_select_partner ON public.orders
  USING (restaurant_id IN (SELECT public.parceiro_minhas_lojas()));

ALTER POLICY orders_update_partner ON public.orders
  USING (restaurant_id IN (SELECT public.parceiro_minhas_lojas()))
  WITH CHECK (restaurant_id IN (SELECT public.parceiro_minhas_lojas()));

-- A5/A2: o parceiro deixa de inserir pedidos direto na tabela. O "Chamar
-- estafeta" passa pela RPC partner_chamar_estafeta (dinheiro calculado no
-- servidor). Nenhum outro caminho do parceiro insere pedidos.
ALTER POLICY orders_insert_partner ON public.orders
  WITH CHECK (false);

-- _partner_owns_order: por restaurant_id (e user_id OU user_), o nome só
-- quando o pedido não tem loja (pedidos muito antigos).
CREATE OR REPLACE FUNCTION public._partner_owns_order(p_order_id text, p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.restaurants r
      ON r.id = o.restaurant_id
      OR (o.restaurant_id IS NULL AND r.name = o.vendor_name)
    WHERE o.id = p_order_id
      AND (r.user_id = p_uid OR r.user_ = p_uid)
      AND COALESCE(r.is_partner, false)
      AND COALESCE(r.is_active_admin, true)
      AND r.approval_status = 'approved'
  );
$function$;
