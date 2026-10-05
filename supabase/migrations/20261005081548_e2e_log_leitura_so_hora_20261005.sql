-- 05/10 (segurança, Danilo autorizou): o e2e_log (registos internos de missões, com nomes, emails e
-- telemóveis) podia ser lido por inteiro por qualquer pessoa com a chave pública da app.
-- A app só ESCREVE nele; os dois vigias (heartbeat-browser.py, hermes-e2e-vigia.sh) só leem id e created_at.
-- Fica: escrever continua igual; ler sem chave de serviço só id e created_at. Agentes por MCP/serviço não mudam.
revoke select on public.e2e_log from anon, authenticated;
grant select (id, created_at) on public.e2e_log to anon, authenticated;
