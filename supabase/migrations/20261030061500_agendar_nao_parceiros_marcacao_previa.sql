-- Agendar nos mercados, parte 2 (30/10/2026): marcação prévia da hora.
--
-- O pedido nasce na app em order_store.dart (zona vermelha) e no cartão pelo rascunho, na Edge Function
-- (zona Stripe). Para não mexer em nenhum dos dois, a app regista a hora ANTES de criar o pedido
-- (client_preparar_agendamento) e o gatilho a0a_orders_agendado_na_criacao aplica-a no INSERT do pedido
-- desse cliente nessa loja (válida 20 minutos, usada uma só vez). Com o pedido ainda por pagar a janela
-- tem de ser válida; já pago (cartão), basta a loja abrir nessa hora.
-- O painel passa a receber parceiro/não-parceiro e o tipo de serviço para filtrar.
-- Nada aqui mexe em preços, taxas, comissões, carteira ou tokens.

CREATE TABLE IF NOT EXISTS public.pedido_agendamento_pendente (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  restaurant_id text NOT NULL,
  scheduled_for timestamptz NOT NULL,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  expira_em     timestamptz NOT NULL DEFAULT now() + interval '20 minutes',
  usado_em      timestamptz,
  order_id      text
);
CREATE INDEX IF NOT EXISTS pedido_agendamento_pendente_user_idx
  ON public.pedido_agendamento_pendente (user_id, restaurant_id) WHERE usado_em IS NULL;
COMMENT ON TABLE public.pedido_agendamento_pendente IS
  'Hora marcada pelo cliente antes de criar o pedido (agendar). Só por funções SECURITY DEFINER.';
ALTER TABLE public.pedido_agendamento_pendente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pedido_agendamento_pendente FROM PUBLIC, anon, authenticated;

-- A app chama antes de criar o pedido. p_scheduled_for NULL = "Entregar agora" (apaga a marcação).
CREATE OR REPLACE FUNCTION public.client_preparar_agendamento(p_restaurant_id text, p_scheduled_for timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_valid boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  DELETE FROM public.pedido_agendamento_pendente WHERE user_id = v_uid AND usado_em IS NULL;
  IF p_scheduled_for IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'agendado', false);
  END IF;
  IF p_restaurant_id IS NULL THEN RAISE EXCEPTION 'schedule_required'; END IF;
  IF NOT (public._sched_cfg()->>'enabled')::boolean THEN RAISE EXCEPTION 'scheduled_orders_disabled'; END IF;
  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
             public._sched_windows_core(p_restaurant_id, (p_scheduled_for AT TIME ZONE 'Europe/Lisbon')::date, 0)) w
     WHERE (w->>'inicio')::timestamptz = p_scheduled_for) INTO v_valid;
  IF NOT v_valid THEN RAISE EXCEPTION 'schedule_window_invalid'; END IF;
  INSERT INTO public.pedido_agendamento_pendente (user_id, restaurant_id, scheduled_for)
  VALUES (v_uid, p_restaurant_id, p_scheduled_for);
  RETURN jsonb_build_object('ok', true, 'agendado', true, 'restaurant_id', p_restaurant_id, 'scheduled_for', p_scheduled_for);
END;
$function$;

-- O gatilho de criação passa a ler também a marcação prévia.
CREATE OR REPLACE FUNCTION public._orders_agendado_na_criacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sched  timestamptz;
  v_pago   boolean := false;
  v_pend   uuid;
  v_cfg    jsonb;
  v_valid  boolean;
