# Proposta — `admin_listar_gorjetas` com a taxa da Stripe (missão gorjetas-taxa-2026-10-30, Bloco E)

A bora-tranca recusou escrever isto como migração em
`supabase/migrations/20261030151000_admin_listar_gorjetas_taxa.sql` (30/10/2026,
"migration que toca tokens/wallet/pagamentos/ledger"). Não se contornou: fica aqui
pronto, igual ao que ia para a migração.

⚠️ ISTO MEXE EM DINHEIRO (só leitura no painel) — está tudo pronto. Para aplicar:
copiar o bloco SQL abaixo, sem mudanças, para
`supabase/migrations/20261030151000_admin_listar_gorjetas_taxa.sql` e aplicar
DEPOIS da migração do servidor que cria `tips.cobrada_junto`.

O que faz: a função passa a devolver, além das 18 colunas de hoje (iguais e na
mesma ordem), `liquido_prestador_cents`, `cobrada_junto`, `como_foi_paga`,
`quem_pagou_taxa`, `taxa_descontada_prestador_cents` e `taxa_por_ler`. Só lê,
não escreve em nenhuma tabela. Mantém o controlo de admin de hoje
(`is_admin()` → `so_admin`, 42501).

Permissões lidas em produção a 30/10/2026 antes da mudança:
`proacl = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
(dono postgres; sem PUBLIC, sem anon). O SQL repõe exatamente estas e verifica-as
no fim com `has_function_privilege`.

O ecrã `lib/screens/admin/admin_gorjetas_screen.dart` já funciona com a função
antiga (calcula o mesmo na app quando as colunas novas não vêm) e passa a usar as
colunas do servidor assim que isto for aplicado.

```sql
-- =============================================================================
-- Gorjetas — painel admin com a taxa da Stripe e o líquido para o prestador
-- Missão gorjetas-taxa-2026-10-30 · Bloco E (painel admin)
-- =============================================================================
-- A regra do Danilo (30/10/2026):
--   1. Gorjeta no carrinho com cartão/MB Way → vai no MESMO pagamento da compra:
--      não há taxa à parte, vai INTEIRA para o prestador.
--   2. Gorjeta paga depois (avaliação da entrega ou da corrida) com cartão/MB Way
--      → pagamento à parte: o prestador recebe a gorjeta MENOS a taxa exata da
--      Stripe desse pagamento (ex.: 2,00 € − 0,28 € = 1,72 €).
--   3. Dinheiro → inteira.
--   4. A Bora não ganha nada em cima de gorjeta; pedido cancelado → a gorjeta
--      volta inteira ao cliente.
--
-- O que muda aqui: `admin_listar_gorjetas` passa a devolver também
--   liquido_prestador_cents          o que o prestador recebe (coluna gerada de tips)
--   cobrada_junto                    true = cobrada no mesmo pagamento da compra
--   como_foi_paga                    'dinheiro' | 'junto_da_compra' | 'a_parte_no_carrinho' | 'depois'
--   quem_pagou_taxa                  'prestador' | 'bora' | 'nenhuma'
--   taxa_descontada_prestador_cents  valor − líquido (só > 0 quando paga depois)
--   taxa_por_ler                     há taxa à parte mas ainda não veio da Stripe
--                                    (o líquido usa a estimativa 25 cêntimos + 1,5 %)
-- As 18 colunas de antes ficam iguais e na mesma ordem (o ecrã atual continua a ler).
-- Muda o RETURNS TABLE → DROP + CREATE (o CREATE OR REPLACE não o deixa mudar).
-- A definição anterior está em 20261004100000_gorjetas.sql (secção 5).
--
-- Depende de:
--   • tips.liquido_prestador_cents — migração `gorjeta_paga_depois_desconta_taxa_stripe_2026_10_30`
--     (já em produção desde 30/10 ~13:55);
--   • tips.cobrada_junto — criada pela migração do servidor desta mesma missão.
--   Se faltar alguma, a migração pára logo no início (nada é apagado).
--
-- Permissões lidas em produção a 30/10/2026, ANTES da mudança:
--   proacl = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   (sem PUBLIC e sem anon; dono postgres). Repostas exatamente no fim e
--   verificadas por has_function_privilege.
-- Controlo de admin igual ao de hoje: IF NOT public.is_admin() → 'so_admin' (42501).
-- Só leitura: não escreve em nenhuma tabela.
-- =============================================================================

DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'tips'
                    AND column_name = 'liquido_prestador_cents') THEN
    RAISE EXCEPTION 'falta a coluna tips.liquido_prestador_cents — aplicar primeiro gorjeta_paga_depois_desconta_taxa_stripe_2026_10_30';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'tips'
                    AND column_name = 'cobrada_junto') THEN
    RAISE EXCEPTION 'falta a coluna tips.cobrada_junto — aplicar primeiro a migração do servidor da missão gorjetas-taxa-2026-10-30';
  END IF;
