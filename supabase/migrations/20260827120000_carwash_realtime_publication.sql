-- =====================================================================
-- CARWASH — publicacao de realtime  |  2026-08-27
--
-- BUG APANHADO NO TESTE NO APARELHO (e so la):
-- o lavador aceitava a lavagem, o servidor gravava `accepted` com ETA, e o
-- ecra do cliente continuava em "A procura de lavador". Nada no codigo Dart
-- estava errado — a subscricao existia e o filtro estava certo.
--
-- CAUSA: as tabelas novas nunca foram acrescentadas a publicacao
-- `supabase_realtime`, por isso o Postgres NAO emitia um unico evento.
-- `cleaning_bookings`, `cleaning_messages` e `orders` ja la estavam desde
-- que foram criadas; estas nasceram de fora.
--
-- SEM ISTO: o cliente nao ve os estados mudarem, o lavador nao recebe as
-- ofertas ao vivo, e o chat nao entrega mensagens.
--
-- NOTA para quem vier a seguir: toda a tabela nova que a app acompanhe em
-- tempo real tem de ser acrescentada aqui. Criar a tabela e subscrever no
-- Dart NAO chega.
-- =====================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.carwash_bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE public.carwash_messages;
