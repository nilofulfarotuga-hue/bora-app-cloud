-- 01/11/2026 (missão seguranca-05, bloco 2) — funções SECURITY DEFINER do schema public que ainda
-- podiam ser chamadas SEM sessão (anon): levantamento, cópia de segurança dos grants e fecho das que
-- não precisam.
--
-- REGRA (CLAUDE.md §5): uma função SQL só fica aberta a `anon` por um de três motivos —
--   (a) a app chama-a ANTES do login (visitante "Sou Cliente" navega SEM sessão nenhuma:
--       platform_settings.visitantes_sem_conta = true e sessao_convidado_ativa = false, lido 01/11);
--   (b) página pública (web/viagem.html, web/fiscalizacao.html, site boraguarda.com);
--   (c) robô da VPS/Hermes que se identifica por p_chave validada contra o cofre.
--
-- LEVANTAMENTO 01/11/2026 (51 funções definer com EXECUTE para anon; callers procurados em lib/,
-- web/, ferramentas/, scripts/, supabase/functions/, hermes/, cron.job e noutras funções SQL):
--
-- FECHAM (5) — nenhum caminho sem sessão as usa:
--   contadores_redes(date)            — estatísticas de visitas/BEMVINDO; sem chamador no repo, só MCP/painel (postgres/authenticated)
--   visitas_por_origem(date)          — idem; a auditoria de 29/10 já as apontava como fuga de estatísticas a anónimos
--   visitas_pessoas_e_robos(date)     — idem
--   is_partner_open(text,timestamptz) — só o painel admin (sessão) e 7 funções SQL (contexto definer, não precisa do grant)
--   get_driver_ratings_summary(text)  — só o ecrã de avaliações do estafeta, depois de um pedido (sessão)
--
-- FICAM (46), com o motivo:
--   (a) app antes do login / visitante sem sessão:
--     get_setting, log_client_crash, home_mais_pedidos, banner_evento, cliente_pesquisar, casa_config,
--     store_active_promotions, get_restaurant_ratings_summary, quote_order_pricing, search_businesses,
--     carwash_quote, get_available_slots, client_search_availability, tvde_calculate_fare,
--     tvde_quote_roundtrip, tvde_plan_price_cents, tvde_conformidade_config, tvde_operador_plataforma,
--     is_admin (as políticas RLS de restaurants/products chamam-na: sem o grant, o anon deixava de ler lojas)
--   (a') estafeta em segundo plano sem sessão (foreground_service bate com a chave pública):
--     driver_heartbeat_segredo (valida segredo próprio), driver_heartbeat_by_id (sem segredo: só mexe em
--     last_heartbeat_at — fraco, mas é o recurso quando o segredo falha; fica anotado)
--   (b) páginas públicas por token longo:
--     tvde_ver_partilha (web/viagem.html), tvde_fiscal_consulta (web/fiscalizacao.html),
--     verificar_ficha_publica (ficha pública da loja), registar_visita_baixar (página /baixar do site)
--   (c) robôs com p_chave validada contra vault.decrypted_secrets (confirmado função a função):
--     caca_resumo_manha, campanha_pago_resumo, carteiro_fila, carteiro_ligar, carteiro_marcar,
--     carteiro_registo, carteiro_resumo_dia, carteiro_threads, decidir_sombra, playbook_redes_registar,
--     prospect_amostra_registar, prospect_contacto_registar, prospect_proposta_registar, prospect_registar,
--     prospects_ler, radar_pesquisas_do_dia, radar_pesquisas_do_tema, radar_videos_ler, radar_videos_registar,
--     redator_fila, secretario_prospect_registar
--
-- Voltar atrás: para cada linha de bkp_function_grants_20261101 com tinha_anon=true,
--   grant execute on function <funcao> to anon;
-- Idempotente: a cópia só se cria se não existir; o REVOKE não falha se já não houver grant.

create table if not exists public.bkp_function_grants_20261101 (
  funcao       text primary key,
  tinha_anon   boolean not null,
  tinha_authd  boolean not null,
  tinha_public boolean not null,
  guardado_em  timestamptz not null default now()
);
alter table public.bkp_function_grants_20261101 enable row level security;
revoke all on table public.bkp_function_grants_20261101 from public, anon, authenticated;

insert into public.bkp_function_grants_20261101 (funcao, tinha_anon, tinha_authd, tinha_public)
select p.oid::regprocedure::text,
       has_function_privilege('anon', p.oid, 'execute'),
       has_function_privilege('authenticated', p.oid, 'execute'),
       has_function_privilege('public', p.oid, 'execute')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosecdef
   and has_function_privilege('anon', p.oid, 'execute')
on conflict (funcao) do nothing;

-- ── Fecho (uma por linha) ────────────────────────────────────────────────────────────────────
-- `from public` também, porque o EXECUTE a anon pode vir do grant implícito a PUBLIC;
-- authenticated e service_role mantêm o que tinham.
revoke execute on function public.contadores_redes(date)                                 from public, anon; -- estatísticas, só MCP/painel
revoke execute on function public.visitas_por_origem(date)                               from public, anon; -- estatísticas, só MCP/painel
revoke execute on function public.visitas_pessoas_e_robos(date)                          from public, anon; -- estatísticas, só MCP/painel
revoke execute on function public.is_partner_open(text, timestamp with time zone)        from public, anon; -- painel admin + funções SQL
revoke execute on function public.get_driver_ratings_summary(text)                       from public, anon; -- ecrã pós-pedido, com sessão

grant execute on function public.contadores_redes(date)                          to authenticated, service_role;
grant execute on function public.visitas_por_origem(date)                        to authenticated, service_role;
grant execute on function public.visitas_pessoas_e_robos(date)                   to authenticated, service_role;
grant execute on function public.is_partner_open(text, timestamp with time zone) to authenticated, service_role;
grant execute on function public.get_driver_ratings_summary(text)                to authenticated, service_role;

-- PROVA (correr depois de aplicar):
--   select count(*) from public.bkp_function_grants_20261101;                      -- esperado: 51
--   select p.proname from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef
--     and has_function_privilege('anon', p.oid, 'execute') order by 1;            -- esperado: 46 linhas, sem as 5 fechadas
--   select p.proname, has_function_privilege('authenticated', p.oid, 'execute') as authd
--     from pg_proc p where p.pronamespace='public'::regnamespace
--     and p.proname in ('contadores_redes','visitas_por_origem','visitas_pessoas_e_robos','is_partner_open','get_driver_ratings_summary');
--                                                                                  -- esperado: 5 linhas, authd = true
--   -- Arranque a frio da app como visitante (sem sessão): home, lupa, loja e carrinho continuam a carregar.
