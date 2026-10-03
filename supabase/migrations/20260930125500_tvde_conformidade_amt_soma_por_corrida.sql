-- tvde-conformidade-lei-59-2026 · correção do relatório AMT — 2026-09-30
-- A primeira versão somava os valores da verificação dos 25%, que no pacote
-- ida-e-volta são do PACOTE inteiro → contava o pacote duas vezes (julho dava
-- 16 € em vez de 8 €). Agora soma os valores gravados em cada corrida.
-- Conferido: faturado = soma(driver_earn + bora_cut) das corridas do mês nos
-- 3 meses com corridas (jul 800, ago 11180, set 49150 cêntimos).
create or replace function public.tvde_amt_relatorio_gerar(p_mes date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_mes date := date_trunc('month', coalesce(p_mes, (now() at time zone 'Europe/Lisbon')::date - interval '1 month'))::date;
  v_pct numeric := coalesce((public.get_setting('tvde_amt_contribuicao_pct') #>> '{}')::numeric, 5);
  v_row public.tvde_amt_reports;
begin
  perform public.tvde_verificar_intermediacao(r.id) from public.tvde_rides r
    where r.status = 'finalizada'
      and (r.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
      and (r.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
      and not exists (select 1 from public.tvde_intermediacao_verificacao iv where iv.ride_id = r.id);
  insert into public.tvde_amt_reports as a (mes, viagens, faturado_cents, intermediacao_cents,
     contribuicao_pct, contribuicao_cents, viagens_acima_teto, detalhe, gerado_em)
  select v_mes, count(*),
         coalesce(sum(coalesce(r.driver_earn_cents, 0) + coalesce(r.bora_cut_cents, 0)), 0),
         coalesce(sum(coalesce(r.bora_cut_cents, 0)), 0),
         v_pct, round(coalesce(sum(greatest(coalesce(r.bora_cut_cents, 0), 0)), 0) * v_pct / 100.0),
         count(*) filter (where iv.cumpre is false),
         jsonb_build_object(
           'por_pagamento', (select jsonb_object_agg(pm, n) from (
               select coalesce(r2.payment_method, '?') pm, count(*) n from public.tvde_rides r2
                where r2.status = 'finalizada'
                  and (r2.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
                  and (r2.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
                group by 1) q),
           'nota', 'Valores sem IVA (empresa por constituir). Faturado = motorista + Bora gravados em cada corrida. Contribuição = % da taxa de intermediação cobrada.'),
         now()
    from public.tvde_rides r left join public.tvde_intermediacao_verificacao iv on iv.ride_id = r.id
   where r.status = 'finalizada'
     and (r.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
     and (r.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
  on conflict (mes) do update set viagens = excluded.viagens, faturado_cents = excluded.faturado_cents,
     intermediacao_cents = excluded.intermediacao_cents, contribuicao_pct = excluded.contribuicao_pct,
     contribuicao_cents = excluded.contribuicao_cents, viagens_acima_teto = excluded.viagens_acima_teto,
     detalhe = excluded.detalhe, gerado_em = now()
  returning * into v_row;
  return to_jsonb(v_row);
end $$;
revoke all on function public.tvde_amt_relatorio_gerar(date) from public, anon, authenticated;

select public.tvde_amt_relatorio_gerar(m::date)
  from generate_series(date_trunc('month', (select min(created_at) from public.tvde_rides)),
                       date_trunc('month', now()), interval '1 month') m;
