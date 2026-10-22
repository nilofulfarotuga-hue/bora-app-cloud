-- Bloco D · ronda 1 do revisor (21/10/2026) — o vale do check-in no pedido, mais apertado.
-- F1: o vale so volta se o pedido nunca chegou a ser aceite pelo estafeta, levantado ou entregue
--     (historico real em order_status_events, que o cliente nao escreve) e nunca se a loja ja foi paga.
-- F2: o artigo-premio conta venha o campo como vier (productId, product_id, id, ...): qualquer
--     mencao a 'premio-checkin-' num artigo exige um vale valido do proprio cliente; e um cliente
--     com sessao nao usa vales de outra pessoa.
-- F3: a folga de 2 h depois do prazo so vale para um vale ja 'reservado' (pagamento a meio).
-- Mais: os artigos de um pedido ja criado nao ganham premios novos por escrita direta.
-- Nenhuma coluna do pedido muda; so se le a linha e se escreve na tabela dos vales.

-- Premios mencionados num artigo do pedido (qualquer campo).
CREATE OR REPLACE FUNCTION public._checkin_premio_ids_no_item(p_item jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(DISTINCT m[1] ORDER BY m[1]), '{}'::text[])
    FROM regexp_matches(COALESCE(p_item::text, ''), '(premio-checkin-[A-Za-z0-9_-]+)', 'g') AS m
$function$;

-- Quantidade de um artigo (o maior numero entre quantity / qty / quantidade; 1 se nada).
CREATE OR REPLACE FUNCTION public._checkin_premio_qtd_item(p_item jsonb)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT GREATEST(1, COALESCE(max(ceil((p_item ->> k)::numeric))::int, 1))
    FROM unnest(ARRAY['quantity', 'qty', 'quantidade']) AS k
   WHERE (p_item ->> k) ~ '^[0-9]+(\.[0-9]+)?$'
$function$;

