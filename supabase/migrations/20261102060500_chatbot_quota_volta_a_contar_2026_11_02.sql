-- 02/11/2026 (missão chaves-varredura-2026-10-31, B3) — o limite diário de mensagens do robô de suporte
-- nunca travava. A support-chatbot chama increment_chatbot_quota() com a SESSÃO do cliente (a função usa
-- auth.uid() e só mexe no contador do próprio), mas o papel authenticated não tinha EXECUTE: 403 em cada
-- mensagem (log 31/10 11:52:17), o contador ficava a 0 e cada mensagem gastava o motor sem limite.
-- Provado a 02/11: sessão de conta de teste → 200 (contador 1); chave pública (anon) → continua recusada.
-- Aplicada em produção por execute_sql e registada à mão em supabase_migrations.schema_migrations.
grant execute on function public.increment_chatbot_quota() to authenticated;
