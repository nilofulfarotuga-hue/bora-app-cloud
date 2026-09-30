-- tvde-conformidade-lei-59-2026 · correção achada na prova web — 2026-09-30
-- A página de fiscalização mostrava o período "25/09 01:00 a 01/10 01:00":
-- os limites dos dias eram meia-noite UTC. Passam a ser meia-noite de Lisboa.
-- Só se trocam as duas linhas dos limites; o resto da função fica igual.
do $patch$
declare v_def text; v_new text;
  v_de_old text := $q$v_de timestamptz := coalesce((p_escopo->>'desde')::date, (now() - interval '30 days')::date)::timestamptz;$q$;
  v_ate_old text := $q$v_ate timestamptz := (coalesce((p_escopo->>'ate')::date, (now() at time zone 'Europe/Lisbon')::date) + 1)::timestamptz;$q$;
  v_de_new text := $q$v_de timestamptz := (coalesce((p_escopo->>'desde')::date, (now() at time zone 'Europe/Lisbon')::date - 30))::timestamp at time zone 'Europe/Lisbon';$q$;
  v_ate_new text := $q$v_ate timestamptz := (coalesce((p_escopo->>'ate')::date, (now() at time zone 'Europe/Lisbon')::date) + 1)::timestamp at time zone 'Europe/Lisbon';$q$;
begin
  v_def := pg_get_functiondef('public._tvde_fiscal_dados(jsonb)'::regprocedure);
  if position(v_de_old in v_def) = 0 or position(v_ate_old in v_def) = 0 then
    raise exception 'âncoras não encontradas — nada mudado';
  end if;
  v_new := replace(replace(v_def, v_de_old, v_de_new), v_ate_old, v_ate_new);
  execute v_new;
  execute 'revoke all on function public._tvde_fiscal_dados(jsonb) from public, anon, authenticated';
end $patch$;
