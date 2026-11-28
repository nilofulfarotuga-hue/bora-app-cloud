-- Missão limpeza-planos-fecho-2026-11-28 — fecho das permissões do Bloco B.
-- JÁ APLICADA no servidor pela Claude.ai (versão 20261128161521), logo depois de 20261128161413.
-- Porquê: o Supabase dá EXECUTE a authenticated por defeito às funções novas; a 20261128161413 só tirava
-- PUBLIC e anon, e as funções do robô/servidor ficavam chamáveis por qualquer cliente com sessão.
-- Aqui: revoke all from public, anon, authenticated + grant execute to service_role, para todas as
-- funções internas e do servidor dos planos. As da app (cleaning_plan_create/mine/skip/change_*/cancel/
-- visit_info e admin_*) continuam com EXECUTE para authenticated.
DO $g$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public._cleaning_plan_dias_ok(text, integer[])',
    'public._cleaning_plan_hora(text)',
    'public._cleaning_plan_visitas_mes(text, integer)',
    'public._cleaning_plan_vaga(public.cleaning_plans, integer)',
    'public._cleaning_plan_visita_confirmada(uuid)',
    'public._cleaning_plan_pago(uuid)',
    'public._cleaning_plan_euro(integer)',
    'public._cleaning_plan_quando(timestamptz)',
    'public._cleaning_plan_json(uuid)',
    'public._cleaning_plan_cancel_visit(uuid, text, text)',
    'public._cleaning_plan_soltar_da_cobranca(uuid)',
    'public._cleaning_plan_devolver(uuid, text, text, integer)',
    'public._trg_cleaning_plan_visita_caiu()',
    'public._trg_cleaning_plan_profissional_fixa()',
    'public._cleaning_plan_gerar_visitas(uuid)',
    'public.cleaning_plan_generate()',
    'public._cleaning_plan_do_cliente(uuid, text[])',
    'public._cleaning_plan_refazer(uuid, text)',
    'public.cleaning_plan_card_saved(uuid, uuid, text, text, text, text, integer, integer)',
    'public._cleaning_plan_marcar_pago(uuid, text, text, text)',
    'public._cleaning_plan_arrumar()',
    'public.cleaning_plan_charges_due(integer)',
    'public.cleaning_plan_charge_result(uuid, integer, text, text, text, text, text)',
    'public.cleaning_plan_webhook_payment(uuid, text, text, integer, text, text)',
    'public.cleaning_plan_action_charge(uuid, uuid)',
    'public.cleaning_plan_refunds_due(integer)',
    'public.cleaning_plan_refund_result(uuid, boolean, text, text)',
    'public._admin_cleaning_plan_linha(public.cleaning_plans)',
    'public._cleaning_plan_chamar_cobranca()']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $g$;
