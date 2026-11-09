-- PUBLICAÇÃO 2 da Casa — verificação final (só leitura; pode correr com --read-only).
-- Tudo o que a publicação gravou, lido de volta numa linha por item.
select 'casa_visivel_para_clientes' as item, (public.casa_config() ->> 'visivel') as valor
union all
select 'servicos_visiveis', jsonb_array_length(public.casa_config() -> 'servicos')::text
union all
select 'servicos_preco_fixo_ou_hora_com_material',
       (select count(*)::text from public.casa_servicos s join public.casa_oficios o on o.codigo = s.oficio and o.ativo
         where s.ativo and s.modo <> 'orcamento' and s.perguntas @> '[{"id":"material"}]')
       || ' de ' ||
       (select count(*)::text from public.casa_servicos s join public.casa_oficios o on o.codigo = s.oficio and o.ativo
         where s.ativo and s.modo <> 'orcamento')
union all
select 'selo_novo_ate', public.get_setting('casa_novo_ate')::text
union all
select 'profissional_danilo', (select approval_status from public.casa_profissionais
                                where id = 'ad8e790d-7519-4366-9565-257f816babd1')
union all
select 'oficios_danilo', (select string_agg(oficio || '=' || estado || (case when ligado then '+' else '-' end), ', ' order by oficio)
                            from public.casa_profissional_oficios where profissional_id = 'ad8e790d-7519-4366-9565-257f816babd1')
union all
select 'aparelho_handyman_danilo', coalesce((select string_agg(platform || ' ' || updated_at::date, ', ')
                                               from public.provider_push_tokens
                                              where user_id = '503a2e09-2111-44b5-9852-d6d5897467f1'
                                                and role = 'handyman' and active), '(nenhum: abrir a app como profissional da Casa)')
union all
select 'faixa_casa', coalesce((select string_agg(titulo || ' ativo=' || ativo || ' ate ' || coalesce(fim::date::text, '-'), '; ')
                                 from public.home_banners where tipo_destino = 'categoria' and destino = 'casa'), '(nenhuma)')
union all
select 'difusao_casa', coalesce((select string_agg(status || ' enviados=' || coalesce(sent_count, 0), '; ')
                                   from public.push_broadcasts where title = 'Novidade: Casa & Manutenção'), '(nenhuma)')
union all
select 'migracao_selo', coalesce((select version from supabase_migrations.schema_migrations where version = '20261109074000'), '(por aplicar)')
union all
select 'auditoria_hoje', (select count(*)::text from public.admin_audit_log
                           where created_at > now() - interval '1 day'
                             and (action like 'casa_%' or action in ('home_banner_criar', 'broadcast_notification')));
