-- PROPOSTA 2/2 — missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
-- Interruptor da conta Stripe para o que NÃO é TVDE. A tranca recusa platform_settings com
-- chave stripe_* nesta sessão. Aplicar pela Claude.ai (MCP, nome: stripe_conta_nao_tvde) e
-- copiar para supabase/migrations/20261102013100_stripe_conta_nao_tvde.sql.
--
-- Nasce em 'pessoal' (nada muda até as provas da F6 passarem). Passar a 'empresa' é um UPDATE
-- à parte, só depois das provas:  update platform_settings set value='"empresa"'::jsonb,
-- updated_at=now() where key='stripe_conta_nao_tvde';   Voltar a 'pessoal' faz tudo regressar
-- sem novo build (a app pergunta ao servidor qual a conta em cada pagamento).

insert into public.platform_settings (key, value, category, description, is_secret)
values (
  'stripe_conta_nao_tvde', '"pessoal"'::jsonb, 'stripe',
  'Conta Stripe para o que NÃO é TVDE (entregas, Favores, limpeza, lavagem, Casa, marcações, reservas de mesa, gorjetas de entregas, dívida, peso, extras): pessoal ou empresa. TVDE fica sempre na pessoal. Só vale para apps que enviam stripe_contas_v2=true; apps antigas ficam na pessoal.',
  false
)
on conflict (key) do nothing;

-- Prova: select key, value from platform_settings where key='stripe_conta_nao_tvde';
