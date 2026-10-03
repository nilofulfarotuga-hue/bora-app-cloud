-- ============================================================================
-- Portas de admin: duas que estavam trancadas a toda a gente e uma que estava
-- aberta a toda a gente.  2026-09-05 · sessão tudo-05-09-mao · Bloco 6
--
-- Gravado na base em três pedaços: 20260904235242 (esta guarda),
-- 20260904235455 (tabela de backup) e 20260904235928 (admin_list_orphans).
-- Este ficheiro junta os três; o nome casa com o primeiro, para o `db push`
-- não os tentar aplicar outra vez.
-- ============================================================================

-- ─── 1. _reservas_pro_assert_admin: estava a trancar TODA a gente ──────────
-- Lia `users.is_admin`, uma coluna que NÃO existe nesta base. Provado:
--     select is_admin from public.users limit 1;
--     ERROR: 42703: column "is_admin" does not exist
-- O SELECT rebentava, o `EXCEPTION WHEN OTHERS` punha v_is_admin := false e a
-- função levantava sempre 'admin_required'. Falhava fechado — não era buraco de
-- segurança, era uma funcionalidade morta. Cinco RPCs de admin dependiam dela e
-- não funcionavam para ninguém, nem para o Danilo:
--   admin_block_client, admin_unblock_client, admin_seat_walk_in,
--   admin_force_create_reservation, admin_get_reservations_stats.
-- Agora delega no is_admin() verdadeiro do projecto. Contrato de erros mantido.
CREATE OR REPLACE FUNCTION public._reservas_pro_assert_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
END;
$function$;

-- ─── 2. Guarda genérica, para quem vier a precisar ─────────────────────────
CREATE OR REPLACE FUNCTION public._assert_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public._assert_admin() FROM anon;

-- ─── 3. Tabela de backup das definições, antes de mexer em nada ────────────
CREATE TABLE IF NOT EXISTS public._backup_funcdefs_20260905 (
  proname       text,
  identity_args text,
  lang          text,
  def_original  text,
  guardado_em   timestamptz DEFAULT now()
);
REVOKE ALL ON TABLE public._backup_funcdefs_20260905 FROM anon, authenticated;

-- ─── 4. admin_list_orphans: a armadilha do NULL ────────────────────────────
-- A guarda era:
--     IF (auth.jwt() -> 'app_metadata' ->> 'role') != 'admin' THEN RAISE ...
-- Num JWT normal do Supabase o app_metadata traz provider/providers mas NÃO traz
-- 'role'. A expressão dá NULL, `NULL != 'admin'` dá NULL — que não é TRUE — e o
-- IF nunca dispara. Lógica de três valores.
-- PROVADO com sessão de um cliente real (JWT com app_metadata realista):
--     admin_list_orphans com cliente real -> PASSOU — leu 0 linhas
-- Leu zero só porque naquele momento não havia órfãos; a guarda não o travou.
-- A função devolve payment_intent_id e valores de payment_drafts e de orders,
-- ou seja dados de pagamento de outras pessoas.
-- Depois do fix, provado nos dois sentidos:
--     cliente real -> BLOQUEOU: insufficient_privilege (correcto)
--     Danilo admin -> PASSOU e leu 0 linhas (correcto)
-- O corpo e o resultado ficam iguais; muda só a guarda.
CREATE OR REPLACE FUNCTION public.admin_list_orphans()
RETURNS TABLE(kind text, id text, user_id uuid, payment_intent_id text, amount numeric, age_minutes numeric, notes text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'insufficient_privilege' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT 'payment_draft'::TEXT AS kind,
           pd.id::TEXT,
           pd.user_id,
           pd.payment_intent_id,
           (pd.amount_cents / 100.0)::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - pd.created_at)) / 60 AS age_minutes,
           CASE
             WHEN pd.expires_at < NOW() THEN 'expired'
             WHEN pd.used_at IS NOT NULL THEN 'used'
             ELSE 'pending'
           END AS notes
    FROM public.payment_drafts pd
    WHERE pd.used_at IS NULL
    UNION ALL
    SELECT 'order_no_charge'::TEXT AS kind,
           o.id,
           o.user_id::UUID,
           o.payment_intent_id,
           o.total::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - o.created_at)) / 60 AS age_minutes,
           COALESCE(o.cancel_reason, 'unknown') AS notes
    FROM public.orders o
    WHERE o.payment_status = 'cancelled_no_charge'
    ORDER BY age_minutes DESC
    LIMIT 100;
END;
$function$;
