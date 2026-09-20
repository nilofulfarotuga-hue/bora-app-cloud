-- 2026-09-20 — CONTAS CLARAS · Bloco 5 — O VIGIA QUE GRITA.
--
-- Todos os dias compara o histórico com o saldo em todas as arcas e em todas as pontas.
-- Quando discordam, escreve o caso em payment_reconciliation_findings (a tabela de achados
-- que já existia) e manda aviso ao Telegram com nome, valor e pedido. NUNCA corrige — só aponta.
--
-- Casos conhecidos não gritam todos os dias: um achado aberto para a mesma entidade fica
-- calado até ser resolvido (resolved_at). Se for resolvido e o desacerto voltar, reabre e grita.
-- (A Isabel Rebelo — histórico 4,09 € contra saldo 1,00 € por ordem do Danilo — já está
-- registada desde o Bloco 1 com kind 'saldo_vs_historico' e pi_id 'wallet:<uid>': fica calada.)
--
-- Verificações (kind → o que compara):
--   saldo_vs_historico        carteira: client_wallets × soma de wallet_transactions (sem tokens)
--   vigia_entregas_saldo      estafeta: driver_balances × driver_transactions (ganhos+tokens−cash)
--   vigia_tvde_saldo          motorista: tvde_driver_balances × soma de settle_cents dos eventos
--   vigia_ledger_snapshot     livro-razão: user_balance_snapshots × soma de ledger_entries
--   vigia_parceiro_arcas      parceiro: ledger (restaurant earning) × order_financials
--   vigia_duplicado_carteira  mesma pessoa, pedido, tipo e valor repetidos em 10 minutos
--   vigia_payout_parado       payouts 'pending' cujo acerto já está pago
--   vigia_compensacao_fora_do_acerto  ganho no ledger sem pedido entregue (1,50 € de cancelamento)
--
-- Modos: p_dry = true não escreve nem grita (só devolve o que encontraria);
--        p_gritar = false escreve mas não manda Telegram (para provas).

