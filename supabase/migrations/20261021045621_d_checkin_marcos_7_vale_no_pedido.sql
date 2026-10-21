-- Bloco D · fechar-pendencias-2026-10-20 — o vale do check-in no pedido.
-- Dois gatilhos aditivos em orders, que so correm quando o pedido traz um artigo-premio
-- (productId 'premio-checkin-...'): nao tocam em nenhuma coluna do pedido nem em
-- nenhum valor; so leem a linha nova e escrevem na tabela dos vales.
--  * ao criar: confirma o vale da pessoa para esse artigo (por usar ou reservado, dentro
--    do prazo, mesma loja, quantidade) e marca-o usado; sem vale, o pedido e recusado
--    (ninguem leva o artigo a 0 EUR sem o ter ganho).
--  * ao cancelar/rejeitar: o vale volta a "por usar" (ou fica expirado se ja passou o prazo).

CREATE OR REPLACE FUNCTION public._checkin_premio_no_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_it   jsonb;
  v_pid  text;
  v_qtd  integer;
  v_vale public.checkin_premios_vales;
BEGIN
  IF jsonb_typeof(NEW.items) IS DISTINCT FROM 'array' THEN
    RETURN NULL;
  END IF;
  FOR v_it IN SELECT x FROM jsonb_array_elements(NEW.items) x LOOP
    v_pid := v_it ->> 'productId';
    CONTINUE WHEN v_pid IS NULL OR v_pid NOT LIKE 'premio-checkin-%';
    v_qtd := GREATEST(COALESCE((v_it ->> 'quantity')::int, 1), 1);

    SELECT * INTO v_vale
      FROM public.checkin_premios_vales c
     WHERE c.user_id = NEW.user_id
       AND c.produto_id = v_pid
       AND c.estado IN ('reservado','por_usar')
       AND (c.valido_ate IS NULL OR c.valido_ate > now() - interval '2 hours')
     ORDER BY (c.estado = 'reservado') DESC, c.valido_ate NULLS LAST
     LIMIT 1
     FOR UPDATE;

    IF v_vale.id IS NULL THEN
      RAISE EXCEPTION 'checkin_premio_sem_vale: este prémio já não está disponível' USING ERRCODE = 'P0001';
    END IF;
    IF v_vale.loja_id IS NOT NULL AND NEW.restaurant_id IS DISTINCT FROM v_vale.loja_id THEN
      RAISE EXCEPTION 'checkin_premio_loja_errada' USING ERRCODE = 'P0001';
    END IF;
    IF v_qtd > v_vale.quantidade THEN
      RAISE EXCEPTION 'checkin_premio_quantidade: o prémio vale % unidade(s)', v_vale.quantidade USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.checkin_premios_vales
       SET estado = 'usado', usado_em = now(), pedido_id = NEW.id, reservado_ate = NULL, atualizado_em = now()
     WHERE id = v_vale.id;
    v_vale := NULL;
  END LOOP;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public._checkin_premio_pedido_cancelado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NULL OR valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, pedido_id = NULL, reservado_ate = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' ' || NEW.status,
         atualizado_em = now()
   WHERE pedido_id = NEW.id AND estado = 'usado';
  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_premio_no_pedido() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_pedido_cancelado() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_checkin_premio_no_pedido
  AFTER INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.items::text LIKE '%premio-checkin-%')
  EXECUTE FUNCTION public._checkin_premio_no_pedido();

CREATE OR REPLACE TRIGGER trg_checkin_premio_pedido_cancelado
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IN ('cancelled','rejected')
        AND OLD.status IS DISTINCT FROM NEW.status
        AND NEW.items::text LIKE '%premio-checkin-%')
  EXECUTE FUNCTION public._checkin_premio_pedido_cancelado();
