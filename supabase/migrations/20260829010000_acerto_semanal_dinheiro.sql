-- ============================================================================
-- ACERTO SEMANAL — o dinheiro: ver, abater e marcar pago
--
-- A vista `v_acerto_semanal_unificado` ja existia e ja juntava os tres papeis
-- por pessoa e por semana. O que faltava era o resto: o ecra do prestador, o
-- painel do admin com cada pessoa UMA vez so, a divida abatida no mesmo numero,
-- e a exportacao.
--
-- ── NAO SE MEXE EM CALCULO NENHUM ──────────────────────────────────────────
-- Nenhuma formula de ganho, comissao ou taxa e tocada aqui. `net_balance`,
-- `net_payout_cents` e `bora_fee_cents` continuam a ser produzidos exactamente
-- pelas mesmas funcoes de sempre. Isto so JUNTA, MOSTRA e ABATE.
--
-- ── A ARMADILHA QUE A PROVA APANHOU, e que teria pago a dobrar ─────────────
-- Provado por SELECT nas 4 semanas reais de acerto de estafeta (2026-08-29):
--
--   semana      earnings  cash_recebido  divida  net_balance
--   2026-07-26     4,85       11,80        6,95     -6,95
--   2026-08-02    11,26       25,74        1,24     -0,53
--   2026-08-09     5,23       12,09        0,80     -0,80
--   2026-08-23     6,07       27,13        4,30     -4,30
--
-- Em todas, `net_balance` = **menos a divida**, exactamente. Ou seja: no
-- estafeta a divida JA ESTA ABATIDA dentro do net_balance (a formula e
-- `ganhos − dinheiro recebido em mao + reembolsos + tokens`). Abater outra vez
-- o `cash_adjustments_due` duplicava a divida de toda a gente.
--
-- Na limpeza e na lavagem e o contrario: `net_payout_cents = total_earnings`,
-- sem nada abatido. Quando o cliente paga em DINHEIRO, o prestador ficou com a
-- parte da Bora na mao e deve-a.
--
-- Por isso cada papel passa a dizer se a sua divida ja esta abatida ou nao, e
-- o total so desconta as que faltam. Um numero final, sem duplicar nenhum.
--
-- Nota honesta que fica registada: para uma limpeza/lavagem paga em dinheiro,
-- o `compute_*_weekly_settlement` conta os ganhos do prestador como se a Bora
-- lhos fosse pagar, quando ele ja os recebeu em mao. Isso e um defeito de
-- CALCULO, dentro de funcao que esta proibida de mexer nesta sessao. Fica no
-- relatorio como decisao de dinheiro para o Danilo. Hoje o efeito e zero:
-- `SELECT count(*) FROM cleaning_bookings WHERE payment_method='cash' AND
-- payment_status='cash_pending'` devolve 0, e o mesmo em carwash_bookings.
-- ============================================================================

-- ── 1. A vista, agora com a divida por papel e a marca de "ja abatida" ─────
DROP VIEW IF EXISTS public.v_acerto_semanal_unificado CASCADE;

