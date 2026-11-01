-- 01/11/2026 (missão seguranca-05, bloco 6) — tokens e carteira: só o próprio, o admin ou o servidor.
--
-- ⚠️ ISTO MEXE NA ZONA DE DINHEIRO (bora_tokens / client_wallets). Não muda nenhum valor, preço,
-- comissão nem saldo: só QUEM pode ler/mexer. Aplicar com o "autorizo" do Danilo e a data.
--
-- (1) get_user_tokens(p_user_id) — SECURITY DEFINER, EXECUTE para authenticated — devolvia o saldo de
--     tokens de QUALQUER conta a qualquer utilizador com sessão (bastava saber o user_id). Passa a
--     exigir: auth.uid() = p_user_id, ou is_admin(), ou service_role, ou chamada interna sem sessão
--     (auth.uid() IS NULL: cron/gatilhos/MCP), ou a flag bora.internal_token_consume='on' que o
--     consume_tokens já usa nos caminhos do servidor. Mesma regra do consume_tokens (28/10).
--     Quem a chama (lido 01/11): app → só com o próprio id (lib/screens/profile_screen.dart:1854);
--     painel admin → admin_get_user_tokens (tem _admin_op_guard, não é tocada); funções SQL →
--     create_order, quote_order_pricing, tvde_request_ride, client_daily_checkin, driver_convert_tokens
--     (todas com o próprio auth.uid()), admin_checkin_clientes e admin_list_wallets (admin),
--     consume_tokens e wallet_get_balance (já guardadas). Nenhum chamador lê tokens de terceiros.
--
-- (2) ACHADO PELO CAMINHO (grave): wallet_get_balance, admin_forgive_wallet_debt e
--     wallet_apply_post_delivery_adjustment decidiam "é admin" por
--       COALESCE((auth.jwt() -> 'user_metadata' ->> 'bora_role'), (auth.jwt() ->> 'role'))
--     e user_metadata é escrito pelo PRÓPRIO utilizador (auth.updateUser({data: {bora_role:'admin'}})).
--     Ou seja: qualquer conta podia (a) ler a carteira de qualquer pessoa e (b) chamar
--     admin_forgive_wallet_debt (EXECUTE para authenticated) e PERDOAR DÍVIDAS de carteira a quem
--     quisesse. Troca-se essa expressão, nas três, por
--       (CASE WHEN public.is_admin() THEN 'admin' ELSE COALESCE(auth.jwt() ->> 'role', '') END)
--     que lê app_metadata (só o servidor escreve) ou o e-mail do Danilo. O resto das funções fica
--     byte a byte igual (substituição por regexp sobre pg_get_functiondef; rebenta se não encontrar).
--
-- Idempotente: CREATE OR REPLACE; o bloco (2) só reescreve se ainda encontrar a expressão insegura.

-- ── (1) get_user_tokens ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_user_tokens(p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  -- 01/11/2026 seguranca-05: só o próprio, admin, service_role, chamada interna sem sessão
  -- ou a flag interna do consume_tokens.
  IF v_caller IS NOT NULL
     AND v_caller IS DISTINCT FROM p_user_id
     AND NOT public.is_admin()
     AND COALESCE(auth.jwt() ->> 'role', '') <> 'service_role'
     AND COALESCE(current_setting('bora.internal_token_consume', true), '') <> 'on' THEN
    RAISE EXCEPTION 'forbidden: get_user_tokens só do próprio (caller %, pedido %)', v_caller, p_user_id
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(SUM(amount), 0)::INTEGER
      FROM public.bora_tokens
     WHERE user_id    = p_user_id
       AND is_used    = FALSE
       AND expires_at > now()
  );
END;
$function$;

-- ── (2) carteira: "admin" só por is_admin() ─────────────────────────────────────────────────
DO $mig$
DECLARE
  f   text;
  d   text;
  n   text;
  pat constant text :=
    'COALESCE\(\s*\(auth\.jwt\(\)\s*->\s*''user_metadata''\s*->>\s*''bora_role''\)\s*,\s*\(auth\.jwt\(\)\s*->>\s*''role''\)\s*\)';
  rep constant text :=
    '(CASE WHEN public.is_admin() THEN ''admin'' ELSE COALESCE(auth.jwt() ->> ''role'', '''') END)';
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.wallet_get_balance(uuid)',
    'public.admin_forgive_wallet_debt(uuid, text)',
    'public.wallet_apply_post_delivery_adjustment(text, uuid, integer, text, text)'
  ] LOOP
    d := pg_get_functiondef(f::regprocedure);
    n := regexp_replace(d, pat, rep, 'g');
    IF n = d THEN
      IF d ~ 'user_metadata' THEN
        RAISE EXCEPTION 'seguranca-05: % ainda lê user_metadata mas o padrão não bateu; nada foi mudado', f;
      END IF;
      RAISE NOTICE 'seguranca-05: % já estava corrigida', f;
      CONTINUE;
    END IF;
    EXECUTE n;
    RAISE NOTICE 'seguranca-05: % corrigida (is_admin em vez de user_metadata)', f;
  END LOOP;
END
$mig$;

-- PROVA (correr depois de aplicar):
--   select p.proname, p.prosrc ~ 'user_metadata' as le_user_metadata, p.prosrc ~ 'is_admin\(\)' as usa_is_admin
--     from pg_proc p where p.pronamespace='public'::regnamespace
--     and p.proname in ('get_user_tokens','wallet_get_balance','admin_forgive_wallet_debt','wallet_apply_post_delivery_adjustment');
--   -- esperado: 4 linhas, le_user_metadata = false, usa_is_admin = true
--   -- Testes com set local role: supabase/tests/seguranca_05_2026_11_01_prova.sql (bloco C).
