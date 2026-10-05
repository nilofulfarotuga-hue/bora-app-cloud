-- Ronda 04/10 Bloco B — correcções da revisão de contexto limpo (05/10/2026):
-- (1) admin_set_settlement_state decidia pago/recebido primeiro pelo weekly_digest_log (fica velho depois de
--     reabrir + recalcular) — passa a decidir pelo saldo do próprio acerto; o resumo só se não houver acerto.
-- (2) admin_unmark_settlement e admin_reabrir_acerto achavam a semana só pela data UTC (domingo) — passam a
--     usar public._semana_bate (data de Lisboa OU UTC), como o marcar pago.
-- Remendo por âncora a partir da definição no ar; cada âncora tem de aparecer o nº de vezes esperado.
-- Provas: desfazer as substituições dá a cópia guardada (3/3 iguais); como admin, em transacção desfeita,
-- desmarcar com a segunda de Lisboa (21/09) achou 1 linha e marcar decidiu 'bora_pays' -> 'paid' pelo saldo 96,22.
-- Voltar atrás: execute (select def from bkp_fn_settlement_20261005 where fn = '<funcao>').
create table if not exists public.bkp_fn_settlement_20261005 (fn text primary key, def text, guardado_em timestamptz default now());
alter table public.bkp_fn_settlement_20261005 enable row level security;
revoke all on table public.bkp_fn_settlement_20261005 from public, anon, authenticated;

do $$
declare
  v_def text; v_novo text; v_n int;
  a_dig text := E'  SELECT w.direction INTO v_dir FROM public.weekly_digest_log w\n   WHERE w.subject_type = p_subject_type AND w.subject_id = p_subject_id\n     AND public._semana_bate(w.week_start_at, p_week_start) LIMIT 1;\n  IF v_dir IS NULL THEN\n';
  a_fim text := E'      ELSE NULL END;\n  END IF;\n';
begin
  -- (1)
  v_def := pg_get_functiondef('public.admin_set_settlement_state(text,text,date,text,text)'::regprocedure);
  insert into public.bkp_fn_settlement_20261005 values ('admin_set_settlement_state', v_def) on conflict (fn) do nothing;
  v_n := (length(v_def) - length(replace(v_def, a_dig, ''))) / length(a_dig);
  if v_n <> 1 then raise exception 'ancora digest: % ocorrencias', v_n; end if;
  v_n := (length(v_def) - length(replace(v_def, a_fim, ''))) / length(a_fim);
  if v_n <> 1 then raise exception 'ancora fim do CASE: % ocorrencias', v_n; end if;
  v_novo := replace(v_def, a_dig, E'  -- ronda 04/10 B (revisão): a direcção vem do saldo do próprio acerto; o resumo semanal só se não houver acerto.\n  IF true THEN\n');
  v_novo := replace(v_novo, a_fim, a_fim || E'  IF v_dir IS NULL THEN\n    SELECT w.direction INTO v_dir FROM public.weekly_digest_log w\n     WHERE w.subject_type = p_subject_type AND w.subject_id = p_subject_id\n       AND public._semana_bate(w.week_start_at, p_week_start) LIMIT 1;\n  END IF;\n');
  execute v_novo;

  -- (2a) admin_unmark_settlement: 5 ocorrências
  v_def := pg_get_functiondef('public.admin_unmark_settlement(text,text,date)'::regprocedure);
  insert into public.bkp_fn_settlement_20261005 values ('admin_unmark_settlement', v_def) on conflict (fn) do nothing;
  v_n := (length(v_def) - length(replace(v_def, 'week_start_at::date=p_week_start', ''))) / length('week_start_at::date=p_week_start');
  if v_n <> 5 then raise exception 'unmark: % ocorrencias (esperava 5)', v_n; end if;
  execute replace(v_def, 'week_start_at::date=p_week_start', 'public._semana_bate(week_start_at, p_week_start)');

  -- (2b) admin_reabrir_acerto: 6 ocorrências (5 acertos + resumo semanal)
  v_def := pg_get_functiondef('public.admin_reabrir_acerto(text,text,date,text)'::regprocedure);
  insert into public.bkp_fn_settlement_20261005 values ('admin_reabrir_acerto', v_def) on conflict (fn) do nothing;
  v_n := (length(v_def) - length(replace(v_def, 'week_start_at::date = p_week_start', ''))) / length('week_start_at::date = p_week_start');
  if v_n <> 6 then raise exception 'reabrir: % ocorrencias (esperava 6)', v_n; end if;
  execute replace(v_def, 'week_start_at::date = p_week_start', 'public._semana_bate(week_start_at, p_week_start)');
end $$;