CREATE VIEW public.v_acerto_semanal_unificado AS
WITH por_papel AS (
  -- ESTAFETA/MOTORISTA: euros na tabela → cents inteiros aqui. A divida
  -- (`cash_adjustments_due`) e informativa: ja esta dentro do net_balance.
  SELECT s.driver_id                                     AS user_id,
         date_trunc('week', s.week_start_at)::date       AS semana,
         'driver'::text                                  AS papel,
         s.total_deliveries                              AS trabalhos,
         round(s.net_balance * 100)::bigint              AS liquido_cents,
         round(COALESCE(s.cash_adjustments_due, 0) * 100)::bigint AS divida_cents,
         true                                            AS divida_ja_abatida,
         s.status                                        AS estado
  FROM public.driver_weekly_settlements s

  UNION ALL

  -- LIMPEZA: a tabela ja guarda cents. A identidade e `cleaners.user_id` — a
  -- juncao e pela PESSOA, nunca pelo id da linha do faxineiro.
  SELECT c.user_id,
         date_trunc('week', s.week_start_at)::date,
         'cleaner'::text,
         s.total_jobs,
         s.net_payout_cents::bigint,
         COALESCE((
           SELECT sum(b.bora_fee_cents)::bigint
           FROM public.cleaning_bookings b
           WHERE b.cleaner_id = s.cleaner_id
             AND b.payment_method = 'cash'
             AND b.payment_status = 'cash_pending'
             AND COALESCE(b.completed_at, b.scheduled_at) >= s.week_start_at
             AND COALESCE(b.completed_at, b.scheduled_at) <= s.week_end_at
         ), 0),
         false,
         s.status
  FROM public.cleaner_weekly_settlements s
  JOIN public.cleaners c ON c.id = s.cleaner_id

  UNION ALL

  -- LAVAGEM: igual a limpeza, identidade por `washers.user_id`.
  SELECT w.user_id,
         date_trunc('week', s.week_start_at)::date,
         'washer'::text,
         s.total_jobs,
         s.net_payout_cents::bigint,
         COALESCE((
           SELECT sum(b.bora_fee_cents)::bigint
           FROM public.carwash_bookings b
           WHERE b.washer_id = s.washer_id
             AND b.payment_method = 'cash'
             AND b.payment_status = 'cash_pending'
             AND COALESCE(b.completed_at, b.scheduled_at) >= s.week_start_at
             AND COALESCE(b.completed_at, b.scheduled_at) <= s.week_end_at
         ), 0),
         false,
         s.status
  FROM public.washer_weekly_settlements s
  JOIN public.washers w ON w.id = s.washer_id
)
SELECT p.user_id,
       p.semana,
       u.email,
       jsonb_object_agg(p.papel, jsonb_build_object(
         'trabalhos',     p.trabalhos,
         'liquido_cents', p.liquido_cents,
         'divida_cents',  p.divida_cents,
         'divida_ja_abatida', p.divida_ja_abatida,
         'estado',        p.estado)) AS detalhe,
       sum(p.trabalhos)                                     AS trabalhos_total,
       sum(GREATEST(p.liquido_cents, 0))                    AS a_receber_cents,
       sum(p.divida_cents)                                  AS divida_cents,
       -- A divida que ainda NAO foi abatida em lado nenhum. COALESCE porque um
       -- FILTER sem nenhuma linha a passar devolve NULL, e NULL num campo de
       -- dinheiro le-se no ecra como buraco, nao como zero.
       COALESCE(sum(p.divida_cents) FILTER (WHERE NOT p.divida_ja_abatida), 0)
                                                            AS divida_por_abater_cents,
       -- O NUMERO FINAL. Um so, com sinal: positivo a Bora paga, negativo a
       -- pessoa deve. So desconta a divida que ainda nao estava descontada.
       sum(p.liquido_cents)
         - COALESCE(sum(p.divida_cents) FILTER (WHERE NOT p.divida_ja_abatida), 0)
                                                            AS total_cents,
       CASE
         WHEN sum(p.liquido_cents)
              - COALESCE(sum(p.divida_cents) FILTER (WHERE NOT p.divida_ja_abatida), 0) > 0
           THEN 'bora_paga'
         WHEN sum(p.liquido_cents)
              - COALESCE(sum(p.divida_cents) FILTER (WHERE NOT p.divida_ja_abatida), 0) < 0
           THEN 'pessoa_deve'
         ELSE 'zero'
       END                                                  AS sentido,
       bool_and(p.estado IN ('paid', 'received'))           AS tudo_pago
FROM por_papel p
LEFT JOIN auth.users u ON u.id = p.user_id
GROUP BY p.user_id, p.semana, u.email;

COMMENT ON VIEW public.v_acerto_semanal_unificado IS
  'SO LEITURA. Junta os acertos semanais dos tres papeis por PESSOA. Nao '
  'calcula ganhos: le os que as funcoes compute_* ja produziram. A divida do '
  'estafeta ja vem abatida no net_balance (provado 2026-08-29); a da limpeza e '
  'da lavagem nao, e por isso e essa a unica que o total desconta.';

REVOKE ALL ON public.v_acerto_semanal_unificado FROM PUBLIC, anon, authenticated;


-- ── 2. O acerto da propria pessoa ──────────────────────────────────────────
-- DROP antes do CREATE: a assinatura de saida muda (entra
-- `divida_por_abater_cents`) e o Postgres nao deixa trocar o tipo de retorno
-- com CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.meu_acerto_semanal(integer);
CREATE OR REPLACE FUNCTION public.meu_acerto_semanal(p_semanas integer DEFAULT 8)
RETURNS TABLE(semana date, detalhe jsonb, trabalhos_total bigint,
              a_receber_cents bigint, divida_cents bigint,
              divida_por_abater_cents bigint, total_cents bigint,
              sentido text, tudo_pago boolean)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT v.semana, v.detalhe, v.trabalhos_total, v.a_receber_cents,
         v.divida_cents, v.divida_por_abater_cents, v.total_cents,
         v.sentido, v.tudo_pago
  FROM public.v_acerto_semanal_unificado v
  WHERE v.user_id = auth.uid()
  ORDER BY v.semana DESC
  LIMIT GREATEST(p_semanas, 1);
