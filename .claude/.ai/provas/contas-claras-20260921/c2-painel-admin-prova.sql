-- Bloco C2 (21/09, 09h00–09h15 UTC) — painel admin dos acertos. Migration aplicada:
-- contas_claras_c2_admin_acertos_reabrir_avisos_2026_09_21 (repo: 20260921094000_...sql).
-- JWT de admin simulado com set_config (uid c9fccf85 = nilofulfarotuga@gmail.com, role admin).

-- C2.1 a lista traz o acerto vivo (colunas novas) — semana 14–20/09 (week_start_at::date = 2026-09-13)
with l as (select public.admin_weekly_closeout_list('2026-09-13') as j)
select x->>'name', x->>'type', (x->>'net_cents')::int as recibo, x->'acerto'->>'net_cents' as acerto,
       x->'acerto'->>'corridas_n', x->'acerto'->>'corridas_cents', x->'acerto'->>'corridas_em_mao_cents',
       x->'acerto'->>'reembolsos_cents', x->>'reabrir_permitido'
from l, jsonb_array_elements(l.j->'items') x;
-- SAÍDA: Danilo recibo 4352 = acerto 4352 · 16 corridas · 6200 · em mão das corridas 2500 · reembolsos 1473 · reabrir true
--        Erika 400 = 400 · 1 · 400 · 0 · 0 · true · Valdemir 1700 = 1700 · 13 · 5200 · 4000 · 0 · true
--        Goola (parceiro) acerto null (só estafetas têm o objecto), reabrir true.

-- C2.2 reabrir em ROLLBACK (DO ... RAISE EXCEPTION 'RESULT %'): plantado status=paid na linha do Valdemir
--      e recibo 'sent'; chamada admin_reabrir_acerto('driver', <valdemir>, '2026-09-13', 'teste em rollback: pagamento marcado por engano')
-- SAÍDA: ret {ok:true, estado_anterior:paid, valor_anterior:17.00, recalcular:true, week_start_at:2026-09-13T23:00Z}
--        status=pending · notes="[21/09/2026 10:07] Reaberto por nilofulfarotuga@gmail.com — motivo: teste em rollback: … (estava paid, valor 17.00 EUR)"
--        admin_audit_log action=reabrir_acerto: 1 linha · weekly_digest_log da pessoa: email_status=pending
--        motivo curto ('ok') → "motivo_obrigatorio: escreve porque reabres este acerto (mínimo 5 letras)"
--        semana antiga (31/08) → "semana_travada: só se reabre a semana em curso ou a última fechada; esta começou a 31/08/2026"
-- Depois do rollback: Valdemir status=pending, paid_at null, notes null, recibo 'sent', 0 auditorias reabrir_acerto (tudo desfeito).

-- C2.3 avisos — base sã: fecho_travado 0, pedidos_no_vermelho 0 (mecanismos novos, ainda sem casos reais).
--      Em ROLLBACK, plantado 1 admin_audit_log 'fecho_linha_travada_valor_diferente' (Valdemir 17,00 vs 19,50) e
--      1 admin_notifications 'pedido_no_vermelho' (Continente, cliente 20,00 / mercadoria 17,40 / estafeta 3,80 / sobrou −1,20,
--      deep_link /admin/orders/teste-rollback-0001) → admin_avisos_fecho('2026-09-13') devolve os dois com nome, valores e link.
--      Depois do rollback: 0 e 0 (nada ficou).

-- C2.4 "Reenviar recibos" → admin_resend_weekly_digest('2026-08-23') (semana cuja única linha é a do próprio Danilo,
--      para a prova não mandar email a mais ninguém). RPC devolveu {ok:true, request_id:1679}.
--      net._http_response 1679: status 200, body {"ok":true,"week_start":"2026-08-23","subjects":1,"emails_sent":1,"force":true,
--      "emails_enabled":true,"resend_key_origem":"vault"} · weekly_digest_log: email_sent_at passou de 2026-09-06 23:53 para 2026-09-21 09:10:11.
--      A RPC já mandava force:true no corpo (lido no C0); o botão da app chama-a com p_week_start.
