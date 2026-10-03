-- ============================================================================
-- PROPOSTA — NAO APLICADA. MEXE EM DINHEIRO. Espera o "vai" do Danilo.
-- ============================================================================
-- BLOCO 4.2 da missao "fecho semanal automatico" (2026-09-07).
--
-- O QUE FAZ (padrao Uber / Glovo)
-- Quando alguem fecha a semana a dever a Bora e nao acerta, a divida NAO fica
-- esquecida numa semana antiga: entra no fecho seguinte como uma linha
-- "Saldo anterior em divida", e o acerto velho fica marcado `rolled_over` a
-- apontar para o novo. O valor conta UMA VEZ SO — e essa e a parte que tem de
-- ser conferida a mao antes de ligar isto.
--
-- PORQUE NAO FOI APLICADA
-- Isto ALTERA VALORES devidos a pessoas reais. Cai na Lista Vermelha do
-- CLAUDE.md ("migrations/UPDATE que alterem valores cobrados a clientes ou
-- pagos a estafetas/parceiros"). Preparou-se tudo; nao se aplica sozinho.
--
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Esta tudo pronto — confirma que eu aplico.
--
-- O interruptor `platform_settings.settlement_carry_over_enabled` JA EXISTE em
-- producao e esta em `false`. Mesmo depois de aplicar este ficheiro, nada
-- acontece ate esse interruptor ser ligado no painel (Acertos da semana →
-- Configurar). Sao dois passos de proposito.
--
-- COMO CONFERIR ANTES DE LIGAR (ordem sugerida)
--   1. Aplicar este ficheiro (cria colunas e funcao; nao corre nada).
--   2. Correr `select public.apply_settlement_carry_over('AAAA-MM-DD', true);`
--      — o `true` e o modo de ensaio: mostra o que faria e NAO grava.
--   3. Conferir a mao uma semana com divida real.
--   4. So entao ligar o interruptor no painel.
-- ============================================================================

-- 1) Onde fica registado o que foi transportado, para se poder auditar depois.
CREATE TABLE IF NOT EXISTS public.settlement_carry_over (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type   text NOT NULL,
  subject_id     text NOT NULL,
  from_week      date NOT NULL,
  to_week        date NOT NULL,
  cents          int  NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT settlement_carry_over_uniq UNIQUE (subject_type, subject_id, from_week)
);

-- 2) A marca no acerto novo, para o recibo poder mostrar a linha.
ALTER TABLE public.driver_weekly_settlements
  ADD COLUMN IF NOT EXISTS carried_over_cents int NOT NULL DEFAULT 0;
ALTER TABLE public.partner_weekly_settlements
  ADD COLUMN IF NOT EXISTS carried_over_cents int NOT NULL DEFAULT 0;
ALTER TABLE public.cleaner_weekly_settlements
  ADD COLUMN IF NOT EXISTS carried_over_cents int NOT NULL DEFAULT 0;
ALTER TABLE public.washer_weekly_settlements
  ADD COLUMN IF NOT EXISTS carried_over_cents int NOT NULL DEFAULT 0;

