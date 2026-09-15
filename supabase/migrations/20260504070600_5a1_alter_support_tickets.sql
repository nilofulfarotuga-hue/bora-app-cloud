-- Sessão 5A-1 B7 — ALTER support_tickets aditivo
-- Preserva schema legacy (question NOT NULL, bot_answer, human_answer,
-- satisfaction, answered_at). Adiciona 9 colunas para tickets whatsapp/email
-- + chatbot session_id.

ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS order_id text REFERENCES public.orders(id),
  ADD COLUMN IF NOT EXISTS channel text,
  ADD COLUMN IF NOT EXISTS subject text,
  ADD COLUMN IF NOT EXISTS body text,
  ADD COLUMN IF NOT EXISTS assigned_to uuid,
  ADD COLUMN IF NOT EXISTS admin_notes text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS session_id uuid
    REFERENCES public.support_chatbot_sessions(id) ON DELETE SET NULL;

-- CHECK constraint canal idempotente
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='support_tickets_channel_check'
  ) THEN
    ALTER TABLE public.support_tickets
      ADD CONSTRAINT support_tickets_channel_check
      CHECK (channel IS NULL OR channel IN ('chatbot','whatsapp','email'));
  END IF;
END$$;

-- Mapeamento legacy ↔ novo (documentação inline)
COMMENT ON COLUMN public.support_tickets.question IS
  'Legacy + chatbot: pergunta original do user (NOT NULL). ' ||
  'Para tickets whatsapp/email novos, replicar subject+body aqui ' ||
  'para satisfazer NOT NULL.';
COMMENT ON COLUMN public.support_tickets.body IS
  'Novo (5A-1): corpo de ticket whatsapp/email. ' ||
  'NULL para tickets chatbot legacy.';
COMMENT ON COLUMN public.support_tickets.subject IS
  'Novo (5A-1): assunto de ticket whatsapp/email.';
COMMENT ON COLUMN public.support_tickets.channel IS
  'Novo (5A-1): chatbot/whatsapp/email. NULL para legacy não classificado.';

-- Backfill condicional (apenas onde temos sinal claro)
UPDATE public.support_tickets
SET channel = 'chatbot'
WHERE channel IS NULL AND bot_answer IS NOT NULL;
