-- 2026-09-07 — a lavagem auto so admitia 'pending', 'paid' e 'cancelled'.
-- Quando o lavador FICA A DEVER a Bora (recebeu dinheiro do cliente em mao), o
-- estado certo e 'recebido', nao 'pago' — sao coisas opostas e trocá-las faz o
-- painel mentir sobre quem deve a quem. As outras verticais ja aceitavam.
-- Alteracao aditiva: passa a admitir mais um estado, nao retira nenhum.

ALTER TABLE public.washer_weekly_settlements
  DROP CONSTRAINT IF EXISTS washer_weekly_settlements_status_check;

ALTER TABLE public.washer_weekly_settlements
  ADD CONSTRAINT washer_weekly_settlements_status_check
  CHECK (status = ANY (ARRAY['pending'::text, 'paid'::text, 'received'::text, 'cancelled'::text, 'disputed'::text]));;
