-- ============================================================================
-- ACERTO SEMANAL UNIFICADO — uma pessoa, uma conta, um número
--
-- Se a mesma pessoa fez corridas, entregas, uma faxina e uma lavagem na mesma
-- semana, tem de haver UM acerto, não quatro. Hoje há três tabelas separadas e
-- nada que as junte.
--
-- ⚠️ ESTA MIGRATION É SÓ DE LEITURA. Cria uma vista e uma função que LEEM e
-- somam o que já está calculado. Não escreve, não paga, não altera nenhum
-- valor. O botão de pagar e o abate efectivo da dívida ficam de fora de
-- propósito — isso mexe em dinheiro que sai para pessoas e espera ordem
-- expressa do Danilo.
--
-- ── DUAS ARMADILHAS QUE ISTO RESOLVE, e que ninguém deve voltar a pisar ────
--
-- 1. UNIDADES DIFERENTES. `driver_weekly_settlements` guarda EUROS em colunas
--    numeric (`net_balance` = -4.30). `cleaner_` e `washer_` guardam CÊNTIMOS
--    em integer (`net_payout_cents` = 430). Somar os dois campos directamente
--    dá um erro de cem vezes, e num acerto isso é a diferença entre pagar
--    quatro euros e pagar quatrocentos. Aqui converte-se TUDO para cêntimos
--    inteiros, que é a única unidade em que dinheiro se soma sem arredondar.
--
-- 2. CADA TABELA APONTA PARA UMA COISA DIFERENTE.
--       driver_weekly_settlements.driver_id  -> drivers.user_id  (a PESSOA)
--       cleaner_weekly_settlements.cleaner_id -> cleaners.id     (a LINHA)
--       washer_weekly_settlements.washer_id   -> washers.id      (a LINHA)
--    Juntar por id às cegas casava o acerto de um motorista com a linha de
--    outro faxineiro qualquer. A limpeza e a lavagem TÊM de passar pela sua
--    tabela para se chegar à pessoa.
--
-- ── SINAL ──────────────────────────────────────────────────────────────────
-- Positivo = a Bora paga à pessoa. Negativo = a pessoa deve à Bora.
-- No motorista o sinal já vem em `net_balance` (negativo quando ele recebeu
-- dinheiro em mão que é da Bora). Na limpeza e na lavagem `net_payout_cents`
-- é sempre o que a Bora paga, logo entra positivo.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_acerto_semanal_unificado AS
WITH por_papel AS (
  -- Motorista e entregas: já em euros, com sinal.
  SELECT
    s.driver_id                                   AS user_id,
    date_trunc('week', s.week_start_at)::date     AS semana,
    'driver'::text                                AS papel,
    s.total_deliveries                            AS trabalhos,
    round(s.net_balance * 100)::bigint            AS liquido_cents,
    round(COALESCE(s.cash_adjustments_due, 0) * 100)::bigint AS divida_cents,
    s.status                                      AS estado
  FROM public.driver_weekly_settlements s

  UNION ALL

  -- Limpeza: em cêntimos, e a pessoa chega-se pela tabela dos faxineiros.
  SELECT
    c.user_id,
    date_trunc('week', s.week_start_at)::date,
    'cleaner',
    s.total_jobs,
    s.net_payout_cents::bigint,
    0::bigint,
    s.status
  FROM public.cleaner_weekly_settlements s
  JOIN public.cleaners c ON c.id = s.cleaner_id

  UNION ALL

  -- Lavagem: igual à limpeza.
  SELECT
    w.user_id,
    date_trunc('week', s.week_start_at)::date,
    'washer',
    s.total_jobs,
    s.net_payout_cents::bigint,
    0::bigint,
    s.status
  FROM public.washer_weekly_settlements s
  JOIN public.washers w ON w.id = s.washer_id
)
SELECT
  p.user_id,
  p.semana,
  u.email,
  -- O detalhe por tipo de trabalho, para a pessoa perceber a conta.
  jsonb_object_agg(
    p.papel,
    jsonb_build_object(
      'trabalhos',     p.trabalhos,
      'liquido_cents', p.liquido_cents,
      'divida_cents',  p.divida_cents,
      'estado',        p.estado
    )
  )                                        AS detalhe,
  SUM(p.trabalhos)                         AS trabalhos_total,
  -- As duas parcelas, mostradas antes do total para a conta se perceber.
  SUM(GREATEST(p.liquido_cents, 0))        AS a_receber_cents,
  SUM(p.divida_cents)                      AS divida_cents,
  -- O número único: ou a Bora paga, ou a pessoa deve.
  SUM(p.liquido_cents)                     AS total_cents,
  CASE
    WHEN SUM(p.liquido_cents) > 0 THEN 'bora_paga'
    WHEN SUM(p.liquido_cents) < 0 THEN 'pessoa_deve'
    ELSE 'zero'
  END                                      AS sentido,
  -- Só se dá por fechada quando TODAS as parcelas estiverem fechadas.
  bool_and(p.estado IN ('paid', 'received')) AS tudo_pago
FROM por_papel p
LEFT JOIN auth.users u ON u.id = p.user_id
GROUP BY p.user_id, p.semana, u.email;

COMMENT ON VIEW public.v_acerto_semanal_unificado IS
  'Um acerto por PESSOA e semana, somando motorista, limpeza e lavagem. Tudo '
  'em centimos inteiros — as tabelas de origem misturam euros e centimos. '
  'Positivo = a Bora paga; negativo = a pessoa deve. So leitura.';


-- ── O que a própria pessoa vê ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.meu_acerto_semanal(p_semanas int DEFAULT 8)
RETURNS TABLE (
  semana          date,
  detalhe         jsonb,
  trabalhos_total bigint,
  a_receber_cents bigint,
  divida_cents    bigint,
  total_cents     bigint,
  sentido         text,
  tudo_pago       boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT v.semana, v.detalhe, v.trabalhos_total, v.a_receber_cents,
         v.divida_cents, v.total_cents, v.sentido, v.tudo_pago
  FROM public.v_acerto_semanal_unificado v
  WHERE v.user_id = auth.uid()
  ORDER BY v.semana DESC
  LIMIT GREATEST(p_semanas, 1);
$function$;

REVOKE ALL ON FUNCTION public.meu_acerto_semanal(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.meu_acerto_semanal(int) TO authenticated;

COMMENT ON FUNCTION public.meu_acerto_semanal(int) IS
  'O acerto da propria pessoa, uma linha por semana, com o detalhe por tipo '
  'de trabalho. So leitura.';
