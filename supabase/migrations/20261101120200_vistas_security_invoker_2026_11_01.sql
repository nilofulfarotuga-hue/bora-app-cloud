-- 01/11/2026 (missão seguranca-05, bloco 3) — as 2 vistas que o advisor marca como SECURITY DEFINER
-- (ERROR security_definer_view): assistant_lojas e platform_settings_publicas.
--
-- assistant_lojas (SELECT sobre restaurants, com EXISTS em products): passa a security_invoker=true.
--   Verificado 01/11: as políticas das tabelas por baixo dão o MESMO acesso aos mesmos papéis —
--     restaurants.restaurants_public_read  {public} SELECT  (approval_status='approved' OR is_admin())
--     products.products_public_read         {public} SELECT  true
--   e a vista já filtra approval_status='approved'. Logo anon e authenticated veem as mesmas linhas
--   com invoker. Ninguém a usa hoje (nem lib/, nem Edge Functions, nem web/: só o client-assistant
--   arquivado a 09/10).
--   ACHADO GRAVE pelo caminho: a vista é auto-atualizável (is_updatable=YES) e anon/authenticated
--   tinham INSERT/UPDATE/DELETE/TRUNCATE nela. Como definer, o dono (postgres, bypassrls) é quem
--   escrevia em restaurants por baixo: um anónimo podia mudar nome/categoria/lat/lng ou APAGAR
--   qualquer loja com um PATCH/DELETE em /rest/v1/assistant_lojas, saltando o RLS. Fecha-se aqui
--   (invoker + só SELECT).
--
-- platform_settings_publicas (SELECT sobre platform_settings): FICA definer, de propósito.
--   A app lê definições ANTES do login (visitante sem sessão) e platform_settings só tem política
--   SELECT para authenticated (platform_settings_select_sem_segredos); com invoker o anon ficava
--   sem nada. A vista já é security_barrier=true, só expõe chaves da lista branca com is_secret=false
--   e anon/authenticated só têm SELECT (confirmado 01/11). É o desenho certo para "público por
--   definição"; o aviso do advisor nesta vista aceita-se e fica documentado aqui.
--
-- Idempotente: ALTER VIEW SET com o mesmo valor e REVOKE repetido não falham.

alter view public.assistant_lojas set (security_invoker = true);

revoke insert, update, delete, truncate, references, trigger on public.assistant_lojas from public, anon, authenticated;
grant select on public.assistant_lojas to anon, authenticated;

-- platform_settings_publicas: garantir que continua só de leitura (hoje já está; fica explícito).
revoke insert, update, delete, truncate, references, trigger on public.platform_settings_publicas from public, anon, authenticated;
grant select on public.platform_settings_publicas to anon, authenticated;

-- PROVA (correr depois de aplicar):
--   select c.relname, (select string_agg(x, ', ') from unnest(c.reloptions) x) as opts
--     from pg_class c where c.relnamespace='public'::regnamespace and c.relname in ('assistant_lojas','platform_settings_publicas');
--   -- esperado: assistant_lojas → security_invoker=true ; platform_settings_publicas → security_barrier=true
--   select table_name, grantee, string_agg(privilege_type, ',') from information_schema.role_table_grants
--     where table_schema='public' and table_name in ('assistant_lojas','platform_settings_publicas')
--     and grantee in ('anon','authenticated') group by 1,2;
--   -- esperado: só SELECT em cada linha
--   set local role anon;  select count(*) from public.assistant_lojas;  reset role;
--   -- esperado: o mesmo número que `select count(*) from public.assistant_lojas` como postgres
--   -- (as lojas aprovadas, ativas, com produtos)
