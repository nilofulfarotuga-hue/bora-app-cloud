-- Ronda de correções 04/10/2026 · agente checkout
-- Carrinho abandonado (como Uber Eats / Glovo).
--
-- A app grava um retrato do carrinho (com pausa de alguns segundos) por
-- carrinho_guardar(); limpa-o ao fazer o pedido (carrinho_convertido()). Um cron a
-- cada 15 min manda UM push a quem largou o carrinho há mais de
-- carrinho_abandonado_minutos — no máximo 1 por carrinho e 1 por dia por pessoa —
-- pela infra de push que já existe (_push_in_app_notification + notify-client).
-- Nasce DESLIGADO (carrinho_abandonado_ligado = false): o Danilo liga no painel.

-- ── Definições ──────────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description) VALUES
  ('carrinho_abandonado_ligado', 'false'::jsonb,
   'Liga o aviso de carrinho abandonado (push ao cliente que largou o carrinho).'),
  ('carrinho_abandonado_minutos', '60'::jsonb,
   'Minutos depois da última mexida no carrinho até mandar o aviso.'),
  ('carrinho_abandonado_titulo', to_jsonb('Ficou alguma coisa no teu carrinho 🛒'::text),
   'Título do push de carrinho abandonado.'),
  ('carrinho_abandonado_texto', to_jsonb('O teu pedido de {loja} está à tua espera. Toca para terminar.'::text),
   'Texto do push de carrinho abandonado. {loja} é trocado pelo nome da loja.')
ON CONFLICT (key) DO NOTHING;

-- ── Tabela: um carrinho vivo por pessoa ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.carrinhos_abandonados (
  user_id         uuid PRIMARY KEY,
  loja            text,
  loja_id         text,
  resumo          text,
  total           numeric(10,2) NOT NULL DEFAULT 0,
  n_itens         integer NOT NULL DEFAULT 0,
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  avisado_em      timestamptz,
  convertido_em   timestamptz,
  ultimo_aviso_em timestamptz,
  criado_em       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.carrinhos_abandonados IS
  'Retrato do carrinho de cada cliente (um por pessoa) para o aviso de carrinho abandonado. avisado_em = este carrinho já levou aviso; ultimo_aviso_em = último aviso à pessoa (máx. 1 por dia).';

CREATE INDEX IF NOT EXISTS carrinhos_abandonados_pendentes_idx
  ON public.carrinhos_abandonados (atualizado_em)
  WHERE avisado_em IS NULL AND convertido_em IS NULL AND n_itens > 0;

ALTER TABLE public.carrinhos_abandonados ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='carrinhos_abandonados' AND policyname='carrinho_proprio_ler') THEN
    CREATE POLICY carrinho_proprio_ler ON public.carrinhos_abandonados
      FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='carrinhos_abandonados' AND policyname='carrinho_proprio_inserir') THEN
    CREATE POLICY carrinho_proprio_inserir ON public.carrinhos_abandonados
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='carrinhos_abandonados' AND policyname='carrinho_proprio_mudar') THEN
    CREATE POLICY carrinho_proprio_mudar ON public.carrinhos_abandonados
      FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

REVOKE ALL ON public.carrinhos_abandonados FROM anon;
GRANT SELECT, INSERT, UPDATE ON public.carrinhos_abandonados TO authenticated;

