-- Ronda 04/10 BLOCO C (05/10/2026, Danilo autorizou): funções SECURITY DEFINER do schema public
-- deixam de poder ser chamadas sem sessão (anon), exceto a lista branca (app antes do login, páginas
-- públicas, robôs que validam por segredo, is_admin das políticas RLS) e 16 funções em dúvida que
-- ficam abertas até um teste de arranque a frio (Android + web) e ver a VPS.
-- Quem tem sessão (authenticated) e o service_role mantêm o acesso que tinham.
-- Resultado lido de volta: 169 fechadas (lista em bkp_anon_execute_20261005), 44 abertas, as 20 RPC
-- mais usadas pela app continuam com EXECUTE para authenticated.
-- Voltar atrás: para cada linha de bkp_anon_execute_20261005, "grant execute on function <funcao> to anon".

create table if not exists public.bkp_anon_execute_20261005 (
  funcao text primary key,
  fechada_em timestamptz not null default now()
);
alter table public.bkp_anon_execute_20261005 enable row level security;
revoke all on table public.bkp_anon_execute_20261005 from public, anon, authenticated;

do $$
declare
  r record;
  v_lista text[] := array[
    -- lista branca (28)
    'is_admin','prospect_registar','prospects_ler','prospect_amostra_registar','prospect_proposta_registar',
    'prospect_contacto_registar','secretario_prospect_registar','carteiro_fila','carteiro_ligar','carteiro_marcar',
    'carteiro_registo','carteiro_resumo_dia','carteiro_threads','redator_fila','decidir_sombra',
    'radar_videos_registar','radar_videos_ler','radar_pesquisas_do_tema','radar_pesquisas_do_dia',
    'playbook_redes_registar','driver_heartbeat_segredo','tvde_ver_partilha','tvde_fiscal_consulta',
    'verificar_ficha_publica','registar_visita_baixar','get_setting','log_client_crash','driver_heartbeat_by_id',
    -- dúvidas (16) — ficam abertas por agora
    'is_partner_open','get_restaurant_ratings_summary','get_driver_ratings_summary','search_businesses',
    'carwash_quote','quote_order_pricing','get_available_slots','client_search_availability',
    'tvde_calculate_fare','tvde_quote_roundtrip','tvde_plan_price_cents','tvde_conformidade_config',
    'tvde_operador_plataforma','contadores_redes','visitas_por_origem','visitas_pessoas_e_robos'];
begin
  for r in
    select p.oid::regprocedure as f
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosecdef
       and has_function_privilege('anon', p.oid, 'execute')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and p.proname <> all (v_lista)
  loop
    execute format('revoke execute on function %s from public, anon', r.f);
    execute format('grant execute on function %s to authenticated, service_role', r.f);
    insert into public.bkp_anon_execute_20261005 (funcao) values (r.f::text) on conflict do nothing;
  end loop;

  -- C.1: só o servidor (Edge com service_role / outras funções) chama estas — fecham também a quem tem sessão
  for r in
    select p.oid::regprocedure as f from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_admin_urgent_push','tvde_reservation_push','aceita_papel')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
    execute format('grant execute on function %s to service_role', r.f);
  end loop;
end $$;

-- C.1: funções de admin que não verificavam quem chama — passam a devolver vazio a quem não é admin
CREATE OR REPLACE FUNCTION public.admin_estado_imagens_catalogo()
 RETURNS TABLE(restaurant_id text, loja_nome text, total bigint, no_storage bigint, fora_do_storage bigint, sem_foto bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.restaurant_id,
         r.name,
         count(*),
         count(*) FILTER (WHERE p.photo_url LIKE '%supabase.co/storage%'),
         count(*) FILTER (WHERE p.photo_url IS NOT NULL
                            AND p.photo_url NOT LIKE '%supabase.co/storage%'),
         count(*) FILTER (WHERE p.photo_url IS NULL OR p.photo_url = '')
    FROM public.products p
    JOIN public.restaurants r ON r.id = p.restaurant_id
   WHERE COALESCE(r.is_partner, false) = false
     AND public.is_admin()
   GROUP BY p.restaurant_id, r.name
   HAVING count(*) > 0
   ORDER BY count(*) FILTER (WHERE p.photo_url IS NOT NULL
                               AND p.photo_url NOT LIKE '%supabase.co/storage%') DESC,
            count(*) FILTER (WHERE p.photo_url IS NULL OR p.photo_url = '') DESC,
            r.name;
$function$;

CREATE OR REPLACE FUNCTION public.admin_fontes_de_preco(p_restaurant_id text DEFAULT NULL::text)
 RETURNS TABLE(product_id text, restaurant_id text, loja_nome text, produto text, categoria text, nosso_base numeric, balcao numeric, glovo numeric, ubereats numeric, acima_do_balcao boolean, delta numeric, confianca numeric, duvidoso boolean, apanhado_em timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.id, p.restaurant_id, r.name, p.name, p.category, p.price,
         b.preco, g.preco, u.preco,
         (b.preco IS NOT NULL AND p.price > b.preco),
         CASE WHEN b.preco IS NOT NULL THEN round(b.preco - p.price, 2) END,
         COALESCE(b.confianca, g.confianca, u.confianca),
         COALESCE(b.duvidoso, g.duvidoso, u.duvidoso, false),
         GREATEST(b.apanhado_em, g.apanhado_em, u.apanhado_em)
    FROM public.products p
    JOIN public.restaurants r ON r.id = p.restaurant_id
    LEFT JOIN public.product_price_sources b
      ON b.product_id = p.id AND b.fonte = 'balcao_oficial'
    LEFT JOIN public.product_price_sources g
      ON g.product_id = p.id AND g.fonte = 'glovo'
    LEFT JOIN public.product_price_sources u
      ON u.product_id = p.id AND u.fonte = 'ubereats'
   WHERE COALESCE(r.is_partner, false) = false
     AND public.is_admin()
     AND (p_restaurant_id IS NULL OR p.restaurant_id = p_restaurant_id)
     AND (b.preco IS NOT NULL OR g.preco IS NOT NULL OR u.preco IS NOT NULL)
   ORDER BY (b.preco IS NOT NULL AND p.price > b.preco) DESC,
            (b.preco - p.price) DESC NULLS LAST,
            p.name;
$function$;

-- C.2: funções novas no schema public nascem fechadas a anon (e a PUBLIC); authenticated/service_role
-- continuam a receber pelo privilégio por defeito do Supabase. Abrir a anon passa a ser um GRANT explícito.
-- (O privilégio global a PUBLIC tira-se na migração seguinte, 20261005092401.)
alter default privileges for role postgres in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
