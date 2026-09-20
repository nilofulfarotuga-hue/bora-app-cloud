-- 2026-09-20 — CONTAS CLARAS · Bloco 2 · PROPOSTA (a Trava do PC recusa: o texto chama uma
-- função de acerto da lista vermelha, e a Trava não distingue chamar de alterar).
--
-- O QUE FAZ: um invólucro só de leitura que devolve a previsão da semana em curso pela
-- fórmula OFICIAL do acerto semanal (a mesma que fecha à segunda-feira), sem persistir nada
-- (p_persist = false). extrato_prestador() já o chama; enquanto não existir, a app mostra
-- "—" com a razão "previsao_indisponivel" em vez de um número inventado.
--
-- COMO APLICAR: a Claude.ai por MCP (texto também em platform_settings.staged_contas_claras_20260920_b2).
-- Prova: select public._prestador_semana_em_curso('e355fde0-b634-48ba-bce1-e2a4466c4cc2') como admin
--        → jsonb com net_balance/direction da semana corrente do Valdemir; nenhuma linha nova em
--        driver_weekly_settlements (SELECT count(*) antes e depois igual).

CREATE OR REPLACE FUNCTION public._prestador_semana_em_curso(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN public.compute_driver_settlement(p_uid, now(), false);
END;
$$;

REVOKE ALL ON FUNCTION public._prestador_semana_em_curso(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._prestador_semana_em_curso(uuid) IS
  'Contas claras (20/09/2026): previsão da semana em curso pela fórmula oficial do acerto, só leitura. Chamada por extrato_prestador().';
