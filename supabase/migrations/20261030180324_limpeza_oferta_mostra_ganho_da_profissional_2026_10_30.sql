-- 30/10/2026: o 1.º aviso de oferta de limpeza (_cleaning_next_offer) mostrava à profissional
-- o total que o cliente paga (ex.: 32,40 €), enquanto os toques seguintes (_cleaning_cron_offer_reping)
-- já mostram o que ela GANHA (regra de ouro do prestador, 09/10/2026). Só muda o texto do aviso;
-- nenhum valor, regra de despacho ou cobrança muda.
-- (Aplicada em produção a 30/10/2026 — versão 20261030180324; espelho no repo escrito a 01/11/2026,
--  missão zona-vermelha-2026-11-01, SQL lido de schema_migrations.statements.)
DO $mig$
DECLARE
  d text := pg_get_functiondef('public._cleaning_next_offer'::regproc);
  n text;
BEGIN
  n := replace(d,
    $a$|| (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens '$a$,
    $b$|| 'ganhas ' || (COALESCE(v_b.cleaner_earnings_cents, v_b.total_cents) / 100.0)::numeric(10,2) || ' EUR. Tens '$b$);
  IF n = d THEN
    RAISE EXCEPTION 'texto da oferta nao encontrado; nada foi mudado';
  END IF;
  EXECUTE n;
END
$mig$;
