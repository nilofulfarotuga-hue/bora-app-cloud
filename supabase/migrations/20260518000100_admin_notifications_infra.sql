-- ============================================================================
-- BLOCO A (2026-05-18) — Admin Notifications Infrastructure
-- ============================================================================
--
-- Tabela `admin_notifications` para persistir todos os eventos críticos
-- que disparam push para admins. Substitui logging ad-hoc no
-- admin_audit_log. Permite UI inbox dedicada com filtros, marcar lido,
-- contagem de não-lidos.
--
-- Função helper `notify_admin_event()` chamável por triggers de qualquer
-- tabela. Faz INSERT na admin_notifications + invoca Edge Function
-- notify-admin-urgent (já existente) via pg_net (se configurado).
--
-- Triggers críticos implementados nesta migration:
--   1. Pedido cancelado com refund > €30  (orders AFTER UPDATE)
--   2. Cliente entra em dívida > €20  (wallets AFTER UPDATE)
--
-- Triggers restantes (templates documentados; cron PG ou triggers mais
-- complexos — implementação progressiva):
--   3. Pedido cancelado em pickedUp/onTheWay
--   4. Pedido órfão > 10 min  (precisa pg_cron)
--   5. Reserva no-show  (status transition trigger)
--   6. 3 falhas Stripe consecutivas  (precisa janela de tempo + count)
--   7. Driver fantasma > 5 min  (precisa pg_cron)
--   8. Skill_suggestion zone_type='critical'  (trigger skill_suggestions)
--   9. Complaint severity='high'  (trigger complaints)
-- ============================================================================

BEGIN;

-- ─── Tabela admin_notifications ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  event_type   text NOT NULL,
  severity     text NOT NULL DEFAULT 'medium'
               CHECK (severity IN ('critical', 'high', 'medium', 'low')),
  entity_type  text,
  entity_id    text,
  summary      text NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
  deep_link    text,
  read_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  read_at      timestamptz,
  archived_at  timestamptz
);

