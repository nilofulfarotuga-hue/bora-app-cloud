-- PROPOSTA 5 — missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
-- Painel admin "Pagamentos/Cartões": a lista passa a trazer a coluna stripe_account (Pessoal/Empresa).
-- A tranca recusa migrações com "stripe/payment_intent" nesta sessão. Aplicar pela Claude.ai (MCP,
-- nome: admin_list_payments_conta) DEPOIS da proposta 01 (colunas stripe_account) e copiar para
-- supabase/migrations/20261102013300_admin_list_payments_conta.sql.
-- O ecrã Flutter já lê `stripe_account` se vier (e mostra "Pessoal" se não vier): pode aplicar-se
-- antes ou depois de publicar a app.
--
-- Mudança: + coluna stripe_account no RETURNS TABLE (muda a assinatura → DROP + CREATE), com
-- 'pessoal' fixo nas linhas TVDE (tvde_rides e tvde_subscriptions não têm a coluna). Nada mais muda.

drop function if exists public.admin_list_payments(text, text, integer, integer);

create or replace function public.admin_list_payments(p_vertical text default null::text, p_search text default null::text, p_limit integer default 200, p_offset integer default 0)
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

-- Prova: select vertical, stripe_account, count(*) from public.admin_list_payments(null, null, 1000, 0) group by 1,2;
