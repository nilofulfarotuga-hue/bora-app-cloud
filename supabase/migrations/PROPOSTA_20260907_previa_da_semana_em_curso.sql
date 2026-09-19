-- ============================================================================
-- PROPOSTA — NAO APLICADA. Espera ordem do Danilo.
-- ============================================================================
-- BLOCO 2.5 da missao "fecho semanal automatico" (2026-09-07).
--
-- O QUE FAZ
-- Um cartao "Previa da semana atual" no painel: o Danilo ve ao sabado quanto
-- vai ter de pagar e receber na segunda, antes de o fecho acontecer.
--
-- PORQUE NAO FOI APLICADA
-- A Trava (.claude/hooks/protege-banco.sh, regra 4) recusa qualquer DDL cujo
-- TEXTO mencione uma funcao de dinheiro, e nao distingue "chamar" de
-- "alterar". Esta funcao CHAMA `compute_driver_settlement`,
-- `compute_partner_weekly_settlement` e as irmas — sempre com p_persist=false,
-- ou seja, so calcula e devolve, nao grava nada nem move um centimo.
--
-- A Trava tem razao em ser burra aqui, e o PADRAO_BORA (seccao 6) diz que isto
-- NAO se contorna: deixa-se a proposta escrita e o Danilo aplica. Foi o que se
-- fez com `20260827102000_PROPOSTA_carwash_tokens.sql`.
--
-- RISCO: baixo. Leitura pura (p_persist = false). Nao escreve em tabela
-- nenhuma. Se falhar num sujeito, salta esse e continua.
--
-- COMO APLICAR (Danilo): correr este ficheiro no editor SQL do Supabase.
-- Depois disso o cartao aparece sozinho no ecra "Acertos da semana".
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_weekly_closeout_preview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini timestamptz := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_itens jsonb := '[]'::jsonb;
  v_r record;
  v_calc jsonb;
  v_cents int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  FOR v_r IN
    SELECT 'driver' AS tipo, d.user_id::text AS sid, d.name FROM drivers d WHERE d.user_id IS NOT NULL
    UNION ALL SELECT 'partner', r.id::text, r.name FROM restaurants r WHERE COALESCE(r.is_partner,false)
    UNION ALL SELECT 'cleaner', c.id::text, c.name FROM cleaners c WHERE COALESCE(c.is_active,false)
    UNION ALL SELECT 'washer',  wa.id::text, wa.name FROM washers wa WHERE COALESCE(wa.is_active,false)
  LOOP
    BEGIN
      v_calc := CASE v_r.tipo
        WHEN 'driver'  THEN public.compute_driver_settlement(v_r.sid::uuid, v_ini, false)
        WHEN 'partner' THEN public.compute_partner_weekly_settlement(v_r.sid, v_ini, false)
        WHEN 'cleaner' THEN public.compute_cleaner_weekly_settlement(v_r.sid::uuid, v_ini, false)
        WHEN 'washer'  THEN public.compute_washer_weekly_settlement(v_r.sid::uuid, v_ini, false)
      END;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;  -- um sujeito com dados estranhos nao pode partir a previa toda
    END;

    v_cents := CASE
      WHEN v_calc ? 'net_balance'      THEN round((v_calc->>'net_balance')::numeric * 100)::int
      WHEN v_calc ? 'net_payout_cents' THEN (v_calc->>'net_payout_cents')::int
      ELSE NULL END;

    IF v_cents IS NOT NULL AND v_cents <> 0 THEN
      v_itens := v_itens || jsonb_build_array(jsonb_build_object(
        'type', v_r.tipo, 'subject_id', v_r.sid, 'name', v_r.name,
        'net_cents', v_cents,
        'direction', CASE WHEN v_cents < 0 THEN 'owes_bora' ELSE 'bora_pays' END));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'week_start', v_ini::date,
    'parcial', true,
    'items', v_itens,
    'pagar_cents',   COALESCE((SELECT sum(abs((x->>'net_cents')::int)) FROM jsonb_array_elements(v_itens) x WHERE x->>'direction'='bora_pays'), 0),
    'receber_cents', COALESCE((SELECT sum(abs((x->>'net_cents')::int)) FROM jsonb_array_elements(v_itens) x WHERE x->>'direction'='owes_bora'), 0)
  );
END $function$;

REVOKE ALL ON FUNCTION public.admin_weekly_closeout_preview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_weekly_closeout_preview() TO authenticated;