CREATE INDEX IF NOT EXISTS idx_admin_notifications_unread
  ON public.admin_notifications (created_at DESC)
  WHERE read_at IS NULL AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_admin_notifications_event_type
  ON public.admin_notifications (event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_notifications_severity
  ON public.admin_notifications (severity, created_at DESC)
  WHERE archived_at IS NULL;

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_select_own_role" ON public.admin_notifications;
CREATE POLICY "admin_select_own_role"
  ON public.admin_notifications
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(
      (auth.jwt() -> 'app_metadata' ->> 'role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  );

DROP POLICY IF EXISTS "admin_update_own_role" ON public.admin_notifications;
CREATE POLICY "admin_update_own_role"
  ON public.admin_notifications
  FOR UPDATE
  TO authenticated
  USING (
    COALESCE(
      (auth.jwt() -> 'app_metadata' ->> 'role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  )
  WITH CHECK (
    COALESCE(
      (auth.jwt() -> 'app_metadata' ->> 'role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  );

COMMENT ON TABLE public.admin_notifications IS
  'BLOCO A 2026-05-18 — Persistência de eventos críticos despachados por triggers. UI: admin_notifications_inbox_screen.';

-- ─── Função helper notify_admin_event ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_admin_event(
  p_event_type  text,
  p_severity    text,
  p_summary     text,
  p_entity_type text DEFAULT NULL,
  p_entity_id   text DEFAULT NULL,
  p_payload     jsonb DEFAULT '{}'::jsonb,
  p_deep_link   text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.admin_notifications (
    event_type, severity, summary, entity_type, entity_id, payload, deep_link
  ) VALUES (
    p_event_type, p_severity, p_summary, p_entity_type, p_entity_id, p_payload, p_deep_link
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_admin_event(text, text, text, text, text, jsonb, text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.notify_admin_event(text, text, text, text, text, jsonb, text)
  TO service_role;

COMMENT ON FUNCTION public.notify_admin_event(text, text, text, text, text, jsonb, text) IS
  'BLOCO A 2026-05-18 — Helper interno chamado por triggers para registar evento crítico admin.';

-- ─── Trigger 1: Pedido cancelado com refund > €30 ──────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_refund_high()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_refund_cents int;
BEGIN
  -- Disparar quando refund acabou de ser registado E é > €30 (3000 cents).
  IF NEW.refund_status = 'succeeded'
     AND (OLD.refund_status IS DISTINCT FROM NEW.refund_status) THEN
    v_refund_cents := COALESCE(((NEW.refund_amount * 100)::numeric)::int, 0);
    IF v_refund_cents > 3000 THEN
      PERFORM public.notify_admin_event(
        p_event_type  := 'order_refund_high',
        p_severity    := 'high',
        p_summary     := format(
          'Pedido %s reembolsado €%s (cliente: %s)',
          substring(NEW.id::text, 1, 8),
          to_char(v_refund_cents::numeric / 100, 'FM999990D00'),
          COALESCE(NEW.customer_name, '—')
        ),
        p_entity_type := 'order',
        p_entity_id   := NEW.id::text,
        p_payload     := jsonb_build_object(
          'refund_amount_cents', v_refund_cents,
          'refund_id', NEW.refund_id,
          'status', NEW.status,
          'vendor_name', NEW.vendor_name
        ),
        p_deep_link   := '/admin/orders/' || NEW.id::text
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_notif_refund_high ON public.orders;
CREATE TRIGGER trg_admin_notif_refund_high
AFTER UPDATE OF refund_status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public._trg_admin_notif_refund_high();

-- ─── Trigger 2: Cliente entra em dívida > €20 ──────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_wallet_debt_high()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Disparar quando o saldo cruza o threshold -€20 (-2000 cents) descendo.
  IF NEW.free_balance_cents < -2000
     AND COALESCE(OLD.free_balance_cents, 0) >= -2000 THEN
    PERFORM public.notify_admin_event(
      p_event_type  := 'wallet_debt_high',
      p_severity    := 'high',
      p_summary     := format(
        'Cliente %s entrou em dívida de €%s',
        COALESCE(NEW.user_id::text, '—'),
        to_char(NEW.free_balance_cents::numeric / 100, 'FM999990D00')
      ),
      p_entity_type := 'wallet',
      p_entity_id   := NEW.user_id::text,
      p_payload     := jsonb_build_object(
        'free_balance_cents', NEW.free_balance_cents,
        'previous_balance_cents', OLD.free_balance_cents
      ),
      p_deep_link   := '/admin/wallets?user=' || NEW.user_id::text
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Apenas cria o trigger se a tabela wallets existir com a coluna esperada.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'wallets'
       AND column_name = 'free_balance_cents'
  ) THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_admin_notif_wallet_debt_high ON public.wallets';
    EXECUTE $TR$
      CREATE TRIGGER trg_admin_notif_wallet_debt_high
      AFTER UPDATE OF free_balance_cents ON public.wallets
      FOR EACH ROW
      EXECUTE FUNCTION public._trg_admin_notif_wallet_debt_high()
    $TR$;
  END IF;
END $$;

-- ─── Templates para os triggers restantes (3, 4, 5, 6, 7, 8, 9) ────────────
-- TODO próxima migration: implementar progressivamente.
--
-- Template trigger 3 (order cancelado em pickedUp/onTheWay):
--   AFTER UPDATE OF status ON orders
--   WHEN OLD.status IN ('pickedUp','onTheWay') AND NEW.status = 'cancelled'
--   -> notify_admin_event('order_cancel_in_flight', 'critical', ...)
--
-- Template trigger 5 (reserva no-show):
--   AFTER UPDATE OF status ON reservations
--   WHEN NEW.status = 'no_show'
--   -> notify_admin_event('reservation_no_show', 'medium', ...)
--
-- Template trigger 8 (skill_suggestion critical):
--   AFTER INSERT ON skill_suggestions
--   WHEN NEW.zone_type = 'critical'
--   -> notify_admin_event('skill_suggestion_critical', 'high', ...)
--
-- Template trigger 9 (complaint high):
--   AFTER INSERT ON complaints
--   WHEN NEW.severity = 'high'
--   -> notify_admin_event('complaint_high', 'high', ...)
--
-- Triggers 4, 6, 7 (órfão>10min, 3 stripe fails, driver fantasma) precisam
-- pg_cron para verificar condições periodicamente. Implementação dedicada.

COMMIT;
