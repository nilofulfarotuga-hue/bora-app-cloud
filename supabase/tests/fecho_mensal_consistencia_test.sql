-- supabase/tests/fecho_mensal_consistencia_test.sql
-- Missão fecho-contabilista-2026-11-10 (bloco D3). Teste só de leitura: FALHA (raise exception) se, em
-- algum mês desde setembro/2026 até ao mês corrente,
--   (1) a soma das rubricas da receita própria ≠ receita própria da Bora, ou
--   (2) pago pelos clientes − mercadoria − estafetas ≠ sobra (lucro) do fecho.
-- Corre contra a base com:
--   supabase db query --linked --project-ref <ref> --agent no --output-format json --yes -f supabase/tests/fecho_mensal_consistencia_test.sql
-- Não escreve nada (a única mudança é set_config local à transação, para correr como servidor).
do $$
declare
  v_ano int := 2026; v_mes int := 9;
  v_fim_ano int := extract(year from (now() at time zone 'Europe/Lisbon'))::int;
  v_fim_mes int := extract(month from (now() at time zone 'Europe/Lisbon'))::int;
  f jsonb; v_soma numeric; v_rec numeric; v_pago numeric; v_merc numeric; v_est numeric; v_lucro numeric;
  v_falhas text := '';
  v_n int := 0;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  while (v_ano, v_mes) <= (v_fim_ano, v_fim_mes) loop
    f := public.admin_monthly_closeout(v_ano, v_mes);
    select coalesce(sum(value::numeric), 0) into v_soma from jsonb_each_text(f->'para_as_financas'->'rubricas');
    v_rec := (f->'totais'->>'receita_propria_bora')::numeric;
    v_pago := (f->'totais'->>'pago_pelos_clientes')::numeric;
    v_merc := (f->'totais'->>'custo_mercadoria')::numeric;
    v_est := (f->'totais'->>'pago_a_estafetas')::numeric;
    v_lucro := (f->'totais'->>'lucro')::numeric;
    if abs(v_soma - v_rec) >= 0.01 then
      v_falhas := v_falhas || format(' | %s-%s: soma das rubricas %s ≠ receita própria %s', v_ano, lpad(v_mes::text, 2, '0'), v_soma, v_rec);
    end if;
    if abs(v_pago - v_merc - v_est - v_lucro) >= 0.01 then
      v_falhas := v_falhas || format(' | %s-%s: pago %s − mercadoria %s − estafetas %s ≠ sobra %s',
                                     v_ano, lpad(v_mes::text, 2, '0'), v_pago, v_merc, v_est, v_lucro);
    end if;
    v_n := v_n + 1;
    if v_mes = 12 then v_ano := v_ano + 1; v_mes := 1; else v_mes := v_mes + 1; end if;
  end loop;
  if v_falhas <> '' then
    raise exception 'FECHO INCONSISTENTE%', v_falhas;
  end if;
  raise notice 'fecho consistente em % mês(es)', v_n;
end $$;
select 'fecho_mensal_consistencia_test: OK' as resultado;
