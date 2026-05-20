-- ═══════════════════════════════════════════════════════════════════════════
-- BUG-CHAT-02 residual — Backfill conversation_type para mensagens legacy.
--
-- 16 das 19 mensagens existentes têm conversation_type=NULL. O filtro do
-- chat_screen.dart aceita NULL em qualquer canal (fallback de compatibilidade)
-- → mensagens NULL aparecem em todos os canais (mistura visual).
--
-- Heurística de backfill por sender_type (correta para o histórico real):
--   sender_type='partner' → conversation_type='client_partner'
--     (parceiros só falavam com clientes nesta fase — não havia driver_partner
--      em produção antes desta sessão).
--   sender_type IN ('client','driver') → conversation_type='client_driver'
--     (canal mais usado durante delivery, onde a maioria das mensagens vivia).
--
-- Idempotente: WHERE conversation_type IS NULL — re-execuções não tocam em
-- nada já preenchido.
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.messages
   SET conversation_type = 'client_partner'
 WHERE conversation_type IS NULL
   AND sender_type = 'partner';

UPDATE public.messages
   SET conversation_type = 'client_driver'
 WHERE conversation_type IS NULL
   AND sender_type IN ('client', 'driver');
