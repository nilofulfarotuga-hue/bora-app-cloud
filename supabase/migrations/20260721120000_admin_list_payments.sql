-- admin_list_payments() — Carteira Única, Parte 6/6 (2026-07-21)
--
-- Histórico de cobranças de TODAS as verticais numa só lista, para a aba admin
-- "Pagamentos/Cartões". Não existe tabela central de pagamentos: cada vertical
-- guarda o seu PaymentIntent na sua própria tabela. Esta função só faz a UNION.
--
-- ESTRITAMENTE READ-ONLY. Não faz INSERT/UPDATE/DELETE, não altera nenhum valor
-- cobrado nem pago. É SECURITY DEFINER apenas porque as políticas RLS de
-- appointments/tvde_rides são user-scoped e o admin não as atravessa — o mesmo
-- padrão de admin_list_orphans().
--
-- Guarda de acesso igual ao resto do painel: app_metadata.role = 'admin'.

CREATE OR REPLACE FUNCTION public.admin_list_payments(
  p_vertical text DEFAULT NULL,   -- 'delivery'|'reserva'|'marcacao'|'tvde'|'tvde_plano'|'limpeza'
  p_search   text DEFAULT NULL,   -- id da entidade, PaymentIntent ou user_id
  p_limit    int  DEFAULT 200,
  p_offset   int  DEFAULT 0
)
RETURNS TABLE (
  vertical          text,
  entity_id         text,
  user_id           uuid,
  payment_intent_id text,
  amount_cents      int,
  status            text,
  payment_method    text,
  created_at        timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF coalesce((auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' THEN
    RAISE EXCEPTION 'unauthorized: admin only';
  END IF;

  RETURN QUERY
  WITH todos AS (
    SELECT 'delivery'::text AS vertical,
           o.id::text,
           o.user_id,
           o.payment_intent_id,
           coalesce(o.stripe_charge_cents, round(coalesce(o.total, 0) * 100)::int),
           o.payment_status,
           o.payment_method,
           o.created_at
    FROM orders o

    UNION ALL
    SELECT 'reserva', r.id::text, r.client_user_id, r.prepayment_pi,
           r.prepayment_cents, r.status, 'card', r.created_at
    FROM reservations r

    UNION ALL
    SELECT 'marcacao', a.id::text, a.client_user_id, a.deposit_pi,
           a.deposit_cents, coalesce(a.full_payment_status, a.status), 'card', a.created_at
    FROM appointments a

    UNION ALL
    SELECT 'tvde', t.id::text, t.client_id, t.payment_intent_id,
           coalesce(t.final_fare_cents, t.est_fare_cents), t.payment_status,
           t.payment_method, t.created_at
    FROM tvde_rides t

    UNION ALL
    SELECT 'tvde_plano', s.id::text, s.client_id, s.stripe_payment_intent_id,
           s.price_cents, s.payment_status, 'card', s.created_at
    FROM tvde_subscriptions s

    UNION ALL
    SELECT 'limpeza', c.id::text, c.client_user_id, c.stripe_payment_intent_id,
           c.total_cents, c.payment_status, c.payment_method, c.created_at
    FROM cleaning_bookings c
  )
  SELECT *
  FROM todos
  WHERE (p_vertical IS NULL OR todos.vertical = p_vertical)
    AND (
      p_search IS NULL OR p_search = ''
      OR todos.entity_id ILIKE '%' || p_search || '%'
      OR coalesce(todos.payment_intent_id, '') ILIKE '%' || p_search || '%'
      OR todos.user_id::text = p_search
    )
  ORDER BY todos.created_at DESC
  LIMIT greatest(1, least(p_limit, 1000))
  OFFSET greatest(0, p_offset);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_payments(text, text, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_payments(text, text, int, int) TO authenticated;

COMMENT ON FUNCTION public.admin_list_payments(text, text, int, int) IS
  'Carteira Unica P6: historico de cobrancas de todas as verticais (READ-ONLY, admin).';
