-- Base local que imita o que as partes 01..05 da Casa usam em produção (só para provar; nada vai ao ar).
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_app_meta_data jsonb DEFAULT '{}', raw_user_meta_data jsonb DEFAULT '{}');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid', true), '')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('test.jwt', true), ''), '{}')::jsonb $$;
CREATE SCHEMA storage;
CREATE TABLE storage.buckets (id text PRIMARY KEY, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
CREATE TABLE storage.objects (id uuid DEFAULT gen_random_uuid(), bucket_id text, name text);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid serial, jobname text UNIQUE, schedule text, command text);
CREATE FUNCTION cron.schedule(n text, s text, c text) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (n, s, c)
  ON CONFLICT (jobname) DO UPDATE SET schedule = excluded.schedule, command = excluded.command RETURNING jobid::bigint $$;
CREATE SCHEMA vault;
CREATE TABLE vault.decrypted_secrets (name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('project_url', 'https://local.test'), ('service_role_key', 'x');
CREATE SCHEMA net;
CREATE TABLE net.calls (id serial, url text, body jsonb);
CREATE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}', body jsonb DEFAULT '{}') RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO net.calls (url, body) VALUES (url, body) RETURNING id::bigint $$;

CREATE TABLE public.users (id uuid PRIMARY KEY, name text, email text, phone text, fcm_token text);
CREATE TABLE public.platform_settings (key text PRIMARY KEY, value jsonb, description text, category text,
  updated_at timestamptz DEFAULT now(), updated_by uuid, is_secret boolean DEFAULT false);
INSERT INTO public.platform_settings (key, value, category) VALUES ('max_cash_amount_cents', '4000', 'pagamentos');
CREATE TABLE public.user_roles (user_id uuid, role text, UNIQUE (user_id, role),
  CONSTRAINT user_roles_role_check CHECK (role = ANY (ARRAY['client','driver','delivery','partner','cleaner','washer','admin'])));
CREATE TABLE public.provider_push_tokens (user_id uuid, role text, fcm_token text, platform text, active boolean DEFAULT true,
  last_fail_at timestamptz,
  CONSTRAINT provider_push_tokens_role_check CHECK (role = ANY (ARRAY['cleaner','washer','delivery'])));
CREATE TABLE public.preferencias_papel (user_id uuid, papel text, aceita boolean, updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, papel),
  CONSTRAINT preferencias_papel_papel_check CHECK (papel = ANY (ARRAY['cleaner','washer','delivery','driver'])));
CREATE TABLE public.notification_failures (id serial, user_id uuid, kind text, source text, erro text, created_at timestamptz DEFAULT now());
CREATE TABLE public.notificacoes_app (id serial, user_id uuid, kind text, title text, body text, related text);
CREATE TABLE public.admin_audit_log (id uuid DEFAULT gen_random_uuid(), admin_id uuid, admin_email text, action text,
  entity_type text, entity_id uuid, details jsonb, ip_address text, created_at timestamptz DEFAULT now(), entity_id_text text);
CREATE TABLE public.provider_atividade (user_id uuid PRIMARY KEY, atividade_status text);
CREATE TABLE public.ofertas_prestador_log (id serial, categoria text, booking_id uuid, prestador_id uuid, user_id uuid, nome text,
  tem_aparelho boolean, janela_min int, oferecida_em timestamptz DEFAULT now(), desfecho text, fechada_em timestamptz,
  CONSTRAINT ofertas_prestador_log_categoria_check CHECK (categoria = ANY (ARRAY['limpeza'::text, 'lavagem'::text])));

-- Funções partilhadas: as de produção tal e qual (is_admin, demo, aparelho, distância, toque, papéis,
-- auditoria, registo de ofertas, acerto congelado, convidado) e stubs onde chamam o mundo de fora.
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM auth.users WHERE id = v_uid AND (COALESCE(raw_app_meta_data->>'role','') = 'admin'
));
END $$;
CREATE FUNCTION public.is_demo_email(p_email text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_email IS NULL OR p_email = '' THEN false
    ELSE COALESCE((SELECT bool_or(lower(p_email) LIKE pat) FROM jsonb_array_elements_text(
      '["demo%@bora.app","teste%@bora.app","prova.%@bora.app","%@boraapp.test","%@test.com","e2e_%","test_%"]'::jsonb) AS pat), false) END $$;
CREATE FUNCTION public.is_demo_user(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_user_id IS NULL THEN false
    ELSE COALESCE((SELECT public.is_demo_email(u.email) FROM auth.users u WHERE u.id = p_user_id), false) END $$;
CREATE FUNCTION public.tem_aparelho(p_user_id uuid, p_papel text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM public.provider_push_tokens t WHERE t.user_id = p_user_id AND t.role = p_papel AND t.active)
      OR EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id AND COALESCE(u.fcm_token, '') <> '') $$;
CREATE FUNCTION public.aceita_papel(p_user_id uuid, p_papel text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT p.aceita FROM public.preferencias_papel p WHERE p.user_id = p_user_id AND p.papel = p_papel), true) $$;
CREATE FUNCTION public._cleaning_distance_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
 RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 6371 * 2 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))) $$;