CREATE OR REPLACE FUNCTION public.vigia_dinheiro_diario(p_gritar boolean DEFAULT true, p_dry boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_casos     jsonb := '[]'::jsonb;
  v_novos     jsonb := '[]'::jsonb;
  v_conhecidos int := 0;
  v_reabertos int := 0;
  v_c         record;
  v_existente record;
  v_msg       text;
  v_linhas    text;
  v_n         int;
  v_gritou    boolean := false;
BEGIN
  -- 1) recolher todos os desacertos de hoje -------------------------------------------
  FOR v_c IN
    -- carteira
    SELECT 'saldo_vs_historico' AS kind, 'warning' AS severity, 'wallet' AS entity_type, w.user_id::text AS entity_id,
           'wallet:' || w.user_id::text AS pi_id,
           (COALESCE(h.s, 0) - w.free_balance_cents) AS amount_cents,
           jsonb_build_object('quem', COALESCE(u.email, w.user_id::text), 'historico_cents', COALESCE(h.s, 0), 'saldo_cents', w.free_balance_cents) AS details
      FROM public.client_wallets w
      LEFT JOIN auth.users u ON u.id = w.user_id
      LEFT JOIN LATERAL (SELECT SUM(t.amount_cents) AS s FROM public.wallet_transactions t
                          WHERE t.user_id = w.user_id AND t.kind <> ALL (public.wallet_kinds_fora_do_saldo())) h ON true
     WHERE w.free_balance_cents <> COALESCE(h.s, 0)
    UNION ALL
    -- histórico sem linha de saldo
    SELECT 'saldo_vs_historico', 'warning', 'wallet', t.user_id::text, 'wallet:' || t.user_id::text,
           SUM(t.amount_cents) FILTER (WHERE t.kind <> ALL (public.wallet_kinds_fora_do_saldo())),
           jsonb_build_object('quem', t.user_id::text, 'historico_cents', SUM(t.amount_cents) FILTER (WHERE t.kind <> ALL (public.wallet_kinds_fora_do_saldo())), 'saldo_cents', NULL, 'nota', 'sem linha em client_wallets')
      FROM public.wallet_transactions t
     WHERE NOT EXISTS (SELECT 1 FROM public.client_wallets w WHERE w.user_id = t.user_id)
     GROUP BY t.user_id
    HAVING COALESCE(SUM(t.amount_cents) FILTER (WHERE t.kind <> ALL (public.wallet_kinds_fora_do_saldo())), 0) <> 0
    UNION ALL
    -- estafeta (entregas)
    SELECT 'vigia_entregas_saldo', 'critical', 'driver', b.driver_id::text, 'driver:' || b.driver_id::text,
           (COALESCE(h.s, 0) - ROUND(b.balance * 100)::int),
           jsonb_build_object('quem', d.name, 'historico_cents', COALESCE(h.s, 0), 'saldo_cents', ROUND(b.balance * 100)::int,
                              'regra', 'ganhos + tokens convertidos − cash_adjustment')
      FROM public.driver_balances b
      LEFT JOIN public.drivers d ON d.user_id = b.driver_id
      LEFT JOIN LATERAL (SELECT ROUND((COALESCE(SUM(t.amount) FILTER (WHERE t.type IN ('delivery_earning','token_conversion')), 0)
                                       - COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'cash_adjustment'), 0)) * 100)::int AS s
                           FROM public.driver_transactions t WHERE t.driver_id = b.driver_id AND t.status = 'completed') h ON true
     WHERE ROUND(b.balance * 100)::int <> COALESCE(h.s, 0)
    UNION ALL
    -- motorista (TVDE)
    SELECT 'vigia_tvde_saldo', 'critical', 'driver', b.driver_id::text, 'tvde:' || b.driver_id::text,
           (COALESCE(h.s, 0) - ROUND(b.balance * 100)::int),
           jsonb_build_object('quem', d.name, 'eventos_cents', COALESCE(h.s, 0), 'saldo_cents', ROUND(b.balance * 100)::int,
                              'regra', 'soma de tvde_ride_events.meta.settle_cents (finalizada)')
      FROM public.tvde_driver_balances b
      LEFT JOIN public.drivers d ON d.user_id = b.driver_id OR d.id = b.driver_id
      LEFT JOIN LATERAL (SELECT SUM((e.meta->>'settle_cents')::int) AS s
                           FROM public.tvde_ride_events e JOIN public.tvde_rides r ON r.id = e.ride_id
                          WHERE e.status = 'finalizada' AND (r.driver_id = b.driver_id OR r.driver_id IN (SELECT dd.id FROM public.drivers dd WHERE dd.user_id = b.driver_id))) h ON true
     WHERE ROUND(b.balance * 100)::int <> COALESCE(h.s, 0)
    UNION ALL
    -- livro-razão × snapshot
    SELECT 'vigia_ledger_snapshot', 'warning', s.user_type, s.user_id, 'ledger:' || s.user_type || ':' || s.user_id,
           (COALESCE(h.s, 0) - ROUND(s.balance * 100)::int),
           jsonb_build_object('quem', s.user_id, 'ledger_cents', COALESCE(h.s, 0), 'snapshot_cents', ROUND(s.balance * 100)::int)
      FROM public.user_balance_snapshots s
      LEFT JOIN LATERAL (SELECT ROUND(SUM(l.amount) * 100)::int AS s FROM public.ledger_entries l WHERE l.user_id = s.user_id AND l.user_type = s.user_type) h ON true
     WHERE ROUND(s.balance * 100)::int <> COALESCE(h.s, 0)
    UNION ALL
    -- parceiro: ledger × order_financials
    SELECT 'vigia_parceiro_arcas', 'critical', 'restaurant', x.rid, 'partner:' || x.rid,
           (x.ledger - x.fin),
           jsonb_build_object('quem', x.nome, 'ledger_cents', x.ledger, 'order_financials_cents', x.fin)
      FROM (SELECT r.id AS rid, r.name AS nome,
                   COALESCE((SELECT ROUND(SUM(l.amount) * 100)::int FROM public.ledger_entries l WHERE l.user_type = 'restaurant' AND l.type = 'earning' AND l.user_id = r.id), 0) AS ledger,
                   COALESCE((SELECT ROUND(SUM(f.restaurant_amount) * 100)::int FROM public.order_financials f JOIN public.orders o ON o.id = f.order_id::text WHERE o.restaurant_id = r.id), 0) AS fin
              FROM public.restaurants r WHERE COALESCE(r.is_partner, false)) x
     WHERE x.ledger <> x.fin
    UNION ALL
    -- duplicados na carteira (últimos 2 dias)
    SELECT 'vigia_duplicado_carteira', 'critical', 'wallet', t.user_id::text, 'dup:' || COALESCE(t.related_order_id, '-') || ':' || t.kind || ':' || t.amount_cents::text,
           t.amount_cents * (COUNT(*) - 1),
           jsonb_build_object('quem', t.user_id::text, 'pedido', t.related_order_id, 'kind', t.kind, 'valor_cents', t.amount_cents, 'vezes', COUNT(*),
                              'entre', MIN(t.created_at), 'e', MAX(t.created_at))
      FROM public.wallet_transactions t
     WHERE t.created_at > now() - interval '2 days' AND t.amount_cents <> 0
     GROUP BY t.user_id, t.related_order_id, t.kind, t.amount_cents
    HAVING COUNT(*) > 1 AND MAX(t.created_at) - MIN(t.created_at) < interval '10 minutes'
    UNION ALL
    -- payouts parados
    SELECT 'vigia_payout_parado', 'warning', 'payout', p.id::text, 'payout:' || p.id::text,
           ROUND(p.amount * 100)::int,
           jsonb_build_object('quem', p.user_id, 'user_type', p.user_type, 'criado', p.created_at,
                              'nota', 'payout em pending com acerto da mesma pessoa já pago — gémeo parado')
      FROM public.payouts p
     WHERE p.status = 'pending'
       AND ((p.user_type = 'restaurant' AND EXISTS (SELECT 1 FROM public.partner_weekly_settlements s WHERE s.partner_id = p.user_id AND s.status IN ('paid','received')))
         OR (p.user_type = 'driver' AND EXISTS (SELECT 1 FROM public.driver_weekly_settlements s WHERE s.driver_id::text = p.user_id AND s.status IN ('paid','received'))))
    UNION ALL
    -- compensações fora do acerto
    SELECT 'vigia_compensacao_fora_do_acerto', 'warning', 'order', l.order_id::text, 'comp:' || l.order_id::text,
           ROUND(l.amount * 100)::int,
           jsonb_build_object('quem', COALESCE(d.name, l.user_id), 'pedido', l.order_id, 'estado_pedido', o.status,
                              'nota', 'ganho no ledger (compensação) sem entrega: não está em driver_balances nem no acerto semanal')
      FROM public.ledger_entries l
      LEFT JOIN public.orders o ON o.id = l.order_id::text
      LEFT JOIN public.drivers d ON d.user_id::text = l.user_id
     WHERE l.user_type = 'driver' AND l.type = 'earning' AND (o.id IS NULL OR o.status <> 'delivered')
  LOOP
    v_casos := v_casos || jsonb_build_object('kind', v_c.kind, 'severity', v_c.severity, 'entity_type', v_c.entity_type,
                 'entity_id', v_c.entity_id, 'pi_id', v_c.pi_id, 'amount_cents', v_c.amount_cents, 'details', v_c.details);
  END LOOP;

  IF p_dry THEN
    RETURN jsonb_build_object('ok', true, 'dry', true, 'casos', jsonb_array_length(v_casos), 'lista', v_casos);
  END IF;

  -- 2) escrever: novo grita; aberto cala; resolvido que voltou reabre e grita ----------
  FOR v_c IN SELECT * FROM jsonb_to_recordset(v_casos)
             AS z(kind text, severity text, entity_type text, entity_id text, pi_id text, amount_cents int, details jsonb) LOOP
    SELECT * INTO v_existente FROM public.payment_reconciliation_findings f
     WHERE f.kind = v_c.kind AND f.pi_id = v_c.pi_id AND f.entity_id = v_c.entity_id;
    IF NOT FOUND THEN
      INSERT INTO public.payment_reconciliation_findings (kind, severity, entity_type, entity_id, pi_id, amount_cents, details)
      VALUES (v_c.kind, v_c.severity, v_c.entity_type, v_c.entity_id, v_c.pi_id, v_c.amount_cents,
              v_c.details || jsonb_build_object('origem', 'vigia_dinheiro_diario', 'primeira_vez', now()));
      v_novos := v_novos || jsonb_build_object('kind', v_c.kind, 'quem', v_c.details->>'quem', 'amount_cents', v_c.amount_cents, 'pedido', COALESCE(v_c.details->>'pedido', v_c.entity_id));
    ELSIF v_existente.resolved_at IS NOT NULL THEN
      UPDATE public.payment_reconciliation_findings
         SET resolved_at = NULL, run_at = now(), amount_cents = v_c.amount_cents,
             details = v_c.details || jsonb_build_object('origem', 'vigia_dinheiro_diario', 'reaberto_em', now())
       WHERE id = v_existente.id;
      v_reabertos := v_reabertos + 1;
      v_novos := v_novos || jsonb_build_object('kind', v_c.kind, 'quem', v_c.details->>'quem', 'amount_cents', v_c.amount_cents, 'pedido', COALESCE(v_c.details->>'pedido', v_c.entity_id), 'reaberto', true);
    ELSE
      v_conhecidos := v_conhecidos + 1;
      UPDATE public.payment_reconciliation_findings SET run_at = now(), amount_cents = v_c.amount_cents WHERE id = v_existente.id
         AND amount_cents IS DISTINCT FROM v_c.amount_cents;
    END IF;
  END LOOP;

  -- 3) gritar só se houver coisa nova ---------------------------------------------------
  v_n := jsonb_array_length(v_novos);
  IF v_n > 0 AND p_gritar THEN
    SELECT string_agg(
             '• ' || COALESCE(x->>'quem', '?') || ' — ' || replace(((x->>'amount_cents')::int / 100.0)::numeric(12,2)::text, '.', ',') || ' € — '
             || CASE x->>'kind'
                  WHEN 'saldo_vs_historico' THEN 'carteira: histórico ≠ saldo'
                  WHEN 'vigia_entregas_saldo' THEN 'entregas: histórico ≠ saldo'
                  WHEN 'vigia_tvde_saldo' THEN 'TVDE: eventos ≠ saldo'
                  WHEN 'vigia_ledger_snapshot' THEN 'livro-razão ≠ snapshot'
                  WHEN 'vigia_parceiro_arcas' THEN 'parceiro: livro-razão ≠ order_financials'
                  WHEN 'vigia_duplicado_carteira' THEN 'carteira: linha repetida'
                  WHEN 'vigia_payout_parado' THEN 'payout parado (acerto já pago)'
                  WHEN 'vigia_compensacao_fora_do_acerto' THEN 'compensação fora do acerto'
                  ELSE x->>'kind' END
             || CASE WHEN x->>'pedido' IS NOT NULL THEN ' (' || left(x->>'pedido', 8) || ')' ELSE '' END
             || CASE WHEN COALESCE((x->>'reaberto')::boolean, false) THEN ' [voltou]' ELSE '' END,
             E'
' ORDER BY (x->>'amount_cents')::int DESC)
      INTO v_linhas FROM jsonb_array_elements(v_novos) x;
    v_msg := '🔎 VIGIA DO DINHEIRO — ' || v_n || ' novo' || CASE WHEN v_n = 1 THEN '' ELSE 's' END
             || E' (só aponto, não corrijo):
' || COALESCE(v_linhas, '')
             || E'
Painel admin › Contas claras › escudo.';
    BEGIN
      PERFORM public._telegram_admin(v_msg);
      v_gritou := true;
    EXCEPTION WHEN OTHERS THEN
      v_gritou := false;
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'dry', false, 'casos', jsonb_array_length(v_casos),
                            'novos', v_n, 'reabertos', v_reabertos, 'conhecidos_calados', v_conhecidos,
                            'gritou', v_gritou, 'lista_novos', v_novos);
