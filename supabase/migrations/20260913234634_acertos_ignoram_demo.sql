-- ============================================================================
-- 2026-09-14 (missao painel-admin-limpo) — DADOS DE DEMO FORA DO DINHEIRO
--
-- Cicatriz: a 14/09 as 00:18 o painel dizia "Pedidos hoje 1" e esse 1 era o
-- pedido de demonstracao 36e6812a (Estafeta Demo, 32,41 EUR em dinheiro). E o
-- fecho da semana de 07/09 tinha uma linha de acerto para o "Estafeta Demo"
-- (3,18 EUR) ao lado das linhas do Danilo e do Valdemir.
--
-- O que esta migration faz (tudo aditivo, sem tocar nas funcoes canonicas de
-- calculo — essas ficam em PROPOSTA no repo, a Trava nao deixa reescreve-las):
--   1. Padroes de email de demo em platform_settings (o Danilo pode mudar no
--      painel sem mexer em codigo) + interruptor admin_show_demo_data.
--   2. Funcoes is_demo_email / is_demo_user / is_demo_driver /
--      is_demo_restaurant / is_demo_provider / is_demo_order / is_demo_subject
--      — UMA definicao de "demo" para todo o servidor.
--   3. Trigger BEFORE INSERT nas 5 tabelas de acerto: se o sujeito e demo, a
--      linha nao entra (RETURN NULL). Vale para o cron, para o recalculo manual
--      e para o painel — nao ha caminho que a crie.
--   4. Apaga as linhas de acerto de demo que ja existiam (so as nao pagas).
--
-- ATENCAO ao filtro: `%@bora.app` NAO e demo. ouro.prata@, mr.kebab@,
-- saboresde.casa@, sabores.brasil@, beunique@, lava.leva@ sao parceiros REAIS
-- com email sintetico. Por isso os padroes sao estreitos (demo%@, teste%@,
-- prova.%@) e nunca `%demo%` solto (alefernandesdemoura03@gmail.com e cliente
-- real — "demo" esta no meio de "de moura").
-- ============================================================================

-- 1) Configuracao ------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('admin_show_demo_data', 'false'::jsonb,
   'Painel admin: mostrar contas/pedidos de demonstracao nos contadores e KPIs (por defeito nao).',
   'admin'),
  ('admin_demo_email_patterns',
   '["demo%@bora.app","teste%@bora.app","prova.%@bora.app","%@boraapp.test","%@test.com","e2e_%","test_%"]'::jsonb,
   'Padroes LIKE (minusculas) que marcam um email como conta de demonstracao/teste. NAO usar %@bora.app: ha parceiros reais com esse dominio.',
   'admin')
ON CONFLICT (key) DO NOTHING;

