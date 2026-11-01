-- supabase/tests/seguranca_05_2026_11_01_prova.sql
-- Provas da missão seguranca-05 (01/11/2026). Correr DEPOIS das migrações 20261101120100..120600.
-- Cada bloco corre numa transação e termina em ROLLBACK: não deixa nada escrito.
-- Como correr: cada bloco (BEGIN ... ROLLBACK) de uma vez no MCP execute_sql ou no SQL editor.
-- "esperado" está em comentário no fim de cada passo.

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- BLOCO A — guarda de colunas dos prestadores (migração 120300)
-- ════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
-- um lavador real (qualquer; se não houver, o UPDATE abaixo não apanha linhas e o teste é inconclusivo)
SELECT set_config('request.jwt.claims',
         json_build_object('sub', w.user_id, 'role', 'authenticated')::text, true) AS claims,
       w.user_id, w.approval_status AS antes_status, w.iban AS antes_iban
  FROM public.washers w ORDER BY created_at DESC LIMIT 1;
SET LOCAL ROLE authenticated;
UPDATE public.washers
   SET approval_status = 'approved', is_banned = false, iban = 'PT50000000000000000000000',
       rating_avg = 5, bio = 'bio editada pelo próprio (permitido)'
 WHERE user_id = (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid
 RETURNING approval_status, is_banned, iban, rating_avg, bio;
-- esperado: approval_status/iban/rating_avg IGUAIS ao "antes"; bio mudou (não é sensível)
RESET ROLE;
SELECT fluxo, passo, estado, detalhe FROM public.e2e_log
 WHERE fluxo = 'prestador-colunas-guarda' ORDER BY id DESC LIMIT 1;
-- esperado: 1 linha 'bloqueado' com "tentou mudar approval_status, iban, rating_avg em washers"
ROLLBACK;

BEGIN;
-- admin passa (o Danilo): o gatilho não interfere
SELECT set_config('request.jwt.claims',
         json_build_object('sub', u.id, 'role', 'authenticated')::text, true)
  FROM auth.users u WHERE u.email = 'nilofulfarotuga@gmail.com';
SET LOCAL ROLE authenticated;
UPDATE public.washers SET rating_avg = COALESCE(rating_avg, 0)
 WHERE id = (SELECT id FROM public.washers ORDER BY created_at DESC LIMIT 1)
 RETURNING id, rating_avg;
-- esperado: 1 linha, sem erro (admin pode)
RESET ROLE;
ROLLBACK;

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- BLOCO B — orders_insert_client fechada (migração 120400)
-- ════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('request.jwt.claims',
         json_build_object('sub', o.user_id, 'role', 'authenticated')::text, true) AS claims
  FROM public.orders o WHERE o.user_id IS NOT NULL ORDER BY created_at DESC LIMIT 1;
SET LOCAL ROLE authenticated;
-- 1) inserção crua pelo cliente: tem de FALHAR com 42501 (new row violates row-level security policy)
INSERT INTO public.orders (id, user_id, status, payment_status, service_type, price, final_total,
                           driver_earnings, platform_commission, payment_method)
VALUES ('teste-seguranca-05', (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid,
        'delivered', 'paid', 'restaurant', 0.01, 0.01, 50, 0, 'cash');
-- esperado: ERROR 42501 new row violates row-level security policy for table "orders"
ROLLBACK;

BEGIN;
-- 2) o caminho da app continua a existir: create_order é EXECUTE para authenticated e definer
SELECT p.proname, p.prosecdef, has_function_privilege('authenticated', p.oid, 'execute') AS authd
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'create_order';
-- esperado: prosecdef = true, authd = true
SELECT policyname, with_check FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'orders' AND cmd = 'INSERT';
-- esperado: orders_insert_client 'false', orders_insert_partner 'false'
ROLLBACK;

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- BLOCO C — tokens e carteira só do próprio/admin (migração 120500)
-- ════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
-- cliente A com sessão tenta ler os tokens do cliente B (ids guardados ANTES de trocar de papel,
-- porque como authenticated o RLS de bora_tokens só mostra as linhas do próprio)
SELECT set_config('request.jwt.claims',
         json_build_object('sub', a.user_id, 'role', 'authenticated')::text, true) AS claims,
       set_config('teste.b_id', b.user_id::text, true) AS b_id
  FROM (SELECT DISTINCT user_id FROM public.bora_tokens ORDER BY 1 LIMIT 1) a,
       (SELECT DISTINCT user_id FROM public.bora_tokens ORDER BY 1 OFFSET 1 LIMIT 1) b;