END;
$$;

REVOKE ALL ON FUNCTION public.vigia_dinheiro_diario(boolean, boolean) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.vigia_dinheiro_diario(boolean, boolean) IS
  'Contas claras (20/09/2026): compara histórico × saldo em todas as arcas; escreve achados e grita no Telegram só quando há caso novo. Nunca corrige.';

-- 4) todos os dias às 06:10 (depois do reconciliador das 05:45) ----------------------------
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'vigia-dinheiro-diario') THEN
    PERFORM cron.schedule('vigia-dinheiro-diario', '10 6 * * *', 'SELECT public.vigia_dinheiro_diario();');
  END IF;
END
$do$;

-- 5) o admin lê e resolve os achados no painel ----------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_vigia_achados(p_so_abertos boolean DEFAULT true, p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE WHEN NOT public.is_admin() THEN jsonb_build_object('ok', false, 'error', 'NOT_ADMIN')
         ELSE jsonb_build_object('ok', true,
           'abertos', (SELECT COUNT(*) FROM public.payment_reconciliation_findings WHERE resolved_at IS NULL),
           'lista', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                       'id', f.id, 'kind', f.kind, 'severity', f.severity, 'entity_type', f.entity_type, 'entity_id', f.entity_id,
                       'amount_cents', f.amount_cents, 'details', f.details, 'run_at', f.run_at, 'resolved_at', f.resolved_at)
                       ORDER BY f.resolved_at NULLS FIRST, f.run_at DESC)
                     FROM (SELECT * FROM public.payment_reconciliation_findings
                            WHERE (NOT p_so_abertos) OR resolved_at IS NULL
                            ORDER BY resolved_at NULLS FIRST, run_at DESC LIMIT GREATEST(p_limit, 1)) f), '[]'::jsonb)) END;
$$;
REVOKE ALL ON FUNCTION public.admin_vigia_achados(boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_vigia_achados(boolean, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_vigia_resolver(p_id uuid, p_nota text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  UPDATE public.payment_reconciliation_findings
     SET resolved_at = now(),
         details = COALESCE(details, '{}'::jsonb) || jsonb_build_object('resolvido_por', auth.uid(), 'nota_resolucao', p_nota, 'resolvido_em', now())
   WHERE id = p_id AND resolved_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACHADO_NAO_ENCONTRADO_OU_JA_RESOLVIDO'; END IF;
  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), 'vigia_resolver', 'payment_reconciliation_findings', p_id::text, jsonb_build_object('nota', p_nota));
  RETURN jsonb_build_object('ok', true, 'id', p_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_vigia_resolver(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_vigia_resolver(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_vigia_correr_agora()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  RETURN public.vigia_dinheiro_diario(true, false);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_vigia_correr_agora() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_vigia_correr_agora() TO authenticated;
