-- C4 (lado do servidor) — pedidos de PARCEIRO: quando chamar o estafeta sozinho
-- (ronda 04/10/2026, agente despacho)
--
-- Antes: o cron partner-auto-dispatch passava TODO o pedido de parceiro aceite a
-- callingDriver 5 min depois de a loja aceitar — ignorava o tempo de preparação
-- e a data marcada (encomenda de festa para sábado chamava estafeta na terça).
--
-- Regra decidida (aplicada tal e qual):
--   • com scheduled_for (agendado / encomenda de festa):
--       chama em scheduled_for − dispatch_antecedencia_agendado_minutos (30), nunca antes;
--   • sem data marcada:
--       chama em accepted_at + greatest(0, prep_time_minutes − dispatch_antecedencia_minutos (8));
--       sem prep_time_minutes fica como hoje (partner_auto_dispatch_after_minutes, 5).
--   • o parceiro pode sempre carregar "Chamar estafeta já" (a app muda o estado na hora).
-- O porteiro das lojas por telefone (aa_orders_encomenda_telefone_porteiro +
-- cron encomendas-telefone-relogio) não é tocado: só trata lojas NÃO-parceiras.

INSERT INTO public.platform_settings(key, value, description, category) VALUES
  ('dispatch_antecedencia_minutos', '8'::jsonb,
   'Parceiros: chamar o estafeta X min antes do fim do tempo de preparação (accepted_at + prep − X).', 'dispatch'),
  ('dispatch_antecedencia_agendado_minutos', '30'::jsonb,
   'Parceiros, pedidos com data marcada: chamar o estafeta X min antes da hora marcada (nunca antes).', 'dispatch')
ON CONFLICT (key) DO NOTHING;

-- Hora em que a loja aceitou (passou a preparing).
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS accepted_at timestamptz;
COMMENT ON COLUMN public.orders.accepted_at IS
  'Quando o pedido passou a preparing (loja aceitou). Base da chamada automática do estafeta nos parceiros.';

CREATE OR REPLACE FUNCTION public._orders_set_accepted_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'preparing'
     AND NEW.accepted_at IS NULL
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'preparing') THEN
    NEW.accepted_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.orders'::regclass AND tgname = 'trg_orders_set_accepted_at') THEN
    CREATE TRIGGER trg_orders_set_accepted_at
      BEFORE INSERT OR UPDATE OF status ON public.orders
      FOR EACH ROW EXECUTE FUNCTION public._orders_set_accepted_at();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.partner_auto_dispatch_ready_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_min     integer;
  v_ant     integer;
  v_ant_ag  integer;
  v_order   record;
BEGIN
  SELECT (value::text)::integer INTO v_min
    FROM public.platform_settings
   WHERE key = 'partner_auto_dispatch_after_minutes';
  v_min := COALESCE(v_min, 5);
  IF v_min <= 0 THEN RETURN; END IF;   -- interruptor: 0 desliga a chamada automática

  SELECT (value::text)::integer INTO v_ant
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_minutos';
  v_ant := GREATEST(COALESCE(v_ant, 8), 0);
  SELECT (value::text)::integer INTO v_ant_ag
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_agendado_minutos';
  v_ant_ag := GREATEST(COALESCE(v_ant_ag, 30), 0);

  FOR v_order IN
    SELECT id
      FROM public.orders
     WHERE status = 'preparing'
       AND COALESCE(is_partner_store, false)
       AND service_type = 'restaurant'
       AND assigned_driver_id IS NULL
       AND driver_id IS NULL
       AND (COALESCE(payment_method, 'cash') = 'cash' OR payment_status = 'paid')
       AND now() >= CASE
             WHEN scheduled_for IS NOT NULL
               THEN scheduled_for - make_interval(mins => v_ant_ag)
             WHEN prep_time_minutes IS NOT NULL
               THEN COALESCE(accepted_at, status_updated_at)
                    + make_interval(mins => GREATEST(0, prep_time_minutes - v_ant))
             ELSE COALESCE(accepted_at, status_updated_at) + make_interval(mins => v_min)
           END
     ORDER BY COALESCE(accepted_at, status_updated_at)
     LIMIT 50
     FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM set_config('app.order_transition_source',
                         'partner_auto_dispatch_ready_orders', true);
      UPDATE public.orders SET status = 'callingDriver'
       WHERE id = v_order.id AND status = 'preparing';
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_lifecycle_errors(
        order_id, component, error_message
      ) VALUES (
        v_order.id, 'partner_auto_dispatch_ready_orders', SQLERRM
      );
    END;
  END LOOP;
END;
$function$;
