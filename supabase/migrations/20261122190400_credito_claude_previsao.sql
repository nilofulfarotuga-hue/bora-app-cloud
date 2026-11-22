-- Missão hermes-diretor-2026-11-20 — B9: o cartão do crédito do Claude no painel (/admin/motores).
-- Só leitura: gasto do mês, previsão até ao fim do mês, quanto falta e quem gasta mais. Não muda nada.
-- "percentagem" = quanto do crédito lido já se gastou. "estado": claude (normal), poupanca (85% ou mais:
-- o porteiro passa os agentes de volume aos grátis), gratis (crédito acabado).
create or replace function public.admin_credito_claude_previsao() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  hoje     date := (now() at time zone 'Europe/Lisbon')::date;
  ini_mes  timestamptz := date_trunc('month', now() at time zone 'Europe/Lisbon') at time zone 'Europe/Lisbon';
  dia      int := extract(day from hoje);
  dias     int := extract(day from (date_trunc('month', hoje) + interval '1 month - 1 day'));
  credito  numeric; lido timestamptz; gasto_mes numeric; gasto_desde numeric; ritmo numeric; previsao numeric; falta numeric; pct numeric;
begin
  if not public.is_admin() then raise exception 'so o administrador'; end if;
  begin
    select nullif(value #>> '{}', '')::numeric into credito from public.platform_settings where key = 'claude_credito_atual_usd';
    select nullif(value #>> '{}', '')::timestamptz into lido from public.platform_settings where key = 'claude_credito_lido_em';
  exception when others then credito := null; lido := null;
  end;
  select coalesce(sum(custo_usd), 0) into gasto_mes from public.ia_gastos where quando >= ini_mes;
  select coalesce(sum(custo_usd), 0) into gasto_desde from public.ia_gastos where quando >= coalesce(lido, ini_mes);
  -- ritmo: a média dos últimos 7 dias (mais fiel do que a média do mês quando o gasto muda a meio)
  select coalesce(sum(custo_usd), 0) / 7.0 into ritmo from public.ia_gastos where quando >= now() - interval '7 days';
  previsao := gasto_mes + ritmo * greatest(dias - dia, 0);
  falta := case when credito is null then null else credito - gasto_desde end;
  pct := case when coalesce(credito, 0) > 0 then round(100 * gasto_desde / credito, 1) end;
  return jsonb_build_object(
    'mes', to_char(hoje, 'YYYY-MM'), 'gasto_usd', round(gasto_mes, 2), 'credito_usd', credito, 'previsao_usd', round(previsao, 2),
    'falta_usd', round(falta, 2), 'percentagem', pct, 'dia_do_mes', dia, 'dias_no_mes', dias, 'ritmo_dia_usd', round(ritmo, 2),
    'estado', case when falta is not null and falta <= 0 then 'gratis' when coalesce(pct, 0) >= 85 then 'poupanca' else 'claude' end,
    'top', (select coalesce(jsonb_agg(x), '[]'::jsonb)
              from (select robo, perfil, round(sum(custo_usd), 2) as usd, count(*) as chamadas
                      from public.ia_gastos where quando >= ini_mes group by 1, 2 order by 3 desc nulls last limit 6) x));
end $$;
revoke all on function public.admin_credito_claude_previsao() from public, anon;
grant execute on function public.admin_credito_claude_previsao() to authenticated, service_role;