-- Gasta um vale por cada artigo que menciona um premio; recusa tudo se faltar um vale valido.
CREATE OR REPLACE FUNCTION public._checkin_premio_consumir(p_user uuid, p_loja text, p_pedido text, p_items jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_it   jsonb;
  v_pid  text;
  v_qtd  integer;
  v_n    integer := 0;
  v_vale public.checkin_premios_vales;
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'checkin_premio_sem_vale: este prémio já não está disponível' USING ERRCODE = 'P0001';
  END IF;
  FOR v_it IN SELECT x FROM jsonb_array_elements(p_items) x LOOP
    FOREACH v_pid IN ARRAY public._checkin_premio_ids_no_item(v_it) LOOP
      v_qtd := public._checkin_premio_qtd_item(v_it);
      v_vale := NULL;
      SELECT * INTO v_vale
        FROM public.checkin_premios_vales c
       WHERE c.user_id = p_user
         AND c.produto_id = v_pid
         AND ((c.estado = 'por_usar' AND c.valido_ate > now())
           OR (c.estado = 'reservado' AND c.valido_ate > now() - interval '2 hours'))
       ORDER BY (c.estado = 'reservado') DESC, c.valido_ate
       LIMIT 1
       FOR UPDATE;
      IF v_vale.id IS NULL THEN
        RAISE EXCEPTION 'checkin_premio_sem_vale: este prémio já não está disponível' USING ERRCODE = 'P0001';
      END IF;
      IF v_vale.loja_id IS NOT NULL AND p_loja IS DISTINCT FROM v_vale.loja_id THEN
        RAISE EXCEPTION 'checkin_premio_loja_errada' USING ERRCODE = 'P0001';
      END IF;
      IF v_qtd > v_vale.quantidade THEN
        RAISE EXCEPTION 'checkin_premio_quantidade: o prémio vale % unidade(s)', v_vale.quantidade USING ERRCODE = 'P0001';
      END IF;
      UPDATE public.checkin_premios_vales
         SET estado = 'usado', usado_em = now(), pedido_id = p_pedido, reservado_ate = NULL, atualizado_em = now()
       WHERE id = v_vale.id;
      v_n := v_n + 1;
    END LOOP;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public._checkin_premio_no_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_quem uuid := auth.uid();
BEGIN
  -- o premio e de quem o ganhou: com sessao de cliente, o pedido tem de ser dele
  IF v_quem IS NOT NULL AND v_quem IS DISTINCT FROM NEW.user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'checkin_premio_de_outra_pessoa' USING ERRCODE = 'P0001';
  END IF;
  PERFORM public._checkin_premio_consumir(NEW.user_id, NEW.restaurant_id, NEW.id, NEW.items);
  RETURN NULL;
END;
$function$;

-- O vale so pode voltar se o pedido nunca chegou ao estafeta, a recolha ou a entrega.
CREATE OR REPLACE FUNCTION public._checkin_premio_pode_voltar(p_pedido text, p_estado_antes text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(p_estado_antes, '') IN ('created', 'preparing', 'callingDriver')
     AND NOT EXISTS (
           SELECT 1 FROM public.order_status_events e
            WHERE e.order_id = p_pedido
              AND (e.to_status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')
                OR e.from_status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')))
     AND NOT EXISTS (
           SELECT 1 FROM public.orders o
            WHERE o.id = p_pedido AND (o.delivered_at IS NOT NULL OR o.takeaway_picked_up_at IS NOT NULL))
$function$;

CREATE OR REPLACE FUNCTION public._checkin_premio_pedido_cancelado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public._checkin_premio_pode_voltar(NEW.id, OLD.status) THEN
    UPDATE public.checkin_premios_vales
       SET motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' passou a ' || NEW.status
                    || ' depois de ' || OLD.status || ': o vale não volta',
           atualizado_em = now()
     WHERE pedido_id = NEW.id AND estado = 'usado';
    RETURN NULL;
  END IF;
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NOT NULL AND valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, pedido_id = NULL, reservado_ate = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' ' || NEW.status,
         atualizado_em = now()
   WHERE pedido_id = NEW.id AND estado = 'usado' AND pago_loja_em IS NULL;
  RETURN NULL;
END;
$function$;

-- Os artigos de um pedido ja criado nao ganham premios novos (o preco ja esta fechado).
-- true se a lista nova traz um premio que a antiga nao tinha (ou mais vezes).
CREATE OR REPLACE FUNCTION public._checkin_premio_items_acrescenta(p_antes jsonb, p_depois jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_antes  text[] := '{}'::text[];
  v_depois text[] := '{}'::text[];
  v_it     jsonb;
BEGIN
  IF jsonb_typeof(p_antes) = 'array' THEN
    FOR v_it IN SELECT x FROM jsonb_array_elements(p_antes) x LOOP
      v_antes := v_antes || public._checkin_premio_ids_no_item(v_it);
    END LOOP;
  END IF;
  IF jsonb_typeof(p_depois) = 'array' THEN
    FOR v_it IN SELECT x FROM jsonb_array_elements(p_depois) x LOOP
      v_depois := v_depois || public._checkin_premio_ids_no_item(v_it);
    END LOOP;
  ELSE
    RETURN COALESCE(p_depois::text, '') LIKE '%premio-checkin-%';
  END IF;
  RETURN EXISTS (SELECT 1 FROM unnest(v_depois) d GROUP BY d
                  HAVING count(*) > (SELECT count(*) FROM unnest(v_antes) a WHERE a = d));
END;
$function$;

CREATE OR REPLACE FUNCTION public._checkin_premio_items_guarda()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF public._checkin_premio_items_acrescenta(OLD.items, NEW.items) THEN
    RAISE EXCEPTION 'checkin_premio_nao_se_acrescenta' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_premio_ids_no_item(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_qtd_item(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_consumir(uuid, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_no_pedido() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_pode_voltar(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_pedido_cancelado() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_items_acrescenta(jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_items_guarda() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_checkin_premio_items_guarda
  BEFORE UPDATE OF items ON public.orders
  FOR EACH ROW
  WHEN (NEW.items::text LIKE '%premio-checkin-%')
  EXECUTE FUNCTION public._checkin_premio_items_guarda();
