-- Prova do saco para viagem (missão saco-viagem-2026-11-20), SEM deixar rasto:
-- corre a migração 20261120122800 + o fluxo do estafeta numa só transação e
-- acaba com RAISE EXCEPTION -> tudo desfeito (migração, pedido de prova,
-- talão, pedidos à rede do pg_net). Cola-se a seguir ao conteúdo da migração.
DO $prova$
DECLARE
  v_rui  uuid := '320d716e-0dd8-4c7f-a5e7-009426319efd';  -- "Rui Teste E2E"
  v_base text := '3a1bbaa2-bfac-41df-ab29-27c709dfae2a';  -- McDonald's, dinheiro
  v_id   text := 'prova-saco-viagem-' || to_char(clock_timestamp(), 'HH24MISS');
  v_id2  text := 'prova-saco-app-antiga-' || to_char(clock_timestamp(), 'HH24MISS');
  r_reg jsonb; r_sem text; r_marca jsonb; r_fecho jsonb; r_antiga jsonb; r_draft jsonb;
  r_desfaz jsonb; r_sem2 text;
BEGIN
  INSERT INTO public.orders
  SELECT (jsonb_populate_record(NULL::public.orders, to_jsonb(o) || jsonb_build_object(
      'id', x.id, 'status', 'driverAccepted', 'is_purchase_finalized', false,
      'assigned_driver_id', v_rui::text, 'current_driver_offer_id', NULL,
      'final_purchase_value', NULL, 'purchase_flow_version', NULL,
      'delivered_at', NULL, 'created_at', now()))).*
    FROM public.orders o, (VALUES (v_id), (v_id2)) x(id)
   WHERE o.id = v_base;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_rui, 'role', 'authenticated')::text, true);

  -- 1) App nova abre a lista: regista que o pedido pede saco.
  r_reg := public.estafeta_saco_viagem(v_id, NULL);
  -- 2) Tenta fechar SEM marcar o saco -> o servidor tem de recusar.
  BEGIN
    PERFORM public.finalizar_talao_nao_parceiro(v_id, 'prova/saco.jpg', 1290, '[]'::jsonb, NULL);
    r_sem := 'ACEITOU (ERRO DA PROVA)';
  EXCEPTION WHEN OTHERS THEN r_sem := SQLERRM; END;
  -- 3) Marca, desfaz e volta a tentar -> recusa outra vez.
  r_marca  := public.estafeta_saco_viagem(v_id, true);
  r_desfaz := public.estafeta_saco_viagem(v_id, false);
  BEGIN
    PERFORM public.finalizar_talao_nao_parceiro(v_id, 'prova/saco.jpg', 1290, '[]'::jsonb, NULL);
    r_sem2 := 'ACEITOU (ERRO DA PROVA)';
  EXCEPTION WHEN OTHERS THEN r_sem2 := SQLERRM; END;
  -- 4) "Comprei o saco" -> fecha.
  r_marca := public.estafeta_saco_viagem(v_id, true);
  r_fecho := public.finalizar_talao_nao_parceiro(v_id, 'prova/saco.jpg', 1290, '[]'::jsonb, NULL);
  SELECT to_jsonb(d) - 'itens' - 'extras' INTO r_draft
    FROM public.order_purchase_drafts d WHERE d.order_id = v_id;
  -- 5) Pedido tratado pela app antiga (nunca registou o saco): não fica preso.
  r_antiga := public.finalizar_talao_nao_parceiro(v_id2, 'prova/saco.jpg', 1290, '[]'::jsonb, NULL);

  RAISE EXCEPTION 'PROVA_SACO %', jsonb_build_object(
    '1_registo', r_reg,
    '2_fechar_sem_saco', r_sem,
    '3_desfazer', r_desfaz, '3_fechar_depois_de_desfazer', r_sem2,
    '4_marca', r_marca,
    '4_fecho_ok', r_fecho->'ok', '4_status', r_fecho->'status',
    '4_bag_count', r_fecho->'bag_count', '4_bag_fee_cents', r_fecho->'bag_fee_cents',
    '4_reembolso', r_fecho->'reimbursement_status',
    '4_rascunho', r_draft,
    '5_app_antiga_ok', r_antiga->'ok', '5_status', r_antiga->'status');
END
$prova$;
