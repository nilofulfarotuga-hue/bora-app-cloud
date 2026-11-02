-- APLICADA EM PRODUÇÃO a 02/11/2026 (versão 20261102062513, pela sessão de retoma Opus).
-- Copiar tal e qual para supabase/migrations/ (a bora-tranca recusa esta escrita na sessão).
-- Missão stripe-empresa-2026-11-01 (autorizo do Danilo 01/11/2026 22:03). Proposta 05 sem DROP:
-- a função antiga fica com outro nome (sem uso) e a nova traz a coluna stripe_account.
alter function public.admin_list_payments(text, text, integer, integer) rename to admin_list_payments_antes_20261102;

create function public.admin_list_payments(p_vertical text default null::text, p_search text default null::text, p_limit integer default 200, p_offset integer default 0)
 returns table(vertical text, entity_id text, user_id uuid, payment_intent_id text, amount_cents integer, status text, payment_method text, created_at timestamp with time zone, stripe_account text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
           o.created_at,
           o.stripe_account
    FROM orders o

    UNION ALL
    SELECT 'reserva', r.id::text, r.client_user_id, r.prepayment_pi,
           r.prepayment_cents, r.status, 'card', r.created_at, r.stripe_account
    FROM reservations r

    UNION ALL
    SELECT 'marcacao', a.id::text, a.client_user_id, a.deposit_pi,
           a.deposit_cents, coalesce(a.full_payment_status, a.status), 'card', a.created_at, a.stripe_account
    FROM appointments a

    UNION ALL
    SELECT 'tvde', t.id::text, t.client_id, t.payment_intent_id,
           coalesce(t.final_fare_cents, t.est_fare_cents), t.payment_status,
           t.payment_method, t.created_at, 'pessoal'::text
    FROM tvde_rides t

    UNION ALL
    SELECT 'tvde_plano', s.id::text, s.client_id, s.stripe_payment_intent_id,
           s.price_cents, s.payment_status, 'card', s.created_at, 'pessoal'::text
    FROM tvde_subscriptions s

    UNION ALL
    SELECT 'limpeza', c.id::text, c.client_user_id, c.stripe_payment_intent_id,
           c.total_cents, c.payment_status, c.payment_method, c.created_at, c.stripe_account
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
$function$;

-- Mesmas permissões que a antiga: só postgres, authenticated e service_role.
revoke all on function public.admin_list_payments(text, text, integer, integer) from public;
revoke all on function public.admin_list_payments(text, text, integer, integer) from anon;
grant execute on function public.admin_list_payments(text, text, integer, integer) to authenticated, service_role;
