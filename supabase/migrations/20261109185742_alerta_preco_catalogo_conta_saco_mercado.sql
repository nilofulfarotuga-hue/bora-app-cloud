-- 20261109185742_alerta_preco_catalogo_conta_saco_mercado: aplicada em produção a 09/11/2026 e escrita no repo a partir de
-- supabase_migrations.schema_migrations.statements (missão pendencias-2026-11-09).
-- 09/11/2026: o talao do mercado traz o saco (0,10 por saco); o aviso tem de o contar
-- senao com 2 sacos dava aviso falso de 0,20.
DO $$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public._trg_alerta_preco_catalogo_fn'::regproc);
  v_def := replace(v_def,
    'v_gap := v_talao_cents - v_base_cents;',
    '-- 09/11/2026: o saco do mercado vem no talao.
  IF v_order.service_type = ''storeShopping'' THEN
    v_base_cents := v_base_cents + ROUND(COALESCE(v_order.bag_fee, 0)::numeric * 100)::int;
  END IF;
  v_gap := v_talao_cents - v_base_cents;');
  EXECUTE v_def;
END $$;
