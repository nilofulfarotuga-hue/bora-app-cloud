import { readFileSync, writeFileSync } from 'node:fs';
let s = readFileSync('compute_partner_weekly_settlement.sql', 'utf8').replace(/\r\n/g, '\n');
const troca = (de, para) => { const n = s.split(de).length - 1; if (n !== 1) throw new Error('ancora ' + n + ': ' + de); s = s.replace(de, para); };
troca("  v_deposit numeric := 0;   -- 09/11/2026 Volta\n",
      "  v_deposit numeric := 0;   -- 09/11/2026 Volta\n  v_extra numeric := 0;     -- 11/11/2026 farmacias: comissão extra da loja depois da data de início\n");
troca("  v_commission := ROUND(v_gross - v_share, 2);\n",
`  v_commission := ROUND(v_gross - v_share, 2);
  -- 11/11/2026 farmacias-2026-11-11 (autorizado pelo Danilo): comissão extra da loja (ex.: 10 % depois de
  -- 3 meses sem comissão). Só conta em pedidos criados a partir de restaurants.partner_extra_commission_starts_at.
  -- Lojas com partner_extra_commission_pct ou starts_at a null: v_extra = 0 (nada muda para elas).
  SELECT COALESCE(ROUND(SUM(COALESCE(lx.share, 0) * r.partner_extra_commission_pct), 2), 0) INTO v_extra
    FROM public.orders o
    JOIN public.restaurants r ON r.id = o.restaurant_id
    LEFT JOIN LATERAL (
      SELECT SUM(le.amount) AS share
      FROM public.ledger_entries le
      WHERE le.order_id::text = o.id
        AND le.user_type = 'restaurant'
        AND le.type = 'earning'
    ) lx ON true
   WHERE o.restaurant_id = p_partner_id
     AND o.status = 'delivered'
     AND o.delivered_at >= v_bounds.week_start
     AND o.delivered_at <= v_bounds.week_end
     AND r.partner_extra_commission_pct IS NOT NULL
     AND r.partner_extra_commission_starts_at IS NOT NULL
     AND o.created_at >= r.partner_extra_commission_starts_at;
  IF v_extra <> 0 THEN
    v_share := ROUND(v_share - v_extra, 2);
    v_commission := ROUND(v_gross - v_share, 2);
  END IF;
`);
troca("    'commission_total', v_commission,\n", "    'commission_total', v_commission,\n    'comissao_extra', v_extra,\n");
const cab = `-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (autorizado pelo Danilo a 11/11/2026 para farmacia-se-guarda e
-- farmacia-teixeira-guarda: "a farmácia não paga nada nos 3 primeiros meses e depois paga 10% do que vender pela app").
-- Zero efeito nas outras lojas: só conta com restaurants.partner_extra_commission_pct E partner_extra_commission_starts_at
-- preenchidos (hoje só as duas farmácias têm o pct, e a data fica vazia até admin_farmacia_abrir = abertura + 3 meses).
-- farmacias-2026-11-11 · 05 · comissão extra no fecho semanal do parceiro
-- Corpo de compute_partner_weekly_settlement copiado da produção a 11/11/2026 + v_extra.
-- A base dos 10 % é a parte da loja (o que a farmácia receberia). Pedidos de demonstração não entram em fechos.
`;
writeFileSync('migracao05.sql', cab + s.trim() + '\n');
console.log('ok');
