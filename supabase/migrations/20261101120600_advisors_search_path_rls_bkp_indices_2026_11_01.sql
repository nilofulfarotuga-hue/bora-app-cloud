-- 01/11/2026 (missão seguranca-05, bloco 7) — o que sobra no get_advisors e se resolve por SQL.
--
-- LIDO 01/11/2026 (security + performance):
--   SECURITY
--     ERROR security_definer_view ×2 ............ assistant_lojas, platform_settings_publicas → migração 20261101120200
--     ERROR rls_disabled_in_public ×2 ........... bkp_products_20261101, catalogo_dedupe_log_20261101 → AQUI (A)
--     WARN  function_search_path_mutable ×24 ... 23 funções (uma com 2 sobrecargas) → AQUI (B)
--     WARN  anon_security_definer_function_executable ×51 → migração 20261101120100 (46 ficam, com motivo)
--     WARN  authenticated_security_definer_function_executable ×984 → NÃO se mexe aqui: é a norma da
--           casa (RPCs definer com guarda própria); varrer 984 funções é missão própria, não um fecho cego
--     WARN  auth_otp_long_expiry ×1 ............. PAINEL (Authentication → Email → OTP expiry < 1 h)
--     WARN  auth_leaked_password_protection ×1 .. PAINEL (Authentication → Password → Leaked password protection ON)
--     INFO  rls_enabled_no_policy ×184 .......... tabelas com RLS ligado e sem política = fechadas a anon/authenticated
--           (bkp_*, tabelas internas) — é o estado desejado; só lista
--   PERFORMANCE
--     WARN  duplicate_index ×2 .................. products, web_health_events → AQUI (C)
--     WARN  auth_rls_initplan ×204, multiple_permissive_policies ×527 — trabalho de afinação de políticas
--           (trocar auth.uid() por (select auth.uid()) e fundir políticas); fora do âmbito de segurança, só lista
--     INFO  unindexed_foreign_keys ×69, unused_index ×136, no_primary_key ×166 — só lista
--     INFO  auth_db_connections_absolute ×1 ..... PAINEL (Auth → connections em percentagem)
--
-- (A) As duas tabelas de hoje nasceram sem RLS (cópia de segurança do catálogo e registo do dedupe):
--     expostas por /rest/v1 a anon/authenticated com os grants por omissão. Liga-se RLS sem política
--     (= ninguém lê/escreve senão postgres/service_role) e tiram-se os grants.
-- (B) search_path fixo em 'public, pg_temp' nas 23 funções (todas SECURITY INVOKER, corpo simples, sem
--     extensões, vault, net ou auth — confirmado 01/11), para ninguém lhes "trocar" uma função por
--     search_path manipulado. _haversine_km(numeric×4) já o tinha; a sobrecarga double precision não.
-- (C) Índices idênticos em duplicado: fica um de cada (o mais antigo pelo nome do padrão Supabase).
--
-- Idempotente: IF EXISTS / SET repetido / DROP INDEX IF EXISTS.

-- ── (A) RLS nas tabelas de hoje ──────────────────────────────────────────────────────────────
do $mig$
declare t text;
begin
  foreach t in array array['bkp_products_20261101', 'catalogo_dedupe_log_20261101'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('revoke all on table public.%I from public, anon, authenticated', t);
    end if;
  end loop;
end
$mig$;

-- ── (B) search_path fixo ─────────────────────────────────────────────────────────────────────
do $mig$
declare
  f text;
  lista text[] := array[
    'public.fn_orders_errand_home_stop_fallback()',
    'public._casa_inicio_semana(timestamp with time zone)',
    'public._casa_motivo(text)',
    'public._casa_euro(integer)',
    'public._conformidade_em_falta(jsonb)',
    'public._semana_bate(timestamp with time zone, date)',
    'public.e_robo(text)',
    'public.despacho_toca_atualizada()',
    'public._csv_campo(text)',
    'public._email_bonus_bemvindo_html(text)',
    'public._email_bonus_bemvindo_html(text, text)',
    'public._fecho_stripe_estimado(integer)',
    'public._haversine_km(double precision, double precision, double precision, double precision)',
    'public._haversine_km(numeric, numeric, numeric, numeric)',
    'public._casa_pode_contactar(public.casa_pedidos)',
    'public._nif_valido(text)',
    'public.wallet_kinds_fora_do_saldo()',
    'public._wallet_tx_append_only()',
    'public.driver_settlement_parcelas(integer, numeric, integer, numeric, numeric, numeric, numeric)',
    'public._robo_documentos_caminho(text, text)',
    'public._robo_documentos_item(text, text, text, text, text)',
    'public._robo_documentos_somar(jsonb, jsonb)',
    'public._robo_documentos_juntar(text[])',
    'public._robo_documentos_texto_pedido(text[])',
    'public.product_promo_active(numeric, numeric, boolean, timestamp with time zone, timestamp with time zone, timestamp with time zone)'
  ];
begin
  foreach f in array lista loop
    if to_regprocedure(f) is null then
      raise notice 'seguranca-05 (B): % não existe, salto', f;
      continue;
    end if;
    execute format('alter function %s set search_path = public, pg_temp', f);
  end loop;
end
$mig$;

-- ── (C) índices em duplicado ─────────────────────────────────────────────────────────────────
drop index if exists public.products_search_trgm_idx;          -- fica idx_products_search_trgm
drop index if exists public.web_health_events_criado_idx;      -- fica idx_web_health_events_criado_em

-- PROVA (correr depois de aplicar):
--   select relname, relrowsecurity from pg_class where relnamespace='public'::regnamespace
--     and relname in ('bkp_products_20261101','catalogo_dedupe_log_20261101');          -- esperado: true, true
--   select p.oid::regprocedure::text, p.proconfig from pg_proc p where p.pronamespace='public'::regnamespace
--     and p.proname in ('fn_orders_errand_home_stop_fallback','_casa_inicio_semana','_casa_motivo','_casa_euro',
--       '_conformidade_em_falta','_semana_bate','e_robo','despacho_toca_atualizada','_csv_campo',
--       '_email_bonus_bemvindo_html','_fecho_stripe_estimado','_haversine_km','_casa_pode_contactar','_nif_valido',
--       'wallet_kinds_fora_do_saldo','_wallet_tx_append_only','driver_settlement_parcelas','_robo_documentos_caminho',
--       '_robo_documentos_item','_robo_documentos_somar','_robo_documentos_juntar','_robo_documentos_texto_pedido',
--       'product_promo_active') and p.proconfig is null;                                   -- esperado: 0 linhas
--   select indexname from pg_indexes where schemaname='public'
--     and indexname in ('products_search_trgm_idx','web_health_events_criado_idx');       -- esperado: 0 linhas
--   -- E voltar a correr get_advisors(security): security_definer_view só platform_settings_publicas (aceite),
--   -- rls_disabled_in_public 0, function_search_path_mutable 0, anon_security_definer 46.
