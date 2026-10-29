-- =====================================================================================================
-- S1 — platform_settings: fechar as chaves secretas            PREPARADO, NÃO APLICADO (29/10/2026)
-- Missão final-app-2026-10-29, bloco 6.c. Autorizado pelo Danilo a 29/10 14:22 (proposta prop-c253185d,
-- estado aprovada_danilo: "eu autorizo os 4 de dinheiro"). Quem aplica é o líder, logo a seguir.
-- =====================================================================================================
--
-- O PROBLEMA (provado em transação desfeita, hoje, ver S1_prova_rollback.sql):
--   · A política platform_settings_select_authed deixa QUALQUER conta com sessão ler a tabela inteira:
--     um cliente comum vê 48 chaves is_secret de 463 (markup oculto, comissões, taxa Stripe, telefone
--     MB Way da Bora, relatórios internos). Antes do S1: cliente = 48 secretas visíveis.
--   · A função get_setting devolve a chave secreta a quem a chama SEM claims (o current_user dentro
--     de uma função SECURITY DEFINER é o dono). Pela API não se chega lá (HTTP real: anon -> null);
--     chega-se por ligação direta/pg_net. Antes do S1: "sem claims, papel authenticated" = VALOR.
--   · 3 tabelas bkp_* de 28/10 ficaram SEM RLS e com todos os privilégios para anon (a chave pública
--     do bundle web lê-as: 200 com o código de 2 funções de pagamento). Passo 0 fecha-as.
--
-- O QUE ESTE FICHEIRO FAZ (por ordem; aplicar de uma vez, numa transação — apply_migration já o faz;
-- por execute_sql embrulhar em begin/commit):
--   0. Fecha as tabelas bkp_*: RLS ligada onde faltava (3) e sem privilégios para anon/authenticated em todas (84, provado em transação desfeita).
--   1. Backups novos (RLS ligada, fechados): função get_setting e políticas de platform_settings.
--   2. get_setting com a regra nova (com claims: só service_role ou is_admin(); sem claims: só
--      session_user postgres/supabase_admin). Chaves NÃO secretas: iguais a hoje, para toda a gente.
--   3. Política nova de leitura: não secretas para toda a conta com sessão; secretas só para admin; e
--      as duas percentagens que o ecrã "novo produto" do parceiro lê direto da tabela
--      (partner_visible_commission_pct, partner_hidden_markup_pct) só para quem é dono de loja.
--   4. Vista platform_settings_publicas: lista branca das chaves que a app lê (nome a nome no fim),
--      legível por anon e por contas com sessão. NÃO é obrigatória para a app de hoje (as leituras
--      diretas continuam a funcionar pela política do passo 3); é o caminho limpo para a fase 2.
--
-- O QUE NÃO FAZ: não toca em valores, preços, comissões nem em nenhuma função de pagamento/dinheiro;
--   nenhum DML em tabelas de dinheiro (não há INSERT/UPDATE/DELETE em tabelas de pedidos, carteira,
--   tokens, motoristas). As funções de preço leem chaves secretas, mas só são chamadas por funções
--   SECURITY DEFINER do dono postgres (RLS não se aplica) — ver AUDITORIA, secção S1.
--   NOTA PARA A TRANCA: este SQL não nomeia nenhuma função da lista de dinheiro. As tabelas de
--   backup do passo 0 têm o nome de uma delas dentro do nome (as bkp_fn_fi…): por isso o passo 0
--   usa um bloco genérico por padrão 'bkp_%' e nunca escreve esses nomes. Ao copiar para
--   supabase/migrations a tranca pergunta (palavras wallet_/stripe_ nos nomes das chaves): é esperado.
--
-- PROVA JÁ FEITA (transação desfeita, 29/10, ficheiro S1_prova_rollback.sql, nada ficou no banco):
--   ANTES   cliente      tabela: 48 secretas de 463 linhas | get_setting(secreta): NULL (com claims)
--   ANTES   sem claims, papel authenticated: get_setting(secreta) = VALOR   <- a fuga
--   DEPOIS  anon         tabela: 0 de 0 linhas | get_setting NULL | vista 87 linhas (0 secretas)
--   DEPOIS  cliente      tabela: 0 secretas de 415 linhas | parceiros: 0 de 2 | get_setting NULL
--   DEPOIS  parceiro     tabela: 2 secretas de 417 linhas | parceiros: 2 de 2 | get_setting NULL
--   DEPOIS  admin        tabela: 48 de 463 | get_setting VALOR        service_role: 48 de 463 | VALOR
--   DEPOIS  claims vazios {} -> NULL ; interno sem claims (session_user=postgres) -> VALOR
--   IGUAIS  81 chaves da app: md5 igual por tabela (cliente), por vista (cliente e anon) e por
--           get_setting = md5 da referência (como postgres)
--   Limite: o editor SQL liga-se como postgres e não pode mudar o session_user para 'authenticator';
--   o caso real do PostgREST (authenticator, sem claims -> NULL) está provado pela expressão
--   (session_user in ('postgres','supabase_admin')), não ao vivo.
--
-- PREÇOS IGUAIS (baseline de hoje, ficheiro S1_prova_precos_antes_depois.sql): o líder volta a correr
--   o mesmo script depois de aplicar e compara os dois md5. As funções de preço INVOKER (as 4 que leem
--   chaves secretas) dão a conta normal o MESMO número que ao anon (que já hoje não vê a tabela): o
--   valor de recurso escrito no código é igual ao valor em produção (0,10 e 0,05) — provado.
--
-- FASE 2 (NÃO aplicar agora): ver o bloco no fim. Só depois de a app deixar de ler a tabela direta
--   (11 ficheiros do lib/, listados abaixo), versão mínima nas 3 lojas, e RPC para o ecrã do parceiro.
--
-- REVERTER (ordem inversa): bloco "REVERTER" no fim; o corpo antigo do get_setting fica em
--   public.bkp_fn_get_setting_20261029.definicao (md5 918dd2fe2712007059bbecc3322fef3f).
-- =====================================================================================================