$function$;

REVOKE ALL ON FUNCTION public.meu_acerto_semanal(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.meu_acerto_semanal(integer) TO authenticated;


-- ── 3. O ganho de HOJE e da SEMANA, ao vivo ────────────────────────────────
-- O acerto semanal so existe depois de a semana fechar. Quem trabalha quer
-- saber quanto ganhou hoje. Isto SOMA colunas ja existentes — nao ha aqui
-- formula nenhuma nova.
CREATE OR REPLACE FUNCTION public.meu_ganho_ao_vivo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dia timestamptz;
  v_sem timestamptz;
  v_cleaner_id uuid;
  v_washer_id uuid;
  v_linhas jsonb := '[]'::jsonb;
  v_hoje bigint := 0;
  v_semana bigint := 0;
  h bigint; s bigint; nh int; ns int;
  v_driver jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  -- Fuso de Lisboa: "hoje" e o dia do prestador, nao o do servidor.
  v_dia := date_trunc('day',  now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_sem := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';

  -- ENTREGAS E CORRIDAS: reaproveita `driver_earnings_summary()`, que ja e a
  -- fonte usada pelo ecra do estafeta. Nao se copia a expressao para aqui —
  -- duas copias da mesma soma sao gemeos a espera de divergir.
  IF EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid) THEN
    v_driver := public.driver_earnings_summary();
    IF v_driver->>'ok' = 'true' THEN
      h := COALESCE((v_driver->'dia'->>'total_cents')::bigint, 0);
      s := COALESCE((v_driver->'semana'->>'total_cents')::bigint, 0);
      v_hoje := v_hoje + h;
      v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'driver', 'titulo', 'Entregas e corridas',
        'hoje_cents', h, 'semana_cents', s);
    END IF;
  END IF;

  -- LIMPEZA
  SELECT c.id INTO v_cleaner_id FROM public.cleaners c WHERE c.user_id = v_uid;
  IF v_cleaner_id IS NOT NULL THEN
    SELECT COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
           COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
           count(*) FILTER (WHERE b.completed_at >= v_dia),
           count(*) FILTER (WHERE b.completed_at >= v_sem)
      INTO h, s, nh, ns
      FROM public.cleaning_bookings b
     WHERE b.cleaner_id = v_cleaner_id AND b.status = 'completed'
       AND COALESCE(b.is_test_order, false) = false;
    v_hoje := v_hoje + h; v_semana := v_semana + s;
    v_linhas := v_linhas || jsonb_build_object(
      'papel', 'cleaner', 'titulo', 'Limpeza',
      'hoje_cents', h, 'semana_cents', s,
      'trabalhos_hoje', nh, 'trabalhos_semana', ns);
  END IF;

  -- LAVAGEM
  SELECT w.id INTO v_washer_id FROM public.washers w WHERE w.user_id = v_uid;
  IF v_washer_id IS NOT NULL THEN
    SELECT COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
           COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
           count(*) FILTER (WHERE b.completed_at >= v_dia),
           count(*) FILTER (WHERE b.completed_at >= v_sem)
      INTO h, s, nh, ns
      FROM public.carwash_bookings b
     WHERE b.washer_id = v_washer_id AND b.status = 'completed';
    v_hoje := v_hoje + h; v_semana := v_semana + s;
    v_linhas := v_linhas || jsonb_build_object(
      'papel', 'washer', 'titulo', 'Lavagem de carros',
      'hoje_cents', h, 'semana_cents', s,
      'trabalhos_hoje', nh, 'trabalhos_semana', ns);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'hoje_cents', v_hoje,
    'semana_cents', v_semana,
    'por_papel', v_linhas);
END $function$;

REVOKE ALL ON FUNCTION public.meu_ganho_ao_vivo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.meu_ganho_ao_vivo() TO authenticated;


