-- tvde-conformidade-lei-59-2026 · FASE 2 — portão no despacho (ZONA PROTEGIDA)
-- Autorização: Danilo, 30/09/2026 ("eu autorizo"), só para ACRESCENTAR
-- verificações atrás de interruptor, sem mudar a lógica que existe.
--
-- O que muda: uma linha a mais no WHERE dos candidatos
--     AND public.tvde_driver_offer_allowed(d.user_id, <corrida>)
-- em tvde_offer_to_next (os 2 ramos: livres e ocupados) e em
-- tvde_reservation_offer_to_next. Com tvde_compliance_enforce=false a função
-- devolve true na primeira linha, logo o resultado do despacho é o de hoje.
--
-- Não se reescreve o corpo à mão: lê-se a definição que está no ar e
-- acrescenta-se só a linha, com asserções (se a âncora não bater, aborta
-- sem mexer em nada).
do $patch$
declare
  v_def text; v_new text; v_n int;
  v_ancora text := 'AND NOT public.tvde_driver_reservation_locked(d.user_id)';
begin
  -- 1) tvde_offer_to_next — dois ramos
  v_def := pg_get_functiondef('public.tvde_offer_to_next(uuid)'::regprocedure);
  if position('tvde_driver_offer_allowed' in v_def) = 0 then
    v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
    if v_n <> 2 then
      raise exception 'tvde_offer_to_next: esperava 2 âncoras, encontrei %', v_n;
    end if;
    v_new := replace(v_def, v_ancora,
      v_ancora || E'\n      -- 2026-09-30 conformidade TVDE (atrás de interruptor; mestre desligado = true)\n'
               || '      AND public.tvde_driver_offer_allowed(d.user_id, p_ride_id)');
    execute v_new;
  end if;

  -- 2) tvde_reservation_offer_to_next — um ramo
  v_ancora := 'AND NOT (d.user_id = ANY(v_ride.reservation_tried_driver_ids))';
  v_def := pg_get_functiondef('public.tvde_reservation_offer_to_next(uuid)'::regprocedure);
  if position('tvde_driver_offer_allowed' in v_def) = 0 then
    v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
    if v_n <> 1 then
      raise exception 'tvde_reservation_offer_to_next: esperava 1 âncora, encontrei %', v_n;
    end if;
    v_new := replace(v_def, v_ancora,
      v_ancora || E'\n    -- 2026-09-30 conformidade TVDE (atrás de interruptor; mestre desligado = true)\n'
               || '    AND public.tvde_driver_offer_allowed(d.user_id, p_ride_id)');
    execute v_new;
  end if;
end $patch$;