-- ---------------------------------------------------------------------------------------------------
-- PASSO 0 — fechar as tabelas bkp_* que ficaram sem RLS e abertas a anon/authenticated
-- ---------------------------------------------------------------------------------------------------
do $fechar$
declare t text; v_rls boolean;
begin
  for t, v_rls in
    select c.relname, c.relrowsecurity from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname like 'bkp\_%'
  loop
    if not v_rls then
      execute format('alter table public.%I enable row level security', t);
      raise notice 'RLS ligada: %', t;
    end if;
    -- sem RLS ninguém devia ler; sem privilégios nem a RLS é precisa para os guardar
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end
$fechar$;


-- ---------------------------------------------------------------------------------------------------
-- PASSO 1 — backups (RLS ligada e fechados a anon/authenticated desde o nascimento)
-- ---------------------------------------------------------------------------------------------------
create table if not exists public.bkp_fn_get_setting_20261029 as
  select now() as guardado_em,
         p.proname::text as nome,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_userbyid(p.proowner)::text as dono,
         p.proacl::text as acl,
         md5(pg_get_functiondef(p.oid)) as md5,
         pg_get_functiondef(p.oid) as definicao
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_setting';
alter table public.bkp_fn_get_setting_20261029 enable row level security;
revoke all on public.bkp_fn_get_setting_20261029 from anon, authenticated;

create table if not exists public.bkp_pol_platform_settings_20261029 as
  select now() as guardado_em, schemaname::text as esquema, tablename::text as tabela, policyname::text as politica,
         permissive, roles::text as papeis, cmd, qual, with_check
    from pg_policies
   where schemaname = 'public' and tablename = 'platform_settings';
alter table public.bkp_pol_platform_settings_20261029 enable row level security;
revoke all on public.bkp_pol_platform_settings_20261029 from anon, authenticated;

-- a vista nova não tem backup (é aditiva): reverte-se com drop view.


