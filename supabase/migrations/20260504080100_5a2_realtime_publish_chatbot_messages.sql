-- Sessão 5A-2 B11.5 — Realtime publication
-- Sem isto, SupportChatScreen B13 não recebe streaming de mensagens.
-- REPLICA IDENTITY default basta para INSERTs novos (RLS aplicada client-side).

ALTER PUBLICATION supabase_realtime
  ADD TABLE public.support_chatbot_messages;
