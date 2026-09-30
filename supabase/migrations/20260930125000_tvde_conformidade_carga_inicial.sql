-- tvde-conformidade-lei-59-2026 · carga inicial (só tabelas NOVAS) — 2026-09-30
-- Correção da medição dos 25% no pacote ida-e-volta: o valor da volta fica
-- reservado na ida, por isso mede-se o PACOTE inteiro (todas as pernas com o
-- mesmo roundtrip_credit_id), não perna a perna.
create or replace function public.tvde_verificar_intermediacao(p_ride uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.tvde_rides; v_total int; v_bora int; v_teto numeric; v_pct numeric; v_ok boolean; v_base text;
begin
  select * into r from public.tvde_rides where id = p_ride;
  if not found or r.status <> 'finalizada' then return null; end if;
  v_teto := coalesce((public.get_setting('tvde_intermediacao_teto_pct') #>> '{}')::numeric, 25);
  if r.roundtrip_credit_id is not null then
    select coalesce(sum(coalesce(x.driver_earn_cents, 0) + coalesce(x.bora_cut_cents, 0)), 0),
           coalesce(sum(coalesce(x.bora_cut_cents, 0)), 0)
      into v_total, v_bora
      from public.tvde_rides x where x.roundtrip_credit_id = r.roundtrip_credit_id and x.status = 'finalizada';
    v_base := 'pacote ida-e-volta (' || (select count(*) from public.tvde_rides x
                where x.roundtrip_credit_id = r.roundtrip_credit_id and x.status = 'finalizada') || ' perna(s) feitas); sem IVA';
  else
    v_total := coalesce(r.driver_earn_cents, 0) + coalesce(r.bora_cut_cents, 0);
    v_bora := r.bora_cut_cents;
    v_base := 'bora_cut / (motorista + bora_cut); sem IVA (empresa por constituir)';
  end if;
  if v_total <= 0 or v_bora is null then
    v_pct := null; v_ok := true;
  else
    v_pct := round(100.0 * v_bora / v_total, 2);
    v_ok := v_pct <= v_teto;
  end if;
  insert into public.tvde_intermediacao_verificacao as iv
    (ride_id, valor_viagem_cents, intermediacao_cents, pct, teto_pct, cumpre, base, verificado_em)
  values (p_ride, greatest(v_total, 0), coalesce(v_bora, 0), v_pct, v_teto, v_ok, v_base, now())
  on conflict (ride_id) do update set valor_viagem_cents = excluded.valor_viagem_cents,
     intermediacao_cents = excluded.intermediacao_cents, pct = excluded.pct, teto_pct = excluded.teto_pct,
     cumpre = excluded.cumpre, base = excluded.base, verificado_em = now();
  if not v_ok then
    insert into public.tvde_compliance_events (tipo, ride_id, driver_user_id, ator, motivo, meta)
    select 'intermediacao_acima_teto', p_ride, r.driver_id, 'sistema',
           'Taxa de intermediação ' || v_pct || '% acima do teto de ' || v_teto || '%',
           jsonb_build_object('pct', v_pct, 'bora_cents', v_bora, 'total_cents', v_total, 'base', v_base)
     where not exists (select 1 from public.tvde_compliance_events e
                        where e.tipo = 'intermediacao_acima_teto' and e.ride_id = p_ride and e.meta->>'pct' = v_pct::text);
  end if;
  return jsonb_build_object('pct', v_pct, 'cumpre', v_ok, 'teto', v_teto, 'base', v_base);
end $$;
revoke all on function public.tvde_verificar_intermediacao(uuid) from public, anon, authenticated;

-- No fim de uma perna do pacote volta-se a medir as outras (o pacote mudou).
create or replace function public.fn_tvde_intermediacao_no_fim()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status = 'finalizada' then
    begin
      perform public.tvde_verificar_intermediacao(new.id);
      if new.roundtrip_credit_id is not null then
        perform public.tvde_verificar_intermediacao(x.id) from public.tvde_rides x
         where x.roundtrip_credit_id = new.roundtrip_credit_id and x.id <> new.id and x.status = 'finalizada';
      end if;
    exception when others then
      insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
      values ('tvde-conformidade', 'intermediacao', 'falhou', new.id || ' ' || sqlerrm, 'db');
    end;
  end if;
  return new;
end $$;

-- 1) teto dos 25%: verifica todas as corridas já finalizadas
select count(public.tvde_verificar_intermediacao(r.id)) from public.tvde_rides r where r.status = 'finalizada';
-- 2) período de serviço aberto para quem está online agora (o gatilho só
--    apanha as passagens offline->online a partir de hoje)
insert into public.tvde_driver_work_log (driver_user_id, inicio)
select d.user_id, now() from public.drivers d
 where d.vehicle_type = 'carro_passageiros' and d.is_online and d.user_id is not null
   and d.last_heartbeat_at > now() - interval '10 minutes'
on conflict (driver_user_id) where fim is null do nothing;
-- 3) estado de conformidade de cada motorista (mestre desligado: não envia avisos)
select public.tvde_conformidade_diaria();
-- 4) relatórios AMT dos meses com corridas
select public.tvde_amt_relatorio_gerar(m::date)
  from generate_series(date_trunc('month', (select min(created_at) from public.tvde_rides)),
                       date_trunc('month', now()), interval '1 month') m;
