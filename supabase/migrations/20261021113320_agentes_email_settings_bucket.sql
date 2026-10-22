insert into public.platform_settings (key, value, description, category)
values
 ('agentes_email_ativo', 'true'::jsonb, 'Liga/desliga a caixa de e-mail dos agentes (agente@boraguarda.com)', 'agentes'),
 ('agentes_email_limite_dia', '80'::jsonb, 'Máximo de e-mails enviados por dia pelos agentes (Resend grátis aguenta 100/dia)', 'agentes'),
 ('agentes_email_nome_remetente', '"Bora App"'::jsonb, 'Nome que aparece como remetente nos e-mails dos agentes', 'agentes')
on conflict (key) do nothing;

insert into storage.buckets (id, name, public, file_size_limit)
values ('agentes-email', 'agentes-email', false, 10485760)
on conflict (id) do nothing;