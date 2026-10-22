-- Revisão B, ronda 1 (20/10/2026): o máximo de sacos de pellets por Favor
-- passa a ser configurável no painel admin (Configurações, categoria errand),
-- com a auditoria de admin_update_setting. Chave OPERACIONAL: um limite de
-- quantidade que a app impõe ao cliente; não mexe em nenhum valor cobrado.
-- A app usa 2 quando não consegue ler o valor.
insert into public.platform_settings (key, value, description, category)
values ('favor_pellets_max_sacos', '2'::jsonb,
        'Favores: máximo de sacos de pellets por Favor (o estafeta vai de mota). A app avisa e não deixa seguir acima disto. Padrão 2.',
        'errand')
on conflict (key) do nothing;