CREATE FUNCTION public._cleaning_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE FUNCTION public._grant_role_from_profile() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_role text := TG_ARGV[0];
BEGIN
  IF NEW.user_id IS NOT NULL THEN INSERT INTO public.user_roles (user_id, role) VALUES (NEW.user_id, v_role) ON CONFLICT DO NOTHING; END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION public.fn_atividade_antes_de_ativar() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE FUNCTION public.fn_conformidade_antes_de_ativar() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE FUNCTION public._conformidade_em_falta(p_row jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY(SELECT x FROM unnest(ARRAY['legal_name','iban','address','birth_date']) x WHERE COALESCE(p_row ->> x, '') = '') $$;
CREATE FUNCTION public.is_conta_convidado() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = auth.uid() AND lower(u.email) = 'guest@bora.com') $$;
CREATE FUNCTION public.trg_convidado_so_ve() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF public.is_conta_convidado() THEN RAISE EXCEPTION 'convidado_sem_conta' USING ERRCODE = '42501'; END IF; RETURN NEW; END $$;
CREATE FUNCTION public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text, p_related_id text)
 RETURNS uuid LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.notificacoes_app (user_id, kind, title, body, related)
 VALUES (p_user_id, p_kind, p_title, p_body, p_related_id); RETURN gen_random_uuid(); END $$;
CREATE FUNCTION public.registar_oferta(p_categoria text, p_booking_id uuid, p_prestador_id uuid, p_user_id uuid, p_nome text,
  p_tem_aparelho boolean, p_janela_min integer) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.ofertas_prestador_log (categoria, booking_id, prestador_id, user_id, nome, tem_aparelho, janela_min)
  VALUES (p_categoria, p_booking_id, p_prestador_id, p_user_id, p_nome, p_tem_aparelho, p_janela_min) $$;
CREATE FUNCTION public.fechar_oferta(p_booking_id uuid, p_prestador_id uuid, p_desfecho text) RETURNS void LANGUAGE sql AS $$
  UPDATE public.ofertas_prestador_log SET desfecho = p_desfecho, fechada_em = now()
   WHERE id = (SELECT id FROM public.ofertas_prestador_log WHERE booking_id = p_booking_id AND prestador_id = p_prestador_id
                 AND desfecho IS NULL ORDER BY oferecida_em DESC LIMIT 1) $$;
CREATE FUNCTION public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_uuid uuid;
BEGIN
  IF p_entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_uuid := p_entity_id::uuid; END IF;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt() ->> 'email', COALESCE(NULLIF(trim(p_action_type), ''), 'acao_admin'), p_entity_type, v_uuid,
          p_entity_id, COALESCE(p_details, '{}'::jsonb));
END $$;
CREATE FUNCTION public.log_admin_action(p_action text, p_entity_type text DEFAULT NULL, p_entity_id uuid DEFAULT NULL,
  p_details jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), p_action, p_entity_type, p_entity_id, COALESCE(p_details, '{}'::jsonb)) RETURNING id INTO v;
  RETURN v;
END $$;
CREATE FUNCTION public._acerto_pago_congelado() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_livres text[] := ARRAY['notes', 'payment_reference', 'payment_method']; v_old jsonb := to_jsonb(OLD); v_new jsonb := to_jsonb(NEW);
BEGIN
  IF OLD.status IN ('paid', 'received') AND NEW.status IN ('paid', 'received') AND (v_new - v_livres) IS DISTINCT FROM (v_old - v_livres) THEN
    NEW := jsonb_populate_record(NEW, v_old - v_livres);
  END IF;
  RETURN NEW;
END $$;
