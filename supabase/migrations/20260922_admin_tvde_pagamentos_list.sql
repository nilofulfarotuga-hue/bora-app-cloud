-- Painel admin — pagamentos das corridas TVDE (2026-09-22)
--
-- Porquê: a 21 e 22/09 sete corridas morreram por pagamento e o Danilo só
-- soube das duas que lhe contaram. Os clientes ficaram sem corrida, ninguém
-- lhes ligou, e não havia sítio nenhum no painel onde isso aparecesse.
--
-- Função aditiva e SÓ DE LEITURA. Não toca na `admin_tvde_rides_list`, que
-- continua exactamente como está — o ecrã "Corridas" não é afectado.
--
-- Guarda: `_admin_op_guard()`, o mesmo das outras RPC do painel.

CREATE OR REPLACE FUNCTION public.admin_tvde_pagamentos_list(
  p_scope text DEFAULT 'todos',
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 1000 THEN RAISE EXCEPTION 'limit 1..1000'; END IF;

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      ride.created_at AS created_at,
      jsonb_build_object(
        'id',                 ride.id,
        'created_at',         ride.created_at,
        'status',             ride.status,
        'payment_method',     ride.payment_method,
        'payment_status',     ride.payment_status,
        'payment_intent_id',  ride.payment_intent_id,
        'est_fare_cents',     ride.est_fare_cents,
        'final_fare_cents',   ride.final_fare_cents,
        'cancel_fee_cents',   ride.cancel_fee_cents,
        'cancel_reason',      ride.cancel_reason,
        'origin_label',       ride.origin_label,
        'dest_label',         ride.dest_label,
        'client_id',          ride.client_id,
        -- cliente de balcão não tem linha em auth.users: public.users manda.
        'client_name',        COALESCE(NULLIF(trim(u.name), ''),
                                       au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',       COALESCE(NULLIF(trim(u.phone), ''),
                                       au.raw_user_meta_data->>'bora_phone', ''),
        'client_email',       u.email,
        -- contas de ensaio não entram na lista de quem se liga a pedir desculpa
        'is_demo',            COALESCE(u.is_counter_client, false)
      ) AS row
    FROM public.tvde_rides ride
    LEFT JOIN auth.users au  ON au.id = ride.client_id
    LEFT JOIN public.users u ON u.id = ride.client_id
    WHERE ride.payment_method IN ('card','mbway')
      AND CASE
        -- Quem tentou pagar e não conseguiu. É esta a lista para ligar.
        WHEN p_scope = 'falhados' THEN
          COALESCE(ride.cancel_reason,'') IN
            ('payment_failed','payment_abandoned','payment_timeout')
          OR (ride.status LIKE 'cancelada%'
              AND COALESCE(ride.payment_status,'') IN
                ('requires_payment_method','requires_action'))
        -- Dinheiro que entrou mesmo (ou que já foi devolvido).
        WHEN p_scope = 'pagos' THEN
          COALESCE(ride.payment_status,'') IN
            ('succeeded','processing','refunded','partial_refund','kept_cancel_fee')
        ELSE true
      END
    ORDER BY ride.created_at DESC
    LIMIT p_limit
  ) s;

  RETURN v_out;
END; $function$;

REVOKE ALL ON FUNCTION public.admin_tvde_pagamentos_list(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_tvde_pagamentos_list(text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_pagamentos_list(text, integer) TO authenticated;

COMMENT ON FUNCTION public.admin_tvde_pagamentos_list(text, integer) IS
  'Painel admin: pagamentos das corridas TVDE. Só de leitura, guarda _admin_op_guard(). Scopes: todos | pagos | falhados. Criada 2026-09-22 (missão pagamento-cartao-2026-09-22).';
