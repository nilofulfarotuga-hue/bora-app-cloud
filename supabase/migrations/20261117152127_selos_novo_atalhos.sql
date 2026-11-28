-- 17/11/2026 Claude.ai (pedido do Danilo: "pôr as novidades nos cantinhos que coloca novidade").
-- JÁ APLICADA em produção por MCP (migração selos_novo_atalhos_17_11). Fica aqui para o repo ter o mesmo.
-- Selo "Novo" no canto de qualquer atalho da página inicial: chave do atalho -> último dia (AAAA-MM-DD, Lisboa).
-- A app lê por get_setting (lib/utils/selos_novo.dart); o painel (Faixas da home) muda por admin_update_setting.
-- Começa com a Farmácia, 14 dias.
insert into public.platform_settings (key, value, description, category, is_secret, updated_at)
values ('selos_novo', '{"farmacia": "2026-12-01"}'::jsonb,
        'Selo "Novo" nos atalhos da página inicial: {"chave do atalho": "último dia AAAA-MM-DD (hora de Lisboa)"}. Painel > Faixas da home.',
        'home', false, now())
on conflict (key) do nothing;
