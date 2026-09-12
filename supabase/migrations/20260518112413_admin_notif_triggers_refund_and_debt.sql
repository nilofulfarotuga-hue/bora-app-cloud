-- Admin notification triggers: high refund + wallet debt
-- Applied via MCP on 2026-05-18, local file created on same date

CREATE OR REPLACE FUNCTION public._trg_admin_notif_refund_high_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_amount_cents int;
  v_summary text;
BEGIN
  IF NEW.refund_status = 'succeeded'
     AND (OLD.refund_status IS DISTINCT FROM 'succeeded') THEN

    v_amount_cents := COALESCE((NEW.refund_amount * 100)::int, 0);

    IF v_amount_cents > 3000 THEN  -- > €30
      v_summary := format(
        'Reembolso alto: €%s no pedido #%s',
        to_char(NEW.refund_amount, 'FM999990.00'),
        substring(NEW.id::text, 1, 8)
      );

      PERFORM public.notify_admin_event(
        'order_refund_high',
        'high',
        v_summary,
        'order',
        NEW.id::text,
        jsonb_build_object(
          'refund_amount', NEW.refund_amount,
          'refund_method', NEW.refund_method,
          'order_status', NEW.status
        ),
        '/admin/orders/' || NEW.id::text
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_refund_high
  AFTER UPDATE OF refund_status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_refund_high_fn();

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_wallet_debt_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_summary text;
  v_email   text;
BEGIN
  IF NEW.free_balance_cents < -2000  -- < -€20
     AND (OLD.free_balance_cents IS NULL OR OLD.free_balance_cents >= -2000) THEN

    SELECT email INTO v_email FROM auth.users WHERE id = NEW.user_id;

    v_summary := format(
      'Cliente em dívida alta: €%s (%s)',
      to_char(NEW.free_balance_cents::numeric / -100, 'FM999990.00'),
      COALESCE(v_email, NEW.user_id::text)
    );

    PERFORM public.notify_admin_event(
      'wallet_debt_high',
      'high',
      v_summary,
      'client',
      NEW.user_id::text,
      jsonb_build_object(
        'free_balance_cents', NEW.free_balance_cents,
        'email', v_email
      ),
      '/admin/wallets'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_wallet_debt_high
  AFTER UPDATE OF free_balance_cents ON public.client_wallets
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_wallet_debt_fn();