-- 2) Uma definicao de demo ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_demo_email(p_email text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_email IS NULL OR p_email = '' THEN false
    ELSE COALESCE((
      SELECT bool_or(lower(p_email) LIKE pat)
      FROM jsonb_array_elements_text(
        COALESCE(
          (SELECT value FROM public.platform_settings WHERE key = 'admin_demo_email_patterns'),
          '["demo%@bora.app","teste%@bora.app","prova.%@bora.app","%@boraapp.test","%@test.com","e2e_%","test_%"]'::jsonb
        )
      ) AS pat
    ), false)
  END
$$;

CREATE OR REPLACE FUNCTION public.is_demo_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_user_id IS NULL THEN false
    -- IDs fixos das contas demo (estafeta, parceiro, conta-para-apagar).
    WHEN p_user_id IN ('dede0000-0000-4000-8000-000000000001',
                       'dede0000-0000-4000-8000-000000000003',
                       'dcdc0000-0000-4000-8000-000000000001') THEN true
    ELSE COALESCE((SELECT public.is_demo_email(u.email) FROM auth.users u WHERE u.id = p_user_id), false)
  END
$$;

-- drivers.id OU drivers.user_id (as tabelas de acerto misturam os dois).
CREATE OR REPLACE FUNCTION public.is_demo_driver(p_driver_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_driver_id IS NULL OR p_driver_id = '' THEN false
    WHEN p_driver_id IN ('dede0000-0000-4000-8000-000000000001',
                         'dede0000-0000-4000-8000-000000000002') THEN true
    WHEN p_driver_id !~ '^[0-9a-f]{8}-' THEN false
    ELSE COALESCE((
      SELECT bool_or(public.is_demo_email(d.email) OR public.is_demo_user(d.user_id))
      FROM public.drivers d
      WHERE d.id = p_driver_id::uuid OR d.user_id = p_driver_id::uuid
    ), false)
  END
$$;

CREATE OR REPLACE FUNCTION public.is_demo_restaurant(p_restaurant_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_restaurant_id IS NULL OR p_restaurant_id = '' THEN false
    WHEN p_restaurant_id = 'demo-parceiro-loja' THEN true
    ELSE COALESCE((
      SELECT public.is_demo_email(r.email) OR public.is_demo_user(COALESCE(r.user_id, r.user_))
      FROM public.restaurants r WHERE r.id = p_restaurant_id
    ), false)
  END
$$;

CREATE OR REPLACE FUNCTION public.is_demo_provider(p_provider_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_provider_id IS NULL OR p_provider_id = '' THEN false
    ELSE COALESCE((
      SELECT public.is_demo_user(sp.user_id)
      FROM public.service_providers sp WHERE sp.id = p_provider_id
    ), false)
  END
$$;

-- Um pedido e demo se foi marcado como teste, se o cliente e demo, se o
-- estafeta e demo ou se a loja e demo.
CREATE OR REPLACE FUNCTION public.is_demo_order(o public.orders)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(o.is_test_order, false)
      OR public.is_demo_user(o.user_id)
      OR public.is_demo_driver(o.assigned_driver_id)
      OR public.is_demo_restaurant(o.restaurant_id)
$$;

-- Sujeito de um acerto: 'driver' | 'partner' | 'provider' | 'cleaner' | 'washer'.
CREATE OR REPLACE FUNCTION public.is_demo_subject(p_type text, p_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE p_type
    WHEN 'driver'   THEN public.is_demo_driver(p_id)
    WHEN 'partner'  THEN public.is_demo_restaurant(p_id)
    WHEN 'provider' THEN public.is_demo_provider(p_id)
    WHEN 'cleaner'  THEN COALESCE((SELECT public.is_demo_email(c.email) OR public.is_demo_user(c.user_id)
                                   FROM public.cleaners c WHERE c.id::text = p_id), false)
    WHEN 'washer'   THEN COALESCE((SELECT public.is_demo_email(w.email) OR public.is_demo_user(w.user_id)
                                   FROM public.washers w WHERE w.id::text = p_id), false)
    ELSE false
  END
$$;

-- O painel quer ver demo? (interruptor). Sem linha = nao.
CREATE OR REPLACE FUNCTION public.admin_demo_visible()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((SELECT value = 'true'::jsonb FROM public.platform_settings WHERE key = 'admin_show_demo_data'), false)
$$;

REVOKE ALL ON FUNCTION public.is_demo_email(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_user(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_driver(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_restaurant(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_provider(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_order(public.orders) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_demo_subject(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_demo_visible() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_demo_email(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_user(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_driver(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_restaurant(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_provider(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_order(public.orders) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_demo_subject(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_demo_visible() TO authenticated, service_role;

-- 3) Trigger aditivo: linha de acerto de sujeito demo nao entra --------------
CREATE OR REPLACE FUNCTION public._acerto_ignora_demo()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type text := TG_ARGV[0];
  v_id   text;
BEGIN
  v_id := CASE v_type
    WHEN 'driver'   THEN NEW.driver_id::text
    WHEN 'partner'  THEN NEW.partner_id::text
    WHEN 'provider' THEN NEW.provider_id::text
    WHEN 'cleaner'  THEN NEW.cleaner_id::text
    WHEN 'washer'   THEN NEW.washer_id::text
  END;
  IF public.is_demo_subject(v_type, v_id) THEN
    -- Fica registado que se ignorou, para ninguem procurar a linha que nao ha.
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('acerto_demo_ignorado', 'settlement', v_id,
            jsonb_build_object('tipo', v_type, 'week_start_at', NEW.week_start_at, 'tabela', TG_TABLE_NAME));
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_acerto_ignora_demo
  BEFORE INSERT ON public.driver_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_ignora_demo('driver');
CREATE OR REPLACE TRIGGER trg_acerto_ignora_demo
  BEFORE INSERT ON public.partner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_ignora_demo('partner');
CREATE OR REPLACE TRIGGER trg_acerto_ignora_demo
  BEFORE INSERT ON public.appointment_payouts
  FOR EACH ROW EXECUTE FUNCTION public._acerto_ignora_demo('provider');
CREATE OR REPLACE TRIGGER trg_acerto_ignora_demo
  BEFORE INSERT ON public.cleaner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_ignora_demo('cleaner');
CREATE OR REPLACE TRIGGER trg_acerto_ignora_demo
  BEFORE INSERT ON public.washer_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_ignora_demo('washer');

-- 4) Limpar o que ja la estava (so linhas nao pagas) ------------------------
DELETE FROM public.driver_weekly_settlements
 WHERE public.is_demo_driver(driver_id::text) AND status NOT IN ('paid','received');
DELETE FROM public.partner_weekly_settlements
 WHERE public.is_demo_restaurant(partner_id) AND status NOT IN ('paid','received');
DELETE FROM public.appointment_payouts
 WHERE public.is_demo_provider(provider_id) AND status NOT IN ('paid','received');
DELETE FROM public.cleaner_weekly_settlements
 WHERE public.is_demo_subject('cleaner', cleaner_id::text) AND status NOT IN ('paid','received');
DELETE FROM public.washer_weekly_settlements
 WHERE public.is_demo_subject('washer', washer_id::text) AND status NOT IN ('paid','received');
