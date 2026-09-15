-- PARTE A (2026-07-17): push persistente ao admin para 5 ações pendentes.
-- Aplicada em produção via MCP (migration admin_persistent_push_pending_actions).
-- Design: helper insere linha HIGH em admin_notifications (badge/inbox já existem)
-- E dispara notify-admin-urgent (kind=generic → canal bora_admin_urgent, FCM a todos
-- os admin_push_tokens). Push é best-effort: falha NUNCA quebra a DML de origem.
-- Sem bridge global em admin_notifications (evita duplicar push de robot_b_suggestion, high).

CREATE OR REPLACE FUNCTION public.notify_admin_urgent_push(
  p_event_type  text,
  p_summary     text,
  p_entity_type text,
  p_entity_id   text,
  p_payload     jsonb,
  p_deep_link   text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id  uuid;
  v_url text;
  v_key text;
BEGIN
  -- 1) Persiste a linha (badge + inbox dependem disto), severidade HIGH.
  v_id := public.notify_admin_event(
    p_event_type, 'high', p_summary,
    p_entity_type, p_entity_id, COALESCE(p_payload, '{}'::jsonb), p_deep_link
  );

  -- 2) Push persistente best-effort (nunca quebra a transação de origem).
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type', 'application/json'),
        body    := jsonb_build_object(
          'kind',  'generic',
          'title', '🔴 Ação pendente — Bora Admin',
          'body',  p_summary,
          'route', COALESCE(p_deep_link, '/admin'),
          'ref',   p_event_type)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'notify_admin_urgent_push push error: %', SQLERRM;
  END;

  RETURN v_id;
END;
$$;

-- ── Gatilho 1: proposta zona-vermelha NOVA na Central ─────────────────────
CREATE OR REPLACE FUNCTION public._trg_admin_notif_cortex_red_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status = 'nova' THEN
    PERFORM public.notify_admin_urgent_push(
      'cortex_red_proposal',
      'Nova proposta zona-vermelha na Central: ' || COALESCE(NULLIF(left(NEW.tarefa,80),''), NEW.pid),
      'cortex_red_proposal', NEW.pid,
      jsonb_build_object('pid', NEW.pid, 'ordem_id', NEW.ordem_id, 'zona', NEW.zona),
      '/admin/robot'
    );
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_admin_notif_cortex_red ON public.cortex_red_proposals;
CREATE TRIGGER trg_admin_notif_cortex_red
  AFTER INSERT ON public.cortex_red_proposals
  FOR EACH ROW EXECUTE FUNCTION public._trg_admin_notif_cortex_red_fn();

-- ── Gatilho 2: novo estafeta a aguardar aprovação ─────────────────────────
CREATE OR REPLACE FUNCTION public._trg_admin_notif_driver_app_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.approval_status = 'pending'
     AND (TG_OP = 'INSERT' OR OLD.approval_status IS DISTINCT FROM 'pending') THEN
    PERFORM public.notify_admin_urgent_push(
      'driver_application_pending',
      'Novo estafeta a aguardar aprovação: ' || COALESCE(NULLIF(NEW.name,''), NEW.phone, NEW.id::text),
      'driver', NEW.id::text,
      jsonb_build_object('driver_id', NEW.id, 'phone', NEW.phone),
      '/admin/drivers/approval'
    );
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_admin_notif_driver_app ON public.drivers;
CREATE TRIGGER trg_admin_notif_driver_app
  AFTER INSERT OR UPDATE OF approval_status ON public.drivers
  FOR EACH ROW EXECUTE FUNCTION public._trg_admin_notif_driver_app_fn();

-- ── Gatilho 3: novo parceiro a aguardar aprovação ─────────────────────────
CREATE OR REPLACE FUNCTION public._trg_admin_notif_partner_app_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.approval_status = 'pending'
     AND (TG_OP = 'INSERT' OR OLD.approval_status IS DISTINCT FROM 'pending') THEN
    PERFORM public.notify_admin_urgent_push(
      'partner_application_pending',
      'Novo parceiro a aguardar aprovação: ' || COALESCE(NULLIF(NEW.name,''), NEW.id::text),
      'restaurant', NEW.id::text,
      jsonb_build_object('restaurant_id', NEW.id, 'name', NEW.name),
      '/admin/partners/pending'
    );
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_admin_notif_partner_app ON public.restaurants;
CREATE TRIGGER trg_admin_notif_partner_app
  AFTER INSERT OR UPDATE OF approval_status ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public._trg_admin_notif_partner_app_fn();

-- ── Gatilho 4: nova profissional de limpeza a aguardar aprovação ──────────
CREATE OR REPLACE FUNCTION public._trg_admin_notif_cleaner_app_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.approval_status = 'pending'
     AND (TG_OP = 'INSERT' OR OLD.approval_status IS DISTINCT FROM 'pending') THEN
    PERFORM public.notify_admin_urgent_push(
      'cleaner_application_pending',
      'Nova profissional de limpeza a aguardar aprovação: ' || COALESCE(NULLIF(NEW.name,''), NEW.phone, NEW.id::text),
      'cleaner', NEW.id::text,
      jsonb_build_object('cleaner_id', NEW.id, 'phone', NEW.phone),
      '/admin/cleaning/cleaners'
    );
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_admin_notif_cleaner_app ON public.cleaners;
CREATE TRIGGER trg_admin_notif_cleaner_app
  AFTER INSERT OR UPDATE OF approval_status ON public.cleaners
  FOR EACH ROW EXECUTE FUNCTION public._trg_admin_notif_cleaner_app_fn();

-- ── Gatilho 5 (TVDE): reaproveita o insert já existente em tvde_request_access,
-- trocando notify_admin_event (só linha, sem push) por notify_admin_urgent_push
-- (linha HIGH + push). Evita duplicar (não há trigger em tvde_access_requests).
CREATE OR REPLACE FUNCTION public.tvde_request_access()
 RETURNS tvde_access_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    UUID := auth.uid();
  v_access BOOLEAN;
  v_name   TEXT;
  v_row    public.tvde_access_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT tvde_access, name INTO v_access, v_name FROM public.users WHERE id = v_uid;
  IF v_access IS TRUE THEN RAISE EXCEPTION 'already_has_access'; END IF;

  SELECT * INTO v_row FROM public.tvde_access_requests
    WHERE client_id = v_uid AND status = 'pendente' LIMIT 1;
  IF FOUND THEN RETURN v_row; END IF;

  INSERT INTO public.tvde_access_requests (client_id)
    VALUES (v_uid) RETURNING * INTO v_row;

  PERFORM public.notify_admin_urgent_push(
    'tvde_driver_application_pending',
    'Novo motorista TVDE a aguardar aprovação: ' || COALESCE(v_name, 'cliente'),
    'tvde_access_request', v_row.id::text,
    jsonb_build_object('client_id', v_uid, 'client_name', v_name),
    '/admin/tvde/access-requests'
  );
  RETURN v_row;
END; $function$;