BEGIN
  IF NEW.scheduled_for IS NOT NULL THEN RETURN NEW; END IF;
  -- 1) pela RPC client_create_order_agendado
  v_sched := NULLIF(current_setting('app.agendar_para', true), '')::timestamptz;
  -- 2) marcação prévia deste cliente nesta loja
  IF v_sched IS NULL AND NEW.user_id IS NOT NULL AND NEW.restaurant_id IS NOT NULL THEN
    SELECT p.id, p.scheduled_for INTO v_pend, v_sched
      FROM public.pedido_agendamento_pendente p
     WHERE p.user_id = NEW.user_id AND p.restaurant_id = NEW.restaurant_id
       AND p.usado_em IS NULL AND p.expira_em > now()
     ORDER BY p.criado_em DESC
     LIMIT 1;
  END IF;
  -- 3) cartão pelo rascunho
  IF v_sched IS NULL AND NEW.payment_intent_id IS NOT NULL THEN
    SELECT NULLIF(d.payload->>'scheduled_for', '')::timestamptz INTO v_sched
      FROM public.payment_drafts d
     WHERE d.payment_intent_id = NEW.payment_intent_id
     ORDER BY d.created_at DESC
     LIMIT 1;
  END IF;
  IF v_sched IS NULL THEN RETURN NEW; END IF;

  v_pago := NEW.payment_intent_id IS NOT NULL OR COALESCE(NEW.payment_status, '') = 'paid'
            AND COALESCE(NEW.payment_method, 'cash') <> 'cash';
  v_cfg := public._sched_cfg();
  IF NOT v_pago THEN
    -- Ainda nada pago: a hora tem de ser uma janela válida desta loja, senão não há pedido.
    IF NOT (v_cfg->>'enabled')::boolean THEN RAISE EXCEPTION 'scheduled_orders_disabled'; END IF;
    IF NEW.restaurant_id IS NULL OR NEW.service_type NOT IN ('restaurant', 'storeShopping') THEN
      RAISE EXCEPTION 'schedule_not_supported';
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM jsonb_array_elements(
               public._sched_windows_core(NEW.restaurant_id, (v_sched AT TIME ZONE 'Europe/Lisbon')::date, 10)) w
       WHERE (w->>'inicio')::timestamptz = v_sched) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'schedule_window_invalid'; END IF;
    NEW.scheduled_for := v_sched;
  ELSE
    -- Já pago (cartão): basta a loja abrir nessa hora; se não, segue sem hora e a guarda decide como sempre.
    IF NEW.restaurant_id IS NOT NULL
       AND NEW.service_type IN ('restaurant', 'storeShopping')
       AND (v_cfg->>'enabled')::boolean
       AND v_sched > now()
       AND v_sched <= now() + make_interval(days => (v_cfg->>'max_days')::integer + 1)
       AND COALESCE((public.is_partner_open(NEW.restaurant_id, v_sched)->>'is_open')::boolean, false)
    THEN
      NEW.scheduled_for := v_sched;
    ELSE
      RAISE WARNING '_orders_agendado_na_criacao: hora % recusada num pedido ja pago (loja %)', v_sched, NEW.restaurant_id;
    END IF;
  END IF;
  IF v_pend IS NOT NULL AND NEW.scheduled_for IS NOT NULL THEN
    UPDATE public.pedido_agendamento_pendente SET usado_em = now(), order_id = NEW.id WHERE id = v_pend;
  END IF;
  RETURN NEW;
END;
$function$;

-- Painel: parceiro/não-parceiro e tipo de serviço para o filtro.
CREATE OR REPLACE FUNCTION public.admin_scheduled_orders()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_for, x.id)
      FROM (
        SELECT o.id, o.status, o.scheduled_for, o.restaurant_id,
               r.name AS restaurant_name, r.category AS restaurant_category,
               o.price, o.customer_name, o.payment_method, o.payment_status,
               o.prep_time_minutes, o.created_at,
               COALESCE(o.is_partner_store, false) AS is_partner_store, o.service_type
          FROM public.orders o
          LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
         WHERE o.scheduled_for IS NOT NULL
           AND o.scheduled_for > now() - interval '1 day'
           AND o.status NOT IN ('delivered', 'cancelled', 'rejected')
         ORDER BY o.scheduled_for, o.id
         LIMIT 300
      ) x
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL ON FUNCTION public.client_preparar_agendamento(text, timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_preparar_agendamento(text, timestamp with time zone) TO authenticated;
REVOKE ALL ON FUNCTION public._orders_agendado_na_criacao() FROM PUBLIC, anon, authenticated;