-- ── 4. O painel do admin: cada pessoa UMA vez so ───────────────────────────
CREATE OR REPLACE FUNCTION public.admin_acerto_unificado(p_semana date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_semana date; v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  v_semana := COALESCE(p_semana,
    (SELECT max(v.semana) FROM public.v_acerto_semanal_unificado v));

  SELECT jsonb_build_object(
    'ok', true,
    'semana', v_semana,
    'semanas', COALESCE((SELECT jsonb_agg(DISTINCT x.semana ORDER BY x.semana DESC)
                         FROM public.v_acerto_semanal_unificado x), '[]'::jsonb),
    'itens', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', v.user_id,
        'email',   v.email,
        -- O nome que o Danilo le. Vem do papel mais completo que a pessoa
        -- tenha; nunca o uuid.
        'nome', COALESCE(
          (SELECT d.name FROM drivers  d WHERE d.user_id = v.user_id LIMIT 1),
          (SELECT c.name FROM cleaners c WHERE c.user_id = v.user_id LIMIT 1),
          (SELECT w.name FROM washers  w WHERE w.user_id = v.user_id LIMIT 1),
          v.email, '(sem nome)'),
        'telefone', COALESCE(
          (SELECT d.phone FROM drivers  d WHERE d.user_id = v.user_id LIMIT 1),
          (SELECT c.phone FROM cleaners c WHERE c.user_id = v.user_id LIMIT 1),
          (SELECT w.phone FROM washers  w WHERE w.user_id = v.user_id LIMIT 1), ''),
        'detalhe', v.detalhe,
        'trabalhos_total', v.trabalhos_total,
        'a_receber_cents', v.a_receber_cents,
        'divida_cents', v.divida_cents,
        'divida_por_abater_cents', v.divida_por_abater_cents,
        'total_cents', v.total_cents,
        'sentido', v.sentido,
        'tudo_pago', v.tudo_pago)
        ORDER BY v.total_cents DESC)
      FROM public.v_acerto_semanal_unificado v
      WHERE v.semana = v_semana), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $function$;

REVOKE ALL ON FUNCTION public.admin_acerto_unificado(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_acerto_unificado(date) TO authenticated;


-- ── 5. Marcar pago — a pessoa toda de uma vez ──────────────────────────────
-- Muda SO o estado. Nao mexe em valor nenhum: nem net_balance, nem
-- net_payout_cents, nem taxa. As tres instrucoes sao as MESMAS do
-- `admin_mark_settlement_paid`, que esta provado desde Agosto — a diferenca e
-- que aqui correm as tres juntas para a mesma pessoa, e que a lavagem entra
-- (aquela funcao nao a conhecia).
CREATE OR REPLACE FUNCTION public.admin_marcar_acerto_pago(
  p_user_id uuid,
  p_semana date,
  p_metodo text DEFAULT NULL,
  p_referencia text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid := auth.uid(); n_d int := 0; n_c int := 0; n_w int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF p_user_id IS NULL OR p_semana IS NULL THEN RAISE EXCEPTION 'faltam_argumentos'; END IF;

  UPDATE driver_weekly_settlements
     SET status = 'paid', paid_at = now(), paid_by = v_uid,
         payment_method = COALESCE(p_metodo, payment_method),
         payment_reference = COALESCE(p_referencia, payment_reference)
   WHERE driver_id = p_user_id
     AND date_trunc('week', week_start_at)::date = p_semana
     AND status NOT IN ('paid', 'received');
  GET DIAGNOSTICS n_d = ROW_COUNT;

  UPDATE cleaner_weekly_settlements s
     SET status = 'paid', paid_at = now(), paid_by = v_uid,
         payment_method = COALESCE(p_metodo, s.payment_method),
         payment_reference = COALESCE(p_referencia, s.payment_reference)
   WHERE s.cleaner_id IN (SELECT c.id FROM cleaners c WHERE c.user_id = p_user_id)
     AND date_trunc('week', s.week_start_at)::date = p_semana
     AND s.status NOT IN ('paid', 'received');
  GET DIAGNOSTICS n_c = ROW_COUNT;

  UPDATE washer_weekly_settlements s
     SET status = 'paid', paid_at = now(), paid_by = v_uid,
         payment_method = COALESCE(p_metodo, s.payment_method),
         payment_reference = COALESCE(p_referencia, s.payment_reference)
   WHERE s.washer_id IN (SELECT w.id FROM washers w WHERE w.user_id = p_user_id)
     AND date_trunc('week', s.week_start_at)::date = p_semana
     AND s.status NOT IN ('paid', 'received');
  GET DIAGNOSTICS n_w = ROW_COUNT;

  PERFORM public.log_admin_action('marcar_acerto_pago', 'pessoa', p_user_id::text,
    jsonb_build_object('semana', p_semana, 'driver', n_d, 'cleaner', n_c,
                       'washer', n_w, 'metodo', p_metodo,
                       'referencia', p_referencia));

  RETURN jsonb_build_object('ok', true, 'linhas', n_d + n_c + n_w,
    'driver', n_d, 'cleaner', n_c, 'washer', n_w);
END $function$;

REVOKE ALL ON FUNCTION public.admin_marcar_acerto_pago(uuid, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_marcar_acerto_pago(uuid, date, text, text) TO authenticated;