SET LOCAL ROLE authenticated;
SELECT public.get_user_tokens(current_setting('teste.b_id', true)::uuid);
-- esperado: ERROR 42501 forbidden: get_user_tokens só do próprio
ROLLBACK;

BEGIN;
-- o próprio lê os seus: OK
SELECT set_config('request.jwt.claims',
         json_build_object('sub', a.user_id, 'role', 'authenticated')::text, true)
  FROM (SELECT DISTINCT user_id FROM public.bora_tokens LIMIT 1) a;
SET LOCAL ROLE authenticated;
SELECT public.get_user_tokens((current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid) AS meus_tokens;
-- esperado: um número (>= 0), sem erro
SELECT (public.wallet_get_balance())::jsonb ->> 'user_id' AS carteira_de;
-- esperado: o próprio user_id, sem erro
ROLLBACK;

BEGIN;
-- conta normal que se "auto-promove" por user_metadata.bora_role = 'admin' (o buraco antigo):
SELECT set_config('request.jwt.claims',
         json_build_object('sub', a.user_id, 'role', 'authenticated',
                           'user_metadata', json_build_object('bora_role', 'admin'))::text, true),
       set_config('teste.b_id', b.user_id::text, true)
  FROM (SELECT user_id FROM public.client_wallets ORDER BY user_id LIMIT 1) a,
       (SELECT user_id FROM public.client_wallets ORDER BY user_id OFFSET 1 LIMIT 1) b;
SET LOCAL ROLE authenticated;
SELECT public.wallet_get_balance(current_setting('teste.b_id', true)::uuid);
-- esperado: ERROR 42501 forbidden (antes da migração devolvia a carteira de outra pessoa)
ROLLBACK;

BEGIN;
SELECT set_config('request.jwt.claims',
         json_build_object('sub', a.user_id, 'role', 'authenticated',
                           'user_metadata', json_build_object('bora_role', 'admin'))::text, true),
       set_config('teste.devedor', coalesce((SELECT user_id::text FROM public.client_wallets WHERE free_balance_cents < 0 LIMIT 1), a.user_id::text), true)
  FROM (SELECT user_id FROM public.client_wallets ORDER BY user_id LIMIT 1) a;
SET LOCAL ROLE authenticated;
SELECT public.admin_forgive_wallet_debt(current_setting('teste.devedor', true)::uuid, 'teste seguranca-05');
-- esperado: ERROR 42501 unauthorized: admin only (antes da migração perdoava a dívida)
ROLLBACK;

-- sem sessão (cron/gatilho) continua a poder ler qualquer conta:
BEGIN;
SELECT public.get_user_tokens((SELECT DISTINCT user_id FROM public.bora_tokens LIMIT 1)) AS tokens_sem_sessao;
-- esperado: número, sem erro (auth.uid() IS NULL)
ROLLBACK;

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- BLOCO D — vistas (migração 120200)
-- ════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT count(*) AS como_postgres FROM public.assistant_lojas;
SET LOCAL ROLE anon;
SELECT count(*) AS como_anon FROM public.assistant_lojas;
-- esperado: como_anon = como_postgres
SELECT count(*) AS defs_publicas FROM public.platform_settings_publicas;
-- esperado: > 0 (o visitante continua a ler as definições públicas)
UPDATE public.assistant_lojas SET name = 'hack' WHERE true;
-- esperado: ERROR 42501 permission denied for view assistant_lojas
-- (a transação fica abortada a partir daqui; o ROLLBACK limpa tudo)
ROLLBACK;

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- BLOCO E — funções fechadas a anon (migração 120100)
-- ════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL ROLE anon;
SELECT public.contadores_redes(current_date);
-- esperado: ERROR 42501 permission denied for function contadores_redes
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
SELECT public.get_setting('visitantes_sem_conta') AS visitante_pode_ver,
       (SELECT count(*) FROM public.home_mais_pedidos(5)) AS home,
       (SELECT jsonb_typeof(public.cliente_pesquisar('pizza', 5))) AS lupa;
-- esperado: true, número, 'object' — o visitante sem sessão continua a navegar
RESET ROLE;
ROLLBACK;
