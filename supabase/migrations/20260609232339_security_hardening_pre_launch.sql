-- M3.5 — SECURITY HARDENING PRÉ-LAUNCH (advisors Supabase 2026-06-09)
-- 1) search_path FIXO nas funções mutáveis (SÓ atributo — corpo intocado;
--    md5(prosrc) verificado antes/depois para as financeiras).
--    `public, extensions, pg_temp`: fixo (satisfaz o advisor) e inclui o schema
--    extensions (unaccent/pg_trgm/pg_net) para não partir funções de texto/rede.
-- 2) REVOKE EXECUTE FROM anon em TODAS as SECURITY DEFINER de public.
-- 3) REVOKE EXECUTE FROM authenticated nas SECURITY DEFINER internas `_*`
--    (exceção: _restaurant_id_of_current_user, usada em policies RLS).
-- 4) Fechar LISTING público dos buckets avatars/product-images/restaurant-assets
--    (downloads por URL pública continuam — public=true não passa por RLS).
-- NOTA: os REVOKEs de 2)/3) ficaram INEFICAZES por causa do GRANT default a
-- PUBLIC — corrigido na migration seguinte (v2_public_revoke). Mantido aqui
-- pelo histórico fiel do que foi aplicado em prod.

-- 1) search_path fixo
DO $do$
DECLARE r record; v_count int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND (p.proconfig IS NULL
           OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions, pg_temp', r.sig);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE '[hardening] search_path fixado em % funções', v_count;
END $do$;

-- 2) REVOKE anon em todas as SECURITY DEFINER de public
DO $do$
DECLARE r record; v_count int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef AND p.prokind = 'f'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE '[hardening] REVOKE anon em % funções SECURITY DEFINER', v_count;
END $do$;

-- 3) REVOKE authenticated nas internas _* (exceto a usada em RLS)
DO $do$
DECLARE r record; v_count int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef AND p.prokind = 'f'
      AND p.proname LIKE '\_%'
      AND p.proname <> '_restaurant_id_of_current_user'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE '[hardening] REVOKE authenticated em % funções internas _*', v_count;
END $do$;

-- 4) Fechar listing público dos 3 buckets (objetos continuam servidos por URL)
DROP POLICY IF EXISTS avatars_select_public ON storage.objects;
DROP POLICY IF EXISTS product_images_public_select ON storage.objects;
DROP POLICY IF EXISTS restaurant_assets_public_read ON storage.objects;

CREATE POLICY avatars_select_authenticated ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'avatars');
CREATE POLICY product_images_select_authenticated ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'product-images');
-- restaurant-assets: já existe restaurant_assets_authenticated_select (mantida)
