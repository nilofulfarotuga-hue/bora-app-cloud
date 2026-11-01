-- 01/11/2026 (missão contabilista-2026-11-01, autorizado pelo Danilo 01/11) — ERRO ENCONTRADO PELO CAMINHO, APLICADO.
--
-- public._fecho_limites(ano, mes) calcula o fim do mês como
--   make_timestamptz(ano, mes, 1, 0,0,0, 'Europe/Lisbon') + interval '1 month'
-- e a soma do intervalo é feita no fuso da sessão (UTC), não em Lisboa. Nos meses em que a hora muda
-- (outubro e março) o fim sai 1 hora errado: para outubro/2026 dá 2026-10-30 23:00 UTC = 30/10 23:00
-- de Lisboa, por isso TODO O DIA 31/10 FICA FORA do fecho de outubro (e entra em nenhum mês).
-- Provado por SELECT a 01/11: o fecho enviado às 09:00 contou 18 pedidos (317,66 €) quando outubro
-- teve 20 (369,70 €) — faltaram a Jyosmi Sushi 33,58 € e o Continente 18,46 € de 31/10 — e a
-- limpeza de 31/10 (36,00 €) também ficou fora do extrato da Mayra.
--
-- Correção: o fim é o dia 1 do mês seguinte às 00:00 de Lisboa, calculado directamente.
-- Afecta admin_monthly_closeout, partner_monthly_statement, driver_monthly_invoice_summary e o
-- fecho_mensal_prestadores proposto. Depois de aplicar, reenviar o fecho de outubro (force:true).

create or replace function public._fecho_limites(p_ano integer, p_mes integer)
returns table(ini timestamptz, fim timestamptz)
language sql immutable set search_path to 'public'
as $$
  select make_timestamptz(p_ano, p_mes, 1, 0, 0, 0, 'Europe/Lisbon'),
         make_timestamptz(case when p_mes = 12 then p_ano + 1 else p_ano end,
                          case when p_mes = 12 then 1 else p_mes + 1 end,
                          1, 0, 0, 0, 'Europe/Lisbon');
$$;
