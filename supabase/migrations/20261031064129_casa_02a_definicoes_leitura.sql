-- Casa & Manutenção — parte 2a: leitura das definições casa_* (só leitura).

-- 1) Definições ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_int(p_key text, p_default integer)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT (value #>> '{}')::integer FROM platform_settings WHERE key = p_key), p_default) $$;

CREATE OR REPLACE FUNCTION public._casa_num(p_key text, p_default numeric)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key = p_key), p_default) $$;

CREATE OR REPLACE FUNCTION public._casa_bool(p_key text, p_default boolean)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM platform_settings WHERE key = p_key), p_default) $$;

-- Preços, percentagem do Bora e promoção só valem depois do "autorizo" do Danilo.
CREATE OR REPLACE FUNCTION public._casa_valores_validos()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE((SELECT (value ->> 'autorizado')::boolean FROM platform_settings WHERE key = 'casa_valores_autorizados'), false) $$;

-- Quem vê a Casa com o interruptor desligado: testadores da lista e contas de demonstração.
CREATE OR REPLACE FUNCTION public._casa_testador(p_uid uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT p_uid IS NOT NULL AND (
    COALESCE((SELECT value ? p_uid::text FROM platform_settings WHERE key = 'casa_testadores'), false)
    OR COALESCE(public.is_demo_user(p_uid), false))
$$;