-- ---------------------------------------------------------------------------------------------------
-- PASSO 2 — get_setting com a regra nova (mesma assinatura, mesmo dono, mesmos grants, STABLE DEFINER)
--   com claims  : só service_role ou is_admin() veem chave secreta;
--   sem claims  : só se o session_user for postgres ou supabase_admin (pg_cron, chamadas internas,
--                 editor SQL); 'authenticator' e outros papéis nunca;
--   não secretas: devolvidas a toda a gente, como hoje.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.get_setting(p_key text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_row    record;
  v_claims text;
  v_role   text;
  v_admin  boolean := false;
begin
  select value, is_secret into v_row from public.platform_settings where key = p_key;
  if not found then return null; end if;
  if not v_row.is_secret then return v_row.value; end if;

  -- Chave sensível: só passa a quem tem autoridade.
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  if v_claims is not null then
    -- Pedido pela API (PostgREST / Edge): decide o papel do token.
    begin
      v_role := v_claims::jsonb ->> 'role';
    exception when others then
      v_role := null;
    end;
    if v_role = 'service_role' then
      return v_row.value;
    end if;
    begin
      v_admin := public.is_admin();
    exception when others then
      v_admin := false;
    end;
    if v_admin then return v_row.value; end if;
    return null;
  end if;

  -- Sem claims: só o próprio servidor. O session_user é quem abriu a ligação
  -- (o current_user aqui dentro é sempre o dono da função).
  if session_user in ('postgres', 'supabase_admin') then
    return v_row.value;
  end if;
  return null;
end $function$;

grant execute on function public.get_setting(text) to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------------------------------
-- PASSO 3 — política de leitura: chaves secretas só para admin (service_role já ignora a RLS)
--   · Não secretas: toda a conta com sessão, como hoje (a app lê taxas, horários, textos por aqui).
--   · Secretas: só admin.
--   · Exceção de compatibilidade: partner_visible_commission_pct e partner_hidden_markup_pct, que o
--     ecrã "novo produto" do parceiro (lib/services/partner_price_rules.dart:99, chamado por
--     lib/screens/add_product_screen.dart:136) lê direto da tabela com a sessão do parceiro. Só
--     para quem é dono de loja (parceiro_minhas_lojas()). DECISÃO DO DANILO a confirmar: se o
--     parceiro não deve ver estas duas percentagens, a fase 2 mete-as numa RPC (lib/ muda).
--   · anon continua sem política (RLS nega), como hoje.
-- ---------------------------------------------------------------------------------------------------
drop policy if exists platform_settings_select_authed on public.platform_settings;

create policy platform_settings_select_sem_segredos on public.platform_settings
  for select to authenticated
  using (
    coalesce(is_secret, false) = false
    or (select public.is_admin())
    or (
      key in ('partner_visible_commission_pct', 'partner_hidden_markup_pct')
      and exists (select 1 from public.parceiro_minhas_lojas())
    )
  );


-- ---------------------------------------------------------------------------------------------------
-- PASSO 4 — vista pública: só as chaves que a app lê (lista nome a nome no fim do ficheiro)
--   O Supabase vai marcar esta vista no aviso "security_definer_view" (ERRO de lint 0010): é de
--   propósito — é o que deixa o anon ler a lista branca sem política na tabela. security_barrier
--   impede que um filtro do chamador veja linhas fora da lista. Só key e value; nunca is_secret.
-- ---------------------------------------------------------------------------------------------------
create or replace view public.platform_settings_publicas
  with (security_barrier = true)
as
select s.key, s.value
  from public.platform_settings s
 where coalesce(s.is_secret, false) = false
   and (
     s.key = any (array[
       'app_latest_version_code','app_latest_version_code_ios','app_min_supported_version_code','app_min_supported_version_code_ios','app_update_notes_pt',
       'appointment_max_advance_days','appointment_reschedule_max_count','assistant_enabled','cancel_fee_after_accept_cents','cancel_fee_after_pickup_ratio',
       'cancel_fee_before_dispatch_cents','cancel_grace_seconds','carwash_enabled','carwash_interior_enabled','carwash_stripe_enabled',
       'cleaning_cancel_free_hours','cleaning_cancel_half_hours','cleaning_min_hours','cleaning_min_lead_hours','cleaning_stripe_enabled',
       'client_live_location_enabled','client_live_location_interval_seconds','delivery_base_fee_cents','dispatch_gps_fresh_seconds','dispatch_offer_timeout_seconds',
       'errand_home_stop_fee_cents','errand_max_advance_cents','eta_avg_speed_kmh','eta_shopping_minutes_nonpartner_max','eta_shopping_minutes_nonpartner_min',
       'favor_pellets_max_sacos','ios_hide_nonpartner_logos','map_route_line_width','max_cash_amount_cents','min_order_cents',
       'non_partner_service_fee_cents','non_partner_service_fee_strikethrough_cents','order_edit_enabled','payment_sheet_timeout_seconds','sessao_convidado_ativa',
       'small_order_fee_cents','small_order_fee_enabled','tips_enabled','token_balance_max_use_pct','token_payment_max_pct',
       'token_value_cents_x100','tvde_base_distance_km','tvde_card_payments_enabled','tvde_dest_change_enabled','tvde_driver_card_poll_seconds',
       'tvde_driver_lost_seconds','tvde_driver_stale_seconds','tvde_encomendas_enabled','tvde_eta_arriving_push_min','tvde_eta_client_discount_max_min',
       'tvde_eta_client_discount_pct','tvde_eta_client_floor_min','tvde_extra_per_km_cents','tvde_extra_ride_cents','tvde_max_stops',
       'tvde_nav_camera_follow_ms','tvde_nav_offroute_fixes','tvde_nav_offroute_meters','tvde_nav_reroute_min_seconds','tvde_nav_tilt',
       'tvde_nav_zoom','tvde_noshow_wait_minutes','tvde_pos_ao_vivo_enabled','tvde_pos_ao_vivo_intervalo_s','tvde_reservation_dest_change_enabled',
       'tvde_reservation_enabled','tvde_reservation_free_cancel_hours','tvde_reservation_max_advance_days','tvde_reservation_min_advance_minutes','tvde_reservation_payment_timeout_minutes',
       'tvde_ride_gps_interval_seconds','tvde_roundtrip_reservation_enabled','tvde_stop_fee_cents','tvde_stop_timer_seconds','visitantes_sem_conta',
       'wallet_split_free_pct','web_card_payments_enabled'
     ])
     or s.key like 'limpeza\_guia\_%'
   );

revoke all on public.platform_settings_publicas from public, anon, authenticated;
grant select on public.platform_settings_publicas to anon, authenticated;
comment on view public.platform_settings_publicas is
  'S1 29/10/2026: lista branca das definições que a app lê (nunca is_secret). Manter em sincronia com lib/ (nome a nome em docs/propostas/missao-geral-2026-10-28/janela2/S1_platform_settings_segredos.sql).';


-- ---------------------------------------------------------------------------------------------------
-- OPCIONAL, defesa em profundidade (não faz parte do fecho; aplicar à parte se o Danilo quiser):
-- anon e authenticated têm INSERT/UPDATE/DELETE/TRUNCATE na tabela; a RLS (só há política de leitura)
-- já os nega, mas um erro futuro numa política abriria a escrita das taxas.
-- (as escritas legítimas passam por admin_update_setting, SECURITY DEFINER, que não precisa disto)
--   revoke insert, update, delete, truncate, references, trigger on public.platform_settings from anon, authenticated;
-- ---------------------------------------------------------------------------------------------------


-- ---------------------------------------------------------------------------------------------------
-- FASE 2 — NÃO APLICAR AGORA. Condições: (a) lib/ deixa de ler a tabela direta (11 ficheiros:
--   lib/config/ios_launch_flags.dart:64, lib/services/assistant_service.dart:622,
--   lib/services/definicoes_publicas.dart:18, lib/services/favor_definicoes.dart:40,
--   lib/services/folha_cartao.dart:55, lib/services/limite_dinheiro_service.dart:54,
--   lib/services/order_edit_service.dart:33, lib/services/payment_service.dart:28,
--   lib/stores/carwash_store.dart:60, lib/widgets/guia_limpeza.dart:32 -> .from('platform_settings_publicas');
--   lib/services/partner_price_rules.dart:99 -> RPC nova só para dono de loja/admin);
--   (b) versão mínima suportada nas 3 lojas já acima da que ainda lê a tabela; (c) prova nas 3
--   plataformas. Depois: a leitura direta passa a ser só admin e a vista é o único caminho público.
--
--   drop policy platform_settings_select_sem_segredos on public.platform_settings;
--   create policy platform_settings_select_so_admin on public.platform_settings
--     for select to authenticated using ((select public.is_admin()));
-- ---------------------------------------------------------------------------------------------------


-- ---------------------------------------------------------------------------------------------------
-- REVERTER (ordem inversa; cada linha é independente)
--   drop view if exists public.platform_settings_publicas;
--   drop policy if exists platform_settings_select_sem_segredos on public.platform_settings;
--   create policy platform_settings_select_authed on public.platform_settings for select to authenticated using (true);
--   -- função: correr o texto de  select definicao from public.bkp_fn_get_setting_20261029;
-- ---------------------------------------------------------------------------------------------------


-- ---------------------------------------------------------------------------------------------------
-- A LISTA, NOME A NOME — o que a app lê de platform_settings (lib/, fora do painel admin), com o
-- ficheiro:linha da primeira leitura (+N = mais N sítios). Extraída por script (varrimento de
-- 'p_key', getSetting*, .eq('key'), inFilter('key'), .like('key'), constantes kChave/kAtual/kRisco,
-- lerDefinicoesPublicas) e confirmada contra a base: 81 existem, todas is_secret = false.
-- "SEM sessão" = lida antes do login (arranque, login, carrinho de convidado); "com sessão" = depois.
-- "tabela" = .from('platform_settings') direto (passo 3 mantém); "rpc" = get_setting (passo 2 mantém).
-- ---------------------------------------------------------------------------------------------------
--   app_latest_version_code                        SEM sessão  rpc    lib/services/app_update_service.dart:101
--   app_latest_version_code_ios                    SEM sessão  rpc    lib/services/app_update_service.dart:101
--   app_min_supported_version_code                 SEM sessão  rpc    lib/services/app_update_service.dart:104
--   app_min_supported_version_code_ios             SEM sessão  rpc    lib/services/app_update_service.dart:104
--   app_update_notes_pt                            SEM sessão  rpc    lib/services/app_update_service.dart:105
--   appointment_max_advance_days                   com sessão  rpc    lib/stores/services_store.dart:194
--   appointment_reschedule_max_count               com sessão  rpc    lib/stores/services_store.dart:209
--   assistant_enabled                              SEM sessão  tabela lib/services/assistant_service.dart:624
--   cancel_fee_after_accept_cents                  com sessão  rpc    lib/screens/order_details_screen.dart:348
--   cancel_fee_after_pickup_ratio                  com sessão  rpc    lib/screens/order_details_screen.dart:350
--   cancel_fee_before_dispatch_cents               com sessão  rpc    lib/screens/order_details_screen.dart:346
--   cancel_grace_seconds                           com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:351
--   carwash_enabled                                com sessão  tabela lib/stores/carwash_store.dart:62
--   carwash_interior_enabled                       com sessão  tabela lib/stores/carwash_store.dart:62
--   carwash_stripe_enabled                         com sessão  tabela lib/stores/carwash_store.dart:62
--   cleaning_cancel_free_hours                     com sessão  rpc    lib/screens/client/cleaning/cleaning_tracking_screen.dart:83
--   cleaning_cancel_half_hours                     com sessão  rpc    lib/screens/client/cleaning/cleaning_tracking_screen.dart:84
--   cleaning_min_hours                             com sessão  rpc    lib/screens/client/cleaning/cleaning_wizard_screen.dart:111
--   cleaning_min_lead_hours                        com sessão  rpc    lib/screens/client/cleaning/cleaning_wizard_screen.dart:110
--   cleaning_stripe_enabled                        com sessão  rpc    lib/stores/cleaning_store.dart:57
--   client_live_location_enabled                   com sessão  rpc    lib/services/driver_live_feed.dart:156
--   client_live_location_interval_seconds          com sessão  rpc    lib/services/driver_live_feed.dart:157
--   delivery_base_fee_cents                        SEM sessão  tabela lib/services/small_order_fee.dart:119
--   dispatch_gps_fresh_seconds                     com sessão  rpc    lib/utils/gps_parado.dart:75
--   dispatch_offer_timeout_seconds                 com sessão  rpc    lib/screens/driver_home_screen.dart:3911
--   errand_home_stop_fee_cents                     com sessão  tabela lib/services/favor_definicoes.dart:42
--   errand_max_advance_cents                       com sessão  tabela lib/services/favor_definicoes.dart:42
--   eta_avg_speed_kmh                              com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:352 (+2)
--   eta_shopping_minutes_nonpartner_max            com sessão  rpc    lib/services/order_eta_service.dart:62
--   eta_shopping_minutes_nonpartner_min            com sessão  rpc    lib/services/order_eta_service.dart:61
--   favor_pellets_max_sacos                        com sessão  tabela lib/services/favor_definicoes.dart:42
--   ios_hide_nonpartner_logos                      SEM sessão  tabela lib/config/ios_launch_flags.dart:66
--   map_route_line_width                           com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:690 (+1)
--   max_cash_amount_cents                          com sessão  tabela lib/services/limite_dinheiro_service.dart:22
--   min_order_cents                                SEM sessão  tabela lib/services/small_order_fee.dart:119
--   non_partner_service_fee_cents                  SEM sessão  tabela lib/services/remote_fees_service.dart:64
--   non_partner_service_fee_strikethrough_cents    SEM sessão  tabela lib/services/remote_fees_service.dart:65
--   order_edit_enabled                             com sessão  tabela lib/services/order_edit_service.dart:35
--   payment_sheet_timeout_seconds                  com sessão  tabela lib/services/folha_cartao.dart:57
--   sessao_convidado_ativa                         SEM sessão  rpc    lib/auth/auth_store.dart:645
--   small_order_fee_cents                          SEM sessão  tabela lib/services/small_order_fee.dart:119
--   small_order_fee_enabled                        SEM sessão  tabela lib/services/small_order_fee.dart:119
--   tips_enabled                                   com sessão  rpc    lib/services/tip_service.dart:35
--   token_balance_max_use_pct                      com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:2614 (+1)
--   token_payment_max_pct                          com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:2600 (+1)
--   token_value_cents_x100                         com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:2629 (+1)
--   tvde_base_distance_km                          com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:260
--   tvde_card_payments_enabled                     com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:256
--   tvde_dest_change_enabled                       com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:348
--   tvde_driver_card_poll_seconds                  com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:354 (+1)
--   tvde_driver_lost_seconds                       com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:368
--   tvde_driver_stale_seconds                      com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:366
--   tvde_encomendas_enabled                        com sessão  rpc    lib/screens/driver/tvde/tvde_driver_home_screen.dart:125 (+1)
--   tvde_eta_arriving_push_min                     com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:363
--   tvde_eta_client_discount_max_min               com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:358
--   tvde_eta_client_discount_pct                   com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:356
--   tvde_eta_client_floor_min                      com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:360
--   tvde_extra_per_km_cents                        com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:259
--   tvde_extra_ride_cents                          com sessão  rpc    lib/screens/client/tvde/tvde_request_ride_screen.dart:261
--   tvde_max_stops                                 com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:347 (+1)
--   tvde_nav_camera_follow_ms                      com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:689
--   tvde_nav_offroute_fixes                        com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:686
--   tvde_nav_offroute_meters                       com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:685
--   tvde_nav_reroute_min_seconds                   com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:688
--   tvde_nav_tilt                                  com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:684
--   tvde_nav_zoom                                  com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:683
--   tvde_noshow_wait_minutes                       com sessão  rpc    lib/stores/tvde_driver_store.dart:159
--   tvde_pos_ao_vivo_enabled                       com sessão  rpc    lib/services/driver_live_feed.dart:158
--   tvde_pos_ao_vivo_intervalo_s                   com sessão  rpc    lib/services/driver_live_feed.dart:159
--   tvde_reservation_dest_change_enabled           com sessão  rpc    lib/stores/tvde_store.dart:1147
--   tvde_reservation_enabled                       com sessão  rpc    lib/stores/tvde_store.dart:761
--   tvde_reservation_free_cancel_hours             com sessão  rpc    lib/stores/tvde_store.dart:748
--   tvde_reservation_max_advance_days              com sessão  rpc    lib/stores/tvde_store.dart:747
--   tvde_reservation_min_advance_minutes           com sessão  rpc    lib/stores/tvde_store.dart:746
--   tvde_reservation_payment_timeout_minutes       com sessão  rpc    lib/stores/tvde_store.dart:749
--   tvde_ride_gps_interval_seconds                 com sessão  rpc    lib/screens/driver/tvde/tvde_ride_active_screen.dart:692 (+1)
--   tvde_roundtrip_reservation_enabled             com sessão  rpc    lib/stores/tvde_store.dart:916
--   tvde_stop_fee_cents                            com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:349
--   tvde_stop_timer_seconds                        com sessão  rpc    lib/screens/client/tvde/tvde_ride_tracking_screen.dart:350 (+1)
--   visitantes_sem_conta                           SEM sessão  rpc    lib/auth/auth_store.dart:675
--   wallet_split_free_pct                          com sessão  rpc    lib/widgets/refund_choice_dialog.dart:82
--   web_card_payments_enabled                      com sessão  tabela lib/services/payment_service.dart:30
--   limpeza_guia_%  (6 chaves: standard, profunda, pos_obras, levar_produtos_profissional,
--                    levar_produtos_cliente, equipamento)   com sessão  tabela  lib/widgets/guia_limpeza.dart:34
--
-- LIDAS PELA APP E SECRETAS (as únicas duas; ficam só para dono de loja e admin pela política do passo 3):
--   partner_hidden_markup_pct       com sessão (parceiro)  tabela  lib/services/partner_price_rules.dart:44 (lido em :99)
--   partner_visible_commission_pct  com sessão (parceiro)  tabela  lib/services/partner_price_rules.dart:43 (lido em :99)
--   chamador: lib/screens/add_product_screen.dart:136 (parceiro) e, como admin,
--             lib/screens/admin/admin_product_prices_dialog.dart:99 e admin_product_weight_dialog.dart:87.
--
-- FALSOS POSITIVOS DO VARRIMENTO (não são desta tabela): priority_5min_cost, priority_10min_cost,
--   priority_15min_cost, priority_1hour_cost -> vêm de token_config (lib/screens/ganhos_screen.dart:188);
--   tvde_reservation_dest_change_enabled ainda não existe na base (a app usa false por recurso) — fica
--   na lista para o dia em que for criada.
--
-- AS 46 SECRETAS RESTANTES: nenhuma é LIDA por lib/ fora do painel admin (varrimento por nome: só 2
--   menções em comentários, 0 leituras). O painel admin lê-as como admin (política: is_admin()).
--
-- LEITORES NO SERVIDOR (confirmados, não mudam): Edge Functions leem com a chave de serviço (RLS não se
--   aplica): create-mbway-payment-intent, charge-tip, client-cancel-order, cancel-order-with-choice,
--   execute-cancellation, client-assistant, decidir, robot-b, tvde-plan-payment, agentes-email-*; o
--   admin-ai-assistant lê como admin. pg_cron corre como postgres (RLS não se aplica; get_setting sem
--   claims, session_user postgres -> valor).


-- ---------------------------------------------------------------------------------------------------
-- PLANO DE PROVA DEPOIS DE APLICAR — nas 3 plataformas (Android, iPhone, web)
-- ---------------------------------------------------------------------------------------------------
-- A. Na base (antes de abrir qualquer app) — correr, como o líder, e guardar a saída:
--    1) S1_prova_precos_antes_depois.sql  -> os dois md5 têm de ser IGUAIS aos de hoje
--         parceira      2a3fb771b124c53c98687c9dfca3af1e   (total 17,25 · taxa 0,69 · entrega 2,50)
--         não parceira  2eccb40e207bcfa8625306ece211000f   (total 14,99 · taxa 0,99 · entrega 2,50)
--       e a linha "partilha do parceiro sobre 100: ... cliente=85.71" (igual a hoje).
--    2) S1_prova_rollback.sql ajustado ao estado novo: cliente 0 secretas, parceiro 2, admin 48.
--    3) HTTP real com a chave pública do bundle (sem login):  rpc/get_setting de uma chave secreta ->
--       "null"; GET /rest/v1/platform_settings -> []; GET /rest/v1/platform_settings_publicas ->
--       87 linhas; GET /rest/v1/ nas 3 tabelas bkp_ do passo 0 (lista no AUDITORIA, achado ALTA-5) -> 401/vazio.
--    4) get_advisors(security): "rls_disabled_in_public" passa de 3 para 0.
-- B. Com conta normal (cliente de teste) em cada plataforma — o que tem de abrir e as chaves a confirmar:
--    · Arranque sem login (web https://app.boraguarda.com, iPhone, Android): ecrã inicial abre; logótipos
--      das lojas não-parceiras ao estilo certo no iPhone (ios_hide_nonpartner_logos); assistente aparece
--      ou não conforme assistant_enabled; aviso de atualização igual (app_latest_version_code*).
--    · Home -> loja parceira -> produto -> carrinho: total do carrinho IGUAL ao baseline (17,25 e 14,99
--      nas duas lojas da prova); "taxa de pedido pequeno" (min_order_cents, small_order_fee_*) e
--      "taxa de serviço" (non_partner_service_fee_*, riscada) visíveis ANTES de entrar (sem sessão) e
--      depois; "calculada no fim" só quando o servidor não responde, nunca valor de recurso.
--    · Entrega: taxa e horário da loja (carrinho/entrega), limite de dinheiro 40 € (max_cash_amount_cents),
--      gorjetas (tips_enabled), edição do pedido (order_edit_enabled), tempo da folha de cartão
--      (payment_sheet_timeout_seconds), cartão no web (web_card_payments_enabled), MB Way.
--    · Check-in diário, Receita do Dia, favores (errand_*, favor_pellets_max_sacos), limpeza (cleaning_*,
--      guia de limpeza com os 6 textos limpeza_guia_*), lavagem (carwash_*), reservas/TVDE (tvde_*).
--    · Pagamento: percentagem de tokens (token_payment_max_pct, token_balance_max_use_pct,
--      token_value_cents_x100) e divisão do reembolso (wallet_split_free_pct) iguais.
--    · Estafeta: oferta com o tempo certo (dispatch_offer_timeout_seconds), mapa (map_route_line_width),
--      posição ao vivo (tvde_pos_ao_vivo_*, client_live_location_*).
--    · Parceiro: "novo produto" calcula "Recebes" / "O cliente vê" (lê as 2 percentagens secretas — é o
--      único ecrã que depende da exceção do passo 3). Se abrir vazio/erro: reverter só a política.
--    · Painel admin (PT-BR): Definições da plataforma abre e mostra as 463 chaves (is_admin()).
-- C. Critério de reverter: qualquer divergência nos dois md5, ou o ecrã "novo produto" do parceiro sem
--    percentagens, ou um ecrã de arranque em branco -> bloco REVERTER; depois investigar.

