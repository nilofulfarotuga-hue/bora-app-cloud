-- 23/11/2026 11:50 — (1) embalagem só quando a app mostra a linha (como o depósito Volta: input 'mostra_embalagem'),
-- para a app antiga continuar a ver e a pagar o saco normal e não ser preciso obrigar ninguém a atualizar;
-- (2) extrato do parceiro: embalagem numa coluna própria (o "cliente pagou" inclui-a; a parte da Bora não muda);
-- (3) listas de acertos semanais (admin e parceiro) passam a trazer embalagem_total. Achados 1 e 2 da missão embalagem-boom.

CREATE OR REPLACE FUNCTION public.app_mostra_embalagem(p_input jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $f$
  SELECT COALESCE(p_input->>'mostra_embalagem', '') IN ('true', '1');
$f$;

DO $mig$
DECLARE d text; d0 text; v_bloco text;
BEGIN
  v_bloco := $q$v_restaurant_id
    );
    -- 23/11/2026 embalagem da loja só quando a app mostra a linha (como o Volta); app antiga paga o saco normal.
    IF public.e_embalagem_da_loja(v_restaurant_id::text, v_pricing.bag_fee) AND NOT public.app_mostra_embalagem(p_input) THEN
      v_pricing.customer_total := ROUND(v_pricing.customer_total - v_pricing.bag_fee
        + COALESCE((SELECT (value::text)::numeric FROM public.platform_settings WHERE key = 'bag_fee_restaurant_cents'), 30) / 100.0, 2);
      v_pricing.bag_fee := ROUND(COALESCE((SELECT (value::text)::numeric FROM public.platform_settings WHERE key = 'bag_fee_restaurant_cents'), 30) / 100.0, 2);
    END IF;
    DECLARE v_free1 NUMERIC; BEGIN$q$;

  -- quote_order_pricing
  d := pg_get_functiondef('public.quote_order_pricing'::regproc); d0 := d;
  d := replace(d, $q$v_restaurant_id
    );
    DECLARE v_free1 NUMERIC; BEGIN$q$, v_bloco);
  IF d = d0 OR (length(d) - length(replace(d, 'app_mostra_embalagem', ''))) / length('app_mostra_embalagem') <> 1 THEN
    RAISE EXCEPTION 'quote_order_pricing: texto nao encontrado ou repetido';
  END IF;
  EXECUTE d;

  -- _create_order_core
  d := pg_get_functiondef('public._create_order_core'::regproc); d0 := d;
  d := replace(d, $q$v_restaurant_id
    );
    DECLARE v_free1 NUMERIC; BEGIN$q$, v_bloco);
  IF d = d0 OR (length(d) - length(replace(d, 'app_mostra_embalagem', ''))) / length('app_mostra_embalagem') <> 1 THEN
    RAISE EXCEPTION '_create_order_core: texto nao encontrado ou repetido';
  END IF;
  EXECUTE d;

  -- extrato_parceiro: embalagem numa coluna própria
  d := pg_get_functiondef('public.extrato_parceiro'::regproc); d0 := d;
  d := replace(d, $q$o.restaurant_id::text)) * 100)::int
           + CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN ROUND(COALESCE(o.bag_fee, 0) * 100)::int ELSE 0 END AS parceiro_cents,$q$,
$q$o.restaurant_id::text)) * 100)::int AS parceiro_cents,
           CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN ROUND(COALESCE(o.bag_fee, 0) * 100)::int ELSE 0 END AS embalagem_cents,$q$);
  d := replace(d, $q$'cliente_pagou_cents', p.produtos_cents + p.taxas_cents,$q$,
                  $q$'cliente_pagou_cents', p.produtos_cents + p.taxas_cents + p.embalagem_cents,$q$);
  d := replace(d, $q$'fica_para_o_parceiro_cents', p.parceiro_cents,$q$,
                  $q$'fica_para_o_parceiro_cents', p.parceiro_cents + p.embalagem_cents,
           'embalagem_cents', p.embalagem_cents,$q$);
  d := replace(d, $q$COALESCE(SUM(p.produtos_cents + p.taxas_cents), 0)$q$,
                  $q$COALESCE(SUM(p.produtos_cents + p.taxas_cents + p.embalagem_cents), 0)$q$);
  d := replace(d, $q$'fica_para_o_parceiro_cents', COALESCE(SUM(p.parceiro_cents), 0),$q$,
                  $q$'fica_para_o_parceiro_cents', COALESCE(SUM(p.parceiro_cents + p.embalagem_cents), 0),
           'embalagem_cents', COALESCE(SUM(p.embalagem_cents), 0),$q$);
  d := replace(d, $q$ROUND(SUM(p.parceiro_cents)::numeric / COUNT(*))$q$,
                  $q$ROUND(SUM(p.parceiro_cents + p.embalagem_cents)::numeric / COUNT(*))$q$);
  d := replace(d, $q$SUM(parceiro_cents) AS c$q$, $q$SUM(parceiro_cents + embalagem_cents) AS c$q$);
  d := replace(d, $q$'fica_para_o_parceiro_cents', ROUND(COALESCE(s.partner_share, 0) * 100)::int,$q$,
                  $q$'fica_para_o_parceiro_cents', ROUND((COALESCE(s.partner_share, 0) + COALESCE(s.embalagem_total, 0)) * 100)::int,
           'embalagem_cents', ROUND(COALESCE(s.embalagem_total, 0) * 100)::int,$q$);
  IF position('ELSE 0 END AS embalagem_cents,' in d) = 0
     OR position('p.produtos_cents + p.taxas_cents + p.embalagem_cents,' in d) = 0
     OR position($q$'fica_para_o_parceiro_cents', p.parceiro_cents + p.embalagem_cents,$q$ in d) = 0
     OR position('SUM(p.produtos_cents + p.taxas_cents + p.embalagem_cents)' in d) = 0
     OR position('SUM(p.parceiro_cents + p.embalagem_cents), 0),' in d) = 0
     OR position('SUM(p.parceiro_cents + p.embalagem_cents)::numeric' in d) = 0
     OR position('SUM(parceiro_cents + embalagem_cents) AS c' in d) = 0
     OR position('COALESCE(s.embalagem_total, 0)) * 100)::int,' in d) = 0
     OR position('THEN ROUND(COALESCE(o.bag_fee, 0) * 100)::int ELSE 0 END AS parceiro_cents' in d) > 0 THEN
    RAISE EXCEPTION 'extrato_parceiro: texto nao encontrado';
  END IF;
  EXECUTE d;

  -- admin_list_partner_settlements_for_week
  d := pg_get_functiondef('public.admin_list_partner_settlements_for_week'::regproc); d0 := d;
  d := replace(d, $q$    'net_balance',          s.net_balance,$q$,
$q$    'embalagem_total',      COALESCE(s.embalagem_total, 0), -- 23/11/2026 embalagem da loja
    'net_balance',          s.net_balance,$q$);
  IF d = d0 THEN RAISE EXCEPTION 'admin_list_partner_settlements_for_week: texto nao encontrado'; END IF;
  EXECUTE d;

  -- partner_my_weekly_closeout (histórico)
  d := pg_get_functiondef('public.partner_my_weekly_closeout'::regproc); d0 := d;
  d := replace(d, $q$    'net_balance', s.net_balance,$q$,
$q$    'embalagem_total', COALESCE(s.embalagem_total, 0),
    'net_balance', s.net_balance,$q$);
  IF d = d0 THEN RAISE EXCEPTION 'partner_my_weekly_closeout: texto nao encontrado'; END IF;
  EXECUTE d;
END
$mig$;