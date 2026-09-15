-- BLOCO D5 (2026-09-04/05) — dois quadros novos no painel admin (PT-BR):
-- 1) Avisos (push) que falharam nas últimas 24h.
-- 2) Marcações (reservas) presas, com botão "libertar" — SEM tocar em dinheiro.
--
-- ── Achado de segurança (bónus, corrigido aqui) ─────────────────────────────
-- `notification_failures` (criada em 20260718003000) tinha RLS DESLIGADA e
-- GRANT completo (select/insert/update/delete/truncate) a `anon` E
-- `authenticated` — ou seja, qualquer pedido não autenticado conseguia ler,
-- escrever OU apagar a tabela inteira. As funções que lá gravam
-- (_cleaning_notify_user, carwash) são SECURITY DEFINER — correm com o
-- privilégio do dono (postgres) e por isso NÃO precisam do grant directo a
-- anon/authenticated. Fechamos o buraco e só o admin passa a ler.
--
-- ── reservations: faltava policy de leitura para admin ──────────────────────
-- `admin_reservations_screen.dart` já faz `.from('reservations').select()`
-- direto, mas só existiam policies de owner (cliente) e parceiro — sem
-- policy admin a tabela ficava invisível para o painel. Policy adicional,
-- não-destrutiva.
--
-- ── Reservas presas: RPC de listagem + RPC de libertar ───────────────────────
-- "Libertar" só actua em reservas sem NENHUM pagamento associado
-- (prepayment_pi IS NULL) — nunca mexe em reserva que já tenha um
-- PaymentIntent da Stripe ligado. Se tiver, a RPC recusa com
-- 'requires_refund_manual_review' e o ecrã mostra "CONFIRMAÇÃO NECESSÁRIA"
-- em vez de decidir sozinho.

BEGIN;

-- ── 1) Hardening notification_failures ──────────────────────────────────────
ALTER TABLE public.notification_failures ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.notification_failures FROM anon, authenticated;
REVOKE SELECT ON public.notification_failures FROM anon;

DROP POLICY IF EXISTS "notification_failures_select_admin" ON public.notification_failures;
CREATE POLICY "notification_failures_select_admin"
  ON public.notification_failures
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

COMMENT ON TABLE public.notification_failures IS
  'Falhas de envio de notificação (push/in-app), gravadas pelas funções SECURITY DEFINER que enviam avisos. Leitura só admin (painel: quadro "Avisos que falharam"). Escrita só via SECURITY DEFINER (bypassa RLS) — nenhum grant directo a anon/authenticated.';

-- ── 2) reservations: policy de leitura para admin ───────────────────────────
DROP POLICY IF EXISTS "reservations_admin_read" ON public.reservations;
CREATE POLICY "reservations_admin_read"
  ON public.reservations
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- ── 3) admin_stuck_reservations — listar reservas presas em pending/pending_payment ──
CREATE OR REPLACE FUNCTION public.admin_stuck_reservations(p_minutes integer DEFAULT 60)
RETURNS TABLE (
  id uuid,
  restaurant_id text,
  restaurant_name text,
  client_name text,
  client_phone text,
  people integer,
  reserved_for timestamptz,
  status text,
  prepayment_cents integer,
  prepayment_pi text,
  created_at timestamptz,
  minutes_stuck integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.restaurant_id,
    rest.name,
    r.client_name,
    r.client_phone,
    r.people,
    r.reserved_for,
    r.status,
    r.prepayment_cents,
    r.prepayment_pi,
    r.created_at,
    (EXTRACT(EPOCH FROM (now() - r.created_at)) / 60)::integer AS minutes_stuck
  FROM public.reservations r
  LEFT JOIN public.restaurants rest ON rest.id = r.restaurant_id
  WHERE r.status IN ('pending', 'pending_payment')
    AND r.created_at < now() - (p_minutes || ' minutes')::interval
  ORDER BY r.created_at ASC
  LIMIT 200;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_stuck_reservations(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_stuck_reservations(integer) TO authenticated;

COMMENT ON FUNCTION public.admin_stuck_reservations(integer) IS
  'Lista reservas em pending/pending_payment há mais de p_minutes. Admin-only (is_admin()). Usado pelo quadro "Marcações presas" do painel admin.';

-- ── 4) admin_release_stuck_reservation — libertar SEM tocar em dinheiro ─────
CREATE OR REPLACE FUNCTION public.admin_release_stuck_reservation(
  p_reservation_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rsv record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  SELECT * INTO v_rsv FROM public.reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  IF v_rsv.status NOT IN ('pending', 'pending_payment') THEN
    RAISE EXCEPTION 'not_stuck: status is %', v_rsv.status;
  END IF;

  -- Trava de dinheiro: só liberta se NENHUM PaymentIntent está associado.
  -- Se houver, a reserva pode ter sido cobrada — exige revisão humana na
  -- Stripe antes de qualquer cancelamento (Lista Vermelha).
  IF v_rsv.prepayment_pi IS NOT NULL THEN
    RAISE EXCEPTION 'requires_refund_manual_review: reserva tem PaymentIntent % associado — confirme na Stripe antes de libertar', v_rsv.prepayment_pi;
  END IF;

  UPDATE public.reservations
  SET status = 'cancelled_by_admin',
      cancelled_at = now(),
      cancel_reason = COALESCE(p_reason, 'Libertada pelo admin — presa, sem pagamento associado')
  WHERE id = p_reservation_id;

  PERFORM log_admin_action(
    'admin_release_stuck_reservation',
    'reservation',
    p_reservation_id::text,
    jsonb_build_object('previous_status', v_rsv.status, 'reason', p_reason)
  );

  RETURN jsonb_build_object('success', true, 'status', 'cancelled_by_admin');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_release_stuck_reservation(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_release_stuck_reservation(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_release_stuck_reservation(uuid, text) IS
  'Liberta reserva presa em pending/pending_payment (status -> cancelled_by_admin). Recusa (requires_refund_manual_review) se houver PaymentIntent associado — nunca mexe em dinheiro. Admin-only. Audita em admin_audit_log.';

COMMIT;