-- 3) A camada por cima. NAO altera nenhuma formula: as `compute_*` continuam
--    intactas e correm primeiro; isto so junta o que ficou por acertar.
CREATE OR REPLACE FUNCTION public.apply_settlement_carry_over(
  p_week_start date,
  p_ensaio boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ligado boolean := COALESCE((public.get_setting('settlement_carry_over_enabled') #>> '{}')::boolean, false);
  v_r record;
  v_linhas jsonb := '[]'::jsonb;
  v_n int := 0;
BEGIN
  IF NOT p_ensaio AND NOT v_ligado THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'transporte de divida desligado');
  END IF;

  FOR v_r IN
    SELECT d.subject_type, d.subject_id, d.subject_name,
           d.week_start_at::date AS semana_velha, d.cents
      FROM public.settlement_debtors() d
     WHERE d.week_start_at::date < p_week_start
       AND NOT EXISTS (SELECT 1 FROM public.settlement_carry_over c
                        WHERE c.subject_type = d.subject_type
                          AND c.subject_id = d.subject_id
                          AND c.from_week = d.week_start_at::date)
  LOOP
    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
      'tipo', v_r.subject_type, 'nome', v_r.subject_name,
      'de', v_r.semana_velha, 'para', p_week_start, 'cents', v_r.cents));
    v_n := v_n + 1;

    CONTINUE WHEN p_ensaio;

    -- Junta a divida velha ao acerto novo e fecha a velha a apontar para ela.
    IF v_r.subject_type = 'driver' THEN
      UPDATE driver_weekly_settlements
         SET net_balance = net_balance - (v_r.cents / 100.0),
             carried_over_cents = carried_over_cents + v_r.cents
       WHERE driver_id::text = v_r.subject_id AND week_start_at::date = p_week_start;
      UPDATE driver_weekly_settlements SET status = 'rolled_over',
             notes = COALESCE(notes,'') || ' | transportado para ' || p_week_start
       WHERE driver_id::text = v_r.subject_id AND week_start_at::date = v_r.semana_velha;

    ELSIF v_r.subject_type = 'partner' THEN
      UPDATE partner_weekly_settlements
         SET net_balance = net_balance - (v_r.cents / 100.0),
             carried_over_cents = carried_over_cents + v_r.cents
       WHERE partner_id::text = v_r.subject_id AND week_start_at::date = p_week_start;
      UPDATE partner_weekly_settlements SET status = 'rolled_over',
             notes = COALESCE(notes,'') || ' | transportado para ' || p_week_start
       WHERE partner_id::text = v_r.subject_id AND week_start_at::date = v_r.semana_velha;

    ELSIF v_r.subject_type = 'cleaner' THEN
      UPDATE cleaner_weekly_settlements
         SET net_payout_cents = net_payout_cents - v_r.cents,
             carried_over_cents = carried_over_cents + v_r.cents
       WHERE cleaner_id::text = v_r.subject_id AND week_start_at::date = p_week_start;
      UPDATE cleaner_weekly_settlements SET status = 'rolled_over',
             notes = COALESCE(notes,'') || ' | transportado para ' || p_week_start
       WHERE cleaner_id::text = v_r.subject_id AND week_start_at::date = v_r.semana_velha;

    ELSIF v_r.subject_type = 'washer' THEN
      UPDATE washer_weekly_settlements
         SET net_payout_cents = net_payout_cents - v_r.cents,
             carried_over_cents = carried_over_cents + v_r.cents
       WHERE washer_id::text = v_r.subject_id AND week_start_at::date = p_week_start;
      UPDATE washer_weekly_settlements SET status = 'rolled_over',
             notes = COALESCE(notes,'') || ' | transportado para ' || p_week_start
       WHERE washer_id::text = v_r.subject_id AND week_start_at::date = v_r.semana_velha;
    END IF;

    INSERT INTO public.settlement_carry_over
      (subject_type, subject_id, from_week, to_week, cents)
    VALUES (v_r.subject_type, v_r.subject_id, v_r.semana_velha, p_week_start, v_r.cents)
    ON CONFLICT ON CONSTRAINT settlement_carry_over_uniq DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'ensaio', p_ensaio,
                            'transportados', v_n, 'linhas', v_linhas);
END $function$;

REVOKE ALL ON FUNCTION public.apply_settlement_carry_over(date, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_settlement_carry_over(date, boolean) TO service_role;

-- 4) DEPOIS de conferir, ligar no fecho — acrescentar ao fim de
--    `run_weekly_closeout()`, antes do RETURN:
--
--      BEGIN
--        PERFORM public.apply_settlement_carry_over(
--          (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date - 7, false);
--      EXCEPTION WHEN OTHERS THEN
--        RAISE WARNING 'transporte de divida falhou: %', SQLERRM;
--      END;
--
--    Fica de fora deste ficheiro de proposito: uma coisa e ter a ferramenta,
--    outra e apontá-la ao fecho real.
--
-- 5) Os estados novos ('rolled_over') precisam de caber no CHECK de cada
--    tabela. `driver_` e `cleaner_` admitem hoje pending/paid/received/disputed
--    e `washer_` admite tambem cancelled — nenhum admite 'rolled_over'. Alargar
--    o CHECK dessas tabelas faz parte de aplicar esta proposta.
