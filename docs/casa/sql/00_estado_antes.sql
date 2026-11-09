-- PUBLICAÇÃO 2 da Casa — passo 0: fotografia do estado ANTES (só leitura; pode correr com --read-only).
-- Esperado a 09/11/2026 ~07:30 Lisboa: casa_enabled=false, valores autorizados=true, casa_novo_ate inexistente,
-- profissional do Danilo 'pending' com montagem+fixacao, sem faixa da Casa, sem difusão da Casa.
select 'casa_enabled' as item, (select value::text from public.platform_settings where key = 'casa_enabled') as valor
union all
select 'valores_autorizados', (select (value ->> 'autorizado') from public.platform_settings where key = 'casa_valores_autorizados')
union all
select 'casa_novo_ate', coalesce((select value::text from public.platform_settings where key = 'casa_novo_ate'), '(não existe)')
union all
select 'max_cash_amount_cents', (select value::text from public.platform_settings where key = 'max_cash_amount_cents')
union all
select 'profissional_danilo', (select approval_status || ' | sem_comissao_ate=' || coalesce(sem_comissao_ate::text, '-')
                                 from public.casa_profissionais where id = 'ad8e790d-7519-4366-9565-257f816babd1')
union all
select 'oficios_danilo', (select string_agg(oficio || '=' || estado || (case when ligado then '+' else '-' end), ', ' order by oficio)
                            from public.casa_profissional_oficios where profissional_id = 'ad8e790d-7519-4366-9565-257f816babd1')
union all
select 'aparelhos_danilo_pro', (select string_agg(role || ':' || platform, ', ') from public.provider_push_tokens
                                 where user_id = '503a2e09-2111-44b5-9852-d6d5897467f1' and active)
union all
select 'faixa_casa', coalesce((select string_agg(titulo || ' ativo=' || ativo, '; ') from public.home_banners
                                 where tipo_destino = 'categoria' and destino = 'casa'), '(nenhuma)')
union all
select 'difusao_casa', coalesce((select string_agg(status || ' ' || created_at::date, '; ') from public.push_broadcasts
                                   where title ilike '%Casa & Manuten%'), '(nenhuma)')
union all
select 'migracao_selo', coalesce((select version from supabase_migrations.schema_migrations where version = '20261109074000'), '(por aplicar)')
union all
select 'publico_da_difusao', (select count(*)::text from public.users u
                               where u.role = 'client' and u.marketing_opt_in
                                 and exists (select 1 from auth.users au where au.id = u.id));