-- ── App: gravar o retrato do carrinho ──────────────────────────────────────
-- Um carrinho que muda de conteúdo é um carrinho NOVO: pode voltar a levar aviso
-- (o limite de 1 por dia por pessoa continua a valer).
CREATE OR REPLACE FUNCTION public.carrinho_guardar(
  p_loja text, p_loja_id text, p_resumo text, p_total numeric, p_n_itens integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  INSERT INTO public.carrinhos_abandonados AS c
    (user_id, loja, loja_id, resumo, total, n_itens, atualizado_em)
  VALUES (v_uid, left(p_loja, 120), left(p_loja_id, 120), left(p_resumo, 300),
          COALESCE(p_total, 0), GREATEST(COALESCE(p_n_itens, 0), 0), now())
  ON CONFLICT (user_id) DO UPDATE SET
    loja          = EXCLUDED.loja,
    loja_id       = EXCLUDED.loja_id,
    resumo        = EXCLUDED.resumo,
    total         = EXCLUDED.total,
    n_itens       = EXCLUDED.n_itens,
    atualizado_em = now(),
    avisado_em    = CASE WHEN c.resumo IS DISTINCT FROM EXCLUDED.resumo
                           OR c.total IS DISTINCT FROM EXCLUDED.total
                         THEN NULL ELSE c.avisado_em END,
    convertido_em = NULL;
END;
$function$;

-- ── App: o carrinho virou pedido (ou foi esvaziado) ────────────────────────
CREATE OR REPLACE FUNCTION public.carrinho_convertido()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  UPDATE public.carrinhos_abandonados
     SET convertido_em = now(), n_itens = 0
   WHERE user_id = auth.uid();
END;
$function$;

REVOKE ALL ON FUNCTION public.carrinho_guardar(text, text, text, numeric, integer) FROM anon, public;
REVOKE ALL ON FUNCTION public.carrinho_convertido() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.carrinho_guardar(text, text, text, numeric, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carrinho_convertido() TO authenticated;

-- ── Cron: mandar os avisos ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.carrinhos_abandonados_avisar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ligado  boolean;
  v_minutos integer;
  v_titulo  text;
  v_texto   text;
  v_url     text;
  v_key     text;
  r         record;
  v_n       integer := 0;
  v_corpo   text;
BEGIN
  SELECT COALESCE((value::text)::boolean, false) INTO v_ligado
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_ligado';
  IF COALESCE(v_ligado, false) IS NOT TRUE THEN RETURN 0; END IF;

  SELECT (value::text)::integer INTO v_minutos
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_minutos';
  v_minutos := GREATEST(COALESCE(v_minutos, 60), 5);
  SELECT value #>> '{}' INTO v_titulo
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_titulo';
  SELECT value #>> '{}' INTO v_texto
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_texto';
  v_titulo := COALESCE(NULLIF(v_titulo, ''), 'Ficou alguma coisa no teu carrinho 🛒');
  v_texto  := COALESCE(NULLIF(v_texto, ''), 'O teu pedido de {loja} está à tua espera. Toca para terminar.');

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_url := NULL; v_key := NULL; END;

  FOR r IN
    SELECT c.*
      FROM public.carrinhos_abandonados c
     WHERE c.n_itens > 0
       AND c.convertido_em IS NULL
       AND c.avisado_em IS NULL
       AND c.atualizado_em < now() - make_interval(mins => v_minutos)
       AND c.atualizado_em > now() - interval '3 days'
       AND (c.ultimo_aviso_em IS NULL OR c.ultimo_aviso_em < now() - interval '24 hours')
       -- Já fez um pedido depois de mexer no carrinho? Então não largou nada.
       AND NOT EXISTS (SELECT 1 FROM public.orders o
                        WHERE o.user_id = c.user_id
                          AND o.created_at > c.atualizado_em - interval '2 minutes')
     ORDER BY c.atualizado_em
     LIMIT 200
     FOR UPDATE SKIP LOCKED
  LOOP
    v_corpo := replace(v_texto, '{loja}', COALESCE(NULLIF(r.loja, ''), 'Bora'));
    -- Marca primeiro: um falhanço no envio nunca faz repetir o aviso.
    UPDATE public.carrinhos_abandonados
       SET avisado_em = now(), ultimo_aviso_em = now()
     WHERE user_id = r.user_id;
    BEGIN
      PERFORM public._push_in_app_notification(r.user_id, 'carrinho_abandonado', v_titulo, v_corpo, r.loja_id);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
          body := jsonb_build_object('clientId', r.user_id::text, 'title', v_titulo, 'body', v_corpo,
                                     'kind', 'carrinho_abandonado', 'type', 'carrinho_abandonado')
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION public.carrinhos_abandonados_avisar() FROM anon, authenticated, public;

-- ── Painel admin (PT-BR) ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_carrinhos_abandonados_resumo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  SELECT jsonb_build_object(
    'ligado',  COALESCE((SELECT (value::text)::boolean FROM platform_settings WHERE key='carrinho_abandonado_ligado'), false),
    'minutos', COALESCE((SELECT (value::text)::integer FROM platform_settings WHERE key='carrinho_abandonado_minutos'), 60),
    'titulo',  (SELECT value #>> '{}' FROM platform_settings WHERE key='carrinho_abandonado_titulo'),
    'texto',   (SELECT value #>> '{}' FROM platform_settings WHERE key='carrinho_abandonado_texto'),
    'carrinhos_abertos', (SELECT count(*) FROM carrinhos_abandonados
                           WHERE n_itens > 0 AND convertido_em IS NULL),
    'avisados_7d', (SELECT count(*) FROM carrinhos_abandonados
                     WHERE ultimo_aviso_em > now() - interval '7 days'),
    'convertidos_apos_aviso_7d', (SELECT count(*) FROM carrinhos_abandonados c
                     WHERE c.avisado_em > now() - interval '7 days'
                       AND EXISTS (SELECT 1 FROM orders o WHERE o.user_id = c.user_id
                                     AND o.created_at > c.avisado_em
                                     AND o.created_at < c.avisado_em + interval '24 hours')),
    'valor_aberto', COALESCE((SELECT sum(total) FROM carrinhos_abandonados
                               WHERE n_itens > 0 AND convertido_em IS NULL), 0),
    'lista', COALESCE((SELECT jsonb_agg(x ORDER BY x.atualizado_em DESC) FROM (
                SELECT c.user_id, COALESCE(u.name, u.email, '') AS cliente, c.loja, c.resumo,
                       c.total, c.n_itens, c.atualizado_em, c.avisado_em, c.convertido_em
                  FROM carrinhos_abandonados c
                  LEFT JOIN users u ON u.id = c.user_id
                 ORDER BY c.atualizado_em DESC LIMIT 100) x), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_carrinho_abandonado_config(
  p_ligado boolean, p_minutos integer, p_titulo text, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  IF p_minutos IS NOT NULL AND (p_minutos < 5 OR p_minutos > 10080) THEN
    RAISE EXCEPTION 'minutos_invalidos: entre 5 e 10080';
  END IF;
  IF p_ligado IS NOT NULL THEN
    UPDATE platform_settings SET value = to_jsonb(p_ligado), updated_at = now(), updated_by = auth.uid()
     WHERE key = 'carrinho_abandonado_ligado';
  END IF;
  IF p_minutos IS NOT NULL THEN
    UPDATE platform_settings SET value = to_jsonb(p_minutos), updated_at = now(), updated_by = auth.uid()
     WHERE key = 'carrinho_abandonado_minutos';
  END IF;
  IF NULLIF(trim(p_titulo), '') IS NOT NULL THEN
    UPDATE platform_settings SET value = to_jsonb(left(trim(p_titulo), 80)), updated_at = now(), updated_by = auth.uid()
     WHERE key = 'carrinho_abandonado_titulo';
  END IF;
  IF NULLIF(trim(p_texto), '') IS NOT NULL THEN
    UPDATE platform_settings SET value = to_jsonb(left(trim(p_texto), 200)), updated_at = now(), updated_by = auth.uid()
     WHERE key = 'carrinho_abandonado_texto';
  END IF;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), 'carrinho_abandonado_config', 'platform_settings', 'carrinho_abandonado',
          jsonb_build_object('ligado', p_ligado, 'minutos', p_minutos, 'titulo', p_titulo, 'texto', p_texto));
  RETURN public.admin_carrinhos_abandonados_resumo();
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_carrinhos_abandonados_resumo() FROM anon, public;
REVOKE ALL ON FUNCTION public.admin_carrinho_abandonado_config(boolean, integer, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.admin_carrinhos_abandonados_resumo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_carrinho_abandonado_config(boolean, integer, text, text) TO authenticated;

-- ── Cron a cada 15 min (idempotente) ───────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carrinhos-abandonados-15min') THEN
    PERFORM cron.schedule('carrinhos-abandonados-15min', '*/15 * * * *',
                          'select public.carrinhos_abandonados_avisar();');
  END IF;
END $$;
