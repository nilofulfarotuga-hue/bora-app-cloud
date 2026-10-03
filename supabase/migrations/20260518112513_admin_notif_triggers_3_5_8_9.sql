-- Admin notification triggers: cancel mid-delivery, reservation no-show,
-- skill critical, complaint high
-- Applied via MCP on 2026-05-18, local file created on same date

CREATE OR REPLACE FUNCTION public._trg_admin_notif_cancel_mid_delivery_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_summary text;
BEGIN
  IF NEW.status IN ('cancelled', 'cancelledByAdmin', 'cancelledByDriver')
     AND OLD.status IN ('pickedUp', 'onTheWay')
     AND OLD.status IS DISTINCT FROM NEW.status THEN

    v_summary := format(
      'Pedido #%s cancelado em %s — driver desistiu',
      substring(NEW.id::text, 1, 8),
      OLD.status
    );

    PERFORM public.notify_admin_event(
      'order_cancel_mid_delivery',
      'critical',
      v_summary,
      'order',
      NEW.id::text,
      jsonb_build_object(
        'previous_status', OLD.status,
        'new_status', NEW.status,
        'driver_id', NEW.driver_id,
        'price', NEW.price
      ),
      '/admin/orders/' || NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_cancel_mid_delivery
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_cancel_mid_delivery_fn();

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_reservation_noshow_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_summary text;
BEGIN
  IF NEW.status = 'no_show'
     AND OLD.status IS DISTINCT FROM 'no_show' THEN

    v_summary := format(
      'No-show na reserva #%s (restaurante %s)',
      substring(NEW.id::text, 1, 8),
      COALESCE(NEW.restaurant_id, '?')
    );

    PERFORM public.notify_admin_event(
      'reservation_noshow',
      'medium',
      v_summary,
      'reservation',
      NEW.id::text,
      jsonb_build_object(
        'restaurant_id', NEW.restaurant_id,
        'client_user_id', NEW.client_user_id
      ),
      '/admin/reservations'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_reservation_noshow
  AFTER UPDATE OF status ON public.reservations
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_reservation_noshow_fn();

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_skill_critical_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_summary text;
BEGIN
  IF NEW.zone_type = 'critical'
     AND NEW.status = 'pending' THEN

    v_summary := format(
      'Sugestão crítica do bot IA: %s',
      substring(NEW.pattern_summary, 1, 120)
    );

    PERFORM public.notify_admin_event(
      'skill_suggestion_critical',
      'high',
      v_summary,
      'skill_suggestion',
      NEW.id::text,
      jsonb_build_object(
        'proposal_type', NEW.proposal_type,
        'pattern_summary', NEW.pattern_summary
      ),
      '/admin/skill-suggestions'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_skill_critical
  AFTER INSERT ON public.skill_suggestions
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_skill_critical_fn();

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_admin_notif_complaint_high_fn()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_summary text;
BEGIN
  IF lower(COALESCE(NEW.category, '')) ~ '(abuse|fraud|safety|theft|harass|grave|violen)' THEN

    v_summary := format(
      'Reclamação grave [%s]: %s',
      NEW.category,
      substring(COALESCE(NEW.subject, NEW.body, ''), 1, 100)
    );

    PERFORM public.notify_admin_event(
      'complaint_high',
      'high',
      v_summary,
      'complaint',
      NEW.id::text,
      jsonb_build_object(
        'category', NEW.category,
        'reporter_role', NEW.reporter_role,
        'related_order_id', NEW.related_order_id
      ),
      '/admin/complaints'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER _trg_admin_notif_complaint_high
  AFTER INSERT ON public.complaints
  FOR EACH ROW EXECUTE FUNCTION _trg_admin_notif_complaint_high_fn();