END $pre$;

DROP FUNCTION IF EXISTS public.admin_listar_gorjetas(timestamptz, timestamptz);

CREATE FUNCTION public.admin_listar_gorjetas(
  p_desde timestamptz DEFAULT now() - interval '90 days',
  p_ate   timestamptz DEFAULT now())
RETURNS TABLE (
  id uuid, criada_em timestamptz, paga_em timestamptz, alvo text, pedido text, corrida uuid,
  cliente_id uuid, cliente_nome text, prestador_id uuid, prestador_nome text,
  valor_cents integer, metodo text, momento text, estado text,
  stripe_pi text, taxa_stripe_cents integer, reembolsada_em timestamptz, motivo_reembolso text,
  liquido_prestador_cents integer,
  cobrada_junto boolean,
  como_foi_paga text,
  quem_pagou_taxa text,
  taxa_descontada_prestador_cents integer,
  taxa_por_ler boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT t.id, t.created_at, t.paid_at, t.target, t.order_id, t.tvde_ride_id,
         t.client_user_id, COALESCE(uc.name, uc.email, ''),
         t.provider_user_id, COALESCE(d.name, up.name, up.email, ''),
         t.amount_cents, t.method, t.moment, t.status,
         t.stripe_payment_intent_id, t.stripe_fee_cents, t.refunded_at, t.refund_reason,
         t.liquido_prestador_cents,
         COALESCE(t.cobrada_junto, false),
         c.como,
         CASE c.como
           WHEN 'depois' THEN 'prestador'
           WHEN 'a_parte_no_carrinho' THEN 'bora'
           ELSE 'nenhuma'
         END,
         (t.amount_cents - t.liquido_prestador_cents),
         (c.como IN ('depois', 'a_parte_no_carrinho') AND t.stripe_fee_cents IS NULL)
    FROM public.tips t
    CROSS JOIN LATERAL (
      SELECT CASE
               WHEN t.method = 'cash' THEN 'dinheiro'
               WHEN COALESCE(t.cobrada_junto, false) THEN 'junto_da_compra'
               WHEN t.moment = 'checkout' THEN 'a_parte_no_carrinho'
               ELSE 'depois'
             END AS como
    ) c
    LEFT JOIN public.users uc ON uc.id = t.client_user_id
    LEFT JOIN public.users up ON up.id = t.provider_user_id
    LEFT JOIN public.drivers d ON d.user_id = t.provider_user_id
   WHERE t.created_at BETWEEN p_desde AND p_ate
   ORDER BY t.created_at DESC;
END $f$;

-- Permissões: exatamente as de antes (postgres dono, authenticated e service_role).
REVOKE ALL ON FUNCTION public.admin_listar_gorjetas(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_listar_gorjetas(timestamptz, timestamptz) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_listar_gorjetas(timestamptz, timestamptz) IS
  'Painel admin (Gorjetas). Só admin. Valor, taxa da Stripe, líquido para o prestador, '
  'quem pagou a taxa e como foi paga (regra de 30/10/2026: carrinho junto da compra = inteira; '
  'paga depois com cartão/MB Way = menos a taxa exata da Stripe; dinheiro = inteira).';

DO $pos$
BEGIN
  IF has_function_privilege('anon', 'public.admin_listar_gorjetas(timestamptz, timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'admin_listar_gorjetas ficou aberta a anon — não pode';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.admin_listar_gorjetas(timestamptz, timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.admin_listar_gorjetas(timestamptz, timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'admin_listar_gorjetas perdeu a permissão de authenticated ou service_role';
  END IF;
END $pos$;

NOTIFY pgrst, 'reload schema';
```

## Prova antes de aplicar (já feita, 30/10)

- Leitura em produção (só SELECT): `pg_get_functiondef` da função atual,
  `information_schema.routine_privileges` (authenticated EXECUTE, postgres EXECUTE
  com grant option, service_role EXECUTE) e o `proacl` acima.
- `tips` em produção tem 2 linhas: 51d1b251 (TVDE, depois, MB Way, 200, taxa 28,
  líquido 172) → `como_foi_paga = depois`, `quem_pagou_taxa = prestador`,
  `taxa_descontada_prestador_cents = 28`; 00fdbbe3 (pedido, checkout, dinheiro,
  cancelada) → `dinheiro`, `nenhuma`, 0.

## Depois de aplicar — conferir por SELECT

```sql
select p.proacl::text from pg_proc p where p.proname = 'admin_listar_gorjetas';
-- esperado: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
```
