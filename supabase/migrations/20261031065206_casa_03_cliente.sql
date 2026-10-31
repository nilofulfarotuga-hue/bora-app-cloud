-- Casa & Manutenção — parte 3: funções do cliente.
-- Dinheiro: o preço sai SEMPRE do servidor (catálogo × quantidade, ou o orçamento aceite).
-- Cartão e MB Way: recusados nesta fase com 'pagamento_cartao_indisponivel' (proposta à parte).
-- Dinheiro em mão só até max_cash_amount_cents (decisão 3 do Danilo).

CREATE OR REPLACE FUNCTION public.casa_config()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'visivel', public._casa_visivel(),
    'enabled', public._casa_bool('casa_enabled', false),
    'valores_autorizados', public._casa_valores_validos(),
    'pagamento_cartao', false,
    'max_cash_cents', public._casa_int('max_cash_amount_cents', 4000),
    'max_fotos', public._casa_int('casa_max_fotos', 5),
    'min_lead_hours', public._casa_int('casa_min_lead_hours', 2),
    'cancel_free_hours', public._casa_int('casa_cancel_free_hours', 12),
    'cancel_half_hours', public._casa_int('casa_cancel_half_hours', 2),
    'garantia_dias', public._casa_int('casa_garantia_dias', 7),
    'quote_max_pros', public._casa_int('casa_quote_max_pros', 3),
    'oficios', COALESCE((SELECT jsonb_agg(jsonb_build_object('codigo', o.codigo, 'nome', o.nome,
                 'descricao', o.descricao, 'fase', o.fase, 'documento_exigido', o.documento_exigido,
                 'ativo', o.ativo) ORDER BY o.ordem) FROM casa_oficios o), '[]'::jsonb),
    'servicos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'oficio', s.oficio, 'nome', s.nome,
                 'descricao', s.descricao, 'modo', s.modo, 'preco_cents', s.preco_cents, 'unidade', s.unidade,
                 'min_quantidade', s.min_quantidade, 'max_quantidade', s.max_quantidade,
                 'duracao_min', s.duracao_min, 'perguntas', s.perguntas) ORDER BY o.ordem, s.ordem)
                 FROM casa_servicos s JOIN casa_oficios o ON o.codigo = s.oficio AND o.ativo
                WHERE s.ativo), '[]'::jsonb))
$$;

CREATE OR REPLACE FUNCTION public.casa_criar_pedido(
  p_servico_id uuid, p_quantidade numeric, p_descricao text, p_respostas jsonb,
  p_address_street text, p_address_city text, p_address_postal text,
  p_lat double precision, p_lng double precision, p_scheduled_at timestamptz,
  p_payment_method text, p_idempotency_key text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  s casa_servicos;
  v_id uuid;
  v_qtd numeric;
  v_preco int;
  v_metodo text;
  v_teste boolean;
  v_estado text;
  v_dur int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF NOT public._casa_visivel() THEN RAISE EXCEPTION 'casa_desligada'; END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_id FROM casa_pedidos WHERE client_user_id = v_uid AND idempotency_key = p_idempotency_key;
    IF v_id IS NOT NULL THEN RETURN public._casa_pedido_json(v_id, 'cliente'); END IF;
  END IF;

  SELECT sv.* INTO s FROM casa_servicos sv JOIN casa_oficios o ON o.codigo = sv.oficio AND o.ativo
   WHERE sv.id = p_servico_id AND sv.ativo;
  IF s.id IS NULL THEN RAISE EXCEPTION 'servico_indisponivel'; END IF;
  IF NULLIF(btrim(COALESCE(p_address_street, '')), '') IS NULL THEN RAISE EXCEPTION 'morada_em_falta'; END IF;
  IF p_scheduled_at IS NULL
     OR p_scheduled_at < now() + make_interval(hours => public._casa_int('casa_min_lead_hours', 2)) THEN
    RAISE EXCEPTION 'antecedencia_minima';
  END IF;

  -- Com a categoria desligada só a vê quem testa: o pedido fica marcado como teste.
  v_teste := NOT public._casa_bool('casa_enabled', false) OR public._casa_testador(v_uid);
  IF NOT v_teste AND NOT public._casa_valores_validos() THEN RAISE EXCEPTION 'valores_por_autorizar'; END IF;

  IF s.modo = 'orcamento' THEN
    v_qtd := 1; v_preco := 0; v_metodo := 'cash'; v_estado := 'orcamentos'; v_dur := s.duracao_min;
  ELSE
    v_qtd := COALESCE(p_quantidade, s.min_quantidade);
    IF v_qtd < s.min_quantidade OR v_qtd > s.max_quantidade THEN RAISE EXCEPTION 'quantidade_invalida'; END IF;
    v_preco := round(s.preco_cents * v_qtd)::int;
    v_metodo := COALESCE(p_payment_method, 'cash');
    IF v_metodo NOT IN ('cash','card','mbway') THEN RAISE EXCEPTION 'metodo_invalido'; END IF;
    IF v_metodo IN ('card','mbway') THEN RAISE EXCEPTION 'pagamento_cartao_indisponivel'; END IF;
    IF v_preco > public._casa_int('max_cash_amount_cents', 4000) THEN RAISE EXCEPTION 'dinheiro_acima_do_limite'; END IF;
    v_estado := 'procura';
    v_dur := CASE WHEN s.unidade = 'hora' THEN (v_qtd * 60)::int
                  WHEN s.unidade = 'movel' THEN (s.duracao_min * v_qtd)::int
                  ELSE s.duracao_min END;
  END IF;

  INSERT INTO casa_pedidos (client_user_id, servico_id, oficio, modo, quantidade, descricao, respostas,
                            address_street, address_city, address_postal, lat, lng, scheduled_at, duracao_min,
                            estado, payment_method, payment_status, preco_cents, total_cents,
                            is_test_order, idempotency_key)
  VALUES (v_uid, s.id, s.oficio, s.modo, v_qtd, left(COALESCE(p_descricao, ''), 2000), COALESCE(p_respostas, '{}'::jsonb),
          btrim(p_address_street), COALESCE(p_address_city, ''), COALESCE(p_address_postal, ''), p_lat, p_lng,
          p_scheduled_at, GREATEST(v_dur, 30), v_estado, v_metodo, 'unpaid', v_preco, v_preco,
          v_teste, p_idempotency_key)
  RETURNING id INTO v_id;

  PERFORM public._casa_evento(v_id, NULL, v_estado, 'client', jsonb_build_object('teste', v_teste));

  BEGIN
    IF v_estado = 'procura' THEN PERFORM public._casa_proxima_oferta(v_id);
    ELSE PERFORM public._casa_convidar(v_id); END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'casa_criar_pedido: oferta falhou (pedido=%): %', v_id, SQLERRM;
  END;

  IF NOT v_teste THEN
    PERFORM public._casa_notificar_admin('Novo pedido Casa',
      (SELECT nome FROM casa_servicos WHERE id = s.id) || ' para '
      || to_char(p_scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
  END IF;
  RETURN public._casa_pedido_json(v_id, 'cliente');
END $$;

CREATE OR REPLACE FUNCTION public.casa_adicionar_foto(p_pedido_id uuid, p_tipo text, p_storage_path text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  p casa_pedidos;
  v_prof uuid;
  v_id uuid;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  IF p.id IS NULL OR v_uid IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  SELECT id INTO v_prof FROM casa_profissionais WHERE user_id = v_uid;

  IF p.client_user_id = v_uid THEN
    IF p_tipo <> 'problema' THEN RAISE EXCEPTION 'tipo_invalido'; END IF;
    IF p.estado IN ('confirmado','cancelado','expirado') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
    IF (SELECT count(*) FROM casa_pedido_fotos WHERE pedido_id = p.id AND tipo = 'problema')
         >= public._casa_int('casa_max_fotos', 5) THEN RAISE EXCEPTION 'limite_fotos'; END IF;
  ELSIF v_prof IS NOT NULL AND p.profissional_id = v_prof THEN
    IF p_tipo NOT IN ('antes','depois','extra') THEN RAISE EXCEPTION 'tipo_invalido'; END IF;
    IF p.estado NOT IN ('aceite','a_caminho','chegou','em_curso','concluido','disputa') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
    IF (SELECT count(*) FROM casa_pedido_fotos WHERE pedido_id = p.id AND tipo = p_tipo) >= 10 THEN
      RAISE EXCEPTION 'limite_fotos';
    END IF;
  ELSE
    RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
  END IF;

  -- Só ficheiros da própria pessoa e deste pedido (nunca apontar para fotos de outros).
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE v_uid::text || '/' || p.id::text || '/%' THEN
    RAISE EXCEPTION 'caminho_invalido';
  END IF;

  INSERT INTO casa_pedido_fotos (pedido_id, tipo, storage_path, enviado_por)
  VALUES (p.id, p_tipo, p_storage_path, v_uid) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_meus_pedidos()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(public._casa_pedido_json(x.id, 'cliente') ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (SELECT id, created_at FROM casa_pedidos WHERE client_user_id = auth.uid()
           ORDER BY created_at DESC LIMIT 100) x
$$;

CREATE OR REPLACE FUNCTION public.casa_pedido(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos; v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  IF p.id IS NULL OR v_uid IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.client_user_id = v_uid THEN RETURN public._casa_pedido_json(p.id, 'cliente'); END IF;
  IF p.profissional_id IS NOT NULL
     AND p.profissional_id = (SELECT id FROM casa_profissionais WHERE user_id = v_uid) THEN
    RETURN public._casa_pedido_json(p.id, 'profissional');
  END IF;
  IF public.is_admin() THEN RETURN public._casa_pedido_json(p.id, 'admin'); END IF;
  RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
END $$;

CREATE OR REPLACE FUNCTION public.casa_aceitar_orcamento(p_orcamento_id uuid, p_payment_method text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  q casa_orcamentos;
  p casa_pedidos;
  v_metodo text := COALESCE(p_payment_method, 'cash');
  v_pct numeric;
  r record;
BEGIN
  SELECT * INTO q FROM casa_orcamentos WHERE id = p_orcamento_id FOR UPDATE;
  IF q.id IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  SELECT * INTO p FROM casa_pedidos WHERE id = q.pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado <> 'orcamentos' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF q.estado <> 'enviado' OR q.expira_em < now() THEN RAISE EXCEPTION 'orcamento_expirado'; END IF;
  IF v_metodo NOT IN ('cash','card','mbway') THEN RAISE EXCEPTION 'metodo_invalido'; END IF;
  IF v_metodo IN ('card','mbway') THEN RAISE EXCEPTION 'pagamento_cartao_indisponivel'; END IF;
  IF q.preco_cents + p.extras_cents > public._casa_int('max_cash_amount_cents', 4000) THEN
    RAISE EXCEPTION 'dinheiro_acima_do_limite';
  END IF;
  IF NOT public._casa_disponivel(q.profissional_id, p.scheduled_at, COALESCE(q.duracao_min, p.duracao_min), p.id) THEN
    RAISE EXCEPTION 'profissional_ocupado';
  END IF;

  v_pct := public._casa_pct_do(q.profissional_id);
  UPDATE casa_pedidos
     SET estado = 'aceite', profissional_id = q.profissional_id, orcamento_aceite_id = q.id,
         preco_cents = q.preco_cents, total_cents = q.preco_cents + extras_cents,
         duracao_min = COALESCE(q.duracao_min, duracao_min), payment_method = v_metodo,
         accepted_at = now(), comissao_pct = v_pct
   WHERE id = p.id;
  UPDATE casa_orcamentos SET estado = 'aceite', decidido_em = now() WHERE id = q.id;
  UPDATE casa_ofertas SET resposta = 'aceite', respondida_em = now()
   WHERE pedido_id = p.id AND profissional_id = q.profissional_id AND tipo = 'convite_orcamento';
  PERFORM public._casa_evento(p.id, 'orcamentos', 'aceite', 'client',
                              jsonb_build_object('orcamento_id', q.id, 'preco_cents', q.preco_cents));

  PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = q.profissional_id),
    'handyman', 'casa_status', 'Orçamento aceite',
    'O cliente aceitou o teu orçamento para ' || to_char(p.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
    || ' — ganhas ' || replace(to_char((q.preco_cents - round(q.preco_cents * v_pct / 100.0)) / 100.0, 'FM999990.00'), '.', ',') || ' €.',
    p.id);

  FOR r IN SELECT o.id, c.user_id FROM casa_orcamentos o JOIN casa_profissionais c ON c.id = o.profissional_id
            WHERE o.pedido_id = p.id AND o.id <> q.id AND o.estado = 'enviado' LOOP
    UPDATE casa_orcamentos SET estado = 'recusado', decidido_em = now() WHERE id = r.id;
    PERFORM public._casa_notificar(r.user_id, 'handyman', 'casa_status', 'Orçamento não escolhido',
      'O cliente escolheu outro orçamento. Obrigado por responderes.', p.id);
  END LOOP;
  RETURN public._casa_pedido_json(p.id, 'cliente');
END $$;

CREATE OR REPLACE FUNCTION public.casa_responder_extra(p_extra_id uuid, p_aceitar boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE e casa_extras; p casa_pedidos;
BEGIN
  SELECT * INTO e FROM casa_extras WHERE id = p_extra_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  SELECT * INTO p FROM casa_pedidos WHERE id = e.pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF e.estado <> 'pedido' OR p.estado NOT IN ('aceite','a_caminho','chegou','em_curso') THEN
    RAISE EXCEPTION 'estado_invalido';
  END IF;
  IF p_aceitar THEN
    IF p.payment_method IN ('card','mbway') THEN RAISE EXCEPTION 'pagamento_cartao_indisponivel'; END IF;
    IF p.total_cents + e.valor_cents > public._casa_int('max_cash_amount_cents', 4000) THEN
      RAISE EXCEPTION 'dinheiro_acima_do_limite';
    END IF;
    UPDATE casa_extras SET estado = 'aceite', respondido_em = now() WHERE id = e.id;
    UPDATE casa_pedidos SET extras_cents = extras_cents + e.valor_cents, total_cents = total_cents + e.valor_cents
     WHERE id = p.id;
  ELSE
    UPDATE casa_extras SET estado = 'recusado', respondido_em = now() WHERE id = e.id;
  END IF;
  PERFORM public._casa_evento(p.id, p.estado, p.estado, 'client',
    jsonb_build_object('extra_id', e.id, 'aceite', p_aceitar, 'valor_cents', e.valor_cents));
  PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
    'handyman', 'casa_status', CASE WHEN p_aceitar THEN 'Valor extra aceite' ELSE 'Valor extra recusado' END,
    CASE WHEN p_aceitar THEN 'O cliente aceitou o valor extra.' ELSE 'O cliente não aceitou o valor extra.' END, p.id);
  RETURN public._casa_pedido_json(p.id, 'cliente');
END $$;

-- Confirmação (pelo cliente ou sozinha ao fim de casa_auto_confirm_hours): a percentagem do Bora
-- calcula-se aqui, só em serviço concluído (decisão 2).
CREATE OR REPLACE FUNCTION public._casa_confirmar(p_pedido_id uuid, p_auto boolean)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos; v_pct numeric; v_com int;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.id IS NULL OR p.estado <> 'concluido' THEN RETURN; END IF;
  v_pct := COALESCE(p.comissao_pct, public._casa_pct_do(p.profissional_id), 0);
  v_com := round(p.total_cents * v_pct / 100.0)::int;
  UPDATE casa_pedidos
     SET estado = 'confirmado', confirmed_at = now(), comissao_pct = v_pct, comissao_cents = v_com,
         ganho_cents = total_cents - v_com,
         payment_status = CASE WHEN payment_method = 'cash' THEN 'cash_pending'
                               WHEN payment_status = 'held' THEN 'released' ELSE payment_status END
   WHERE id = p.id;
  UPDATE casa_profissionais SET jobs_done = jobs_done + 1 WHERE id = p.profissional_id;
  PERFORM public._casa_evento(p.id, 'concluido', 'confirmado', CASE WHEN p_auto THEN 'sistema' ELSE 'client' END);
  PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
    'handyman', 'casa_status', 'Trabalho confirmado',
    'O trabalho ficou confirmado — ganhas ' || replace(to_char((p.total_cents - v_com) / 100.0, 'FM999990.00'), '.', ',') || ' €.', p.id);
  IF p_auto THEN
    PERFORM public._casa_notificar(p.client_user_id, 'client', 'casa_status', 'Trabalho concluído',
      'Demos o trabalho por concluído. Se algo não ficou bem, ainda podes pedir para refazer.', p.id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.casa_confirmar_conclusao(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado <> 'concluido' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  PERFORM public._casa_confirmar(p.id, false);
  RETURN public._casa_pedido_json(p.id, 'cliente');
END $$;

CREATE OR REPLACE FUNCTION public.casa_pedir_refazer(p_pedido_id uuid, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado NOT IN ('concluido','confirmado') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF p.estado = 'confirmado'
     AND now() > p.confirmed_at + make_interval(days => public._casa_int('casa_garantia_dias', 7)) THEN
    RAISE EXCEPTION 'garantia_terminou';
  END IF;
  UPDATE casa_pedidos SET estado = 'disputa', refazer_pedido_em = now(), refazer_motivo = left(COALESCE(p_motivo, ''), 1000)
   WHERE id = p.id;
  PERFORM public._casa_evento(p.id, p.estado, 'disputa', 'client', jsonb_build_object('motivo', p_motivo));
  PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
    'handyman', 'casa_status', 'Pedido para refazer', 'O cliente pediu para rever o trabalho. O Bora vai contactar-te.', p.id);
  PERFORM public._casa_notificar_admin('Casa: pedido para refazer', 'Pedido ' || p.id || ': ' || COALESCE(p_motivo, ''));
  RETURN public._casa_pedido_json(p.id, 'cliente');
END $$;

CREATE OR REPLACE FUNCTION public.casa_avaliar(p_pedido_id uuid, p_nota integer, p_comentario text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  -- Avaliação só de quem pagou: o trabalho tem de estar confirmado.
  IF p.estado <> 'confirmado' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF p.rating_cliente IS NOT NULL THEN RAISE EXCEPTION 'ja_avaliado'; END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'nota_invalida'; END IF;
  UPDATE casa_pedidos SET rating_cliente = p_nota, comentario_cliente = left(COALESCE(p_comentario, ''), 1000) WHERE id = p.id;
  UPDATE casa_profissionais c
     SET ratings_count = x.n, rating_avg = round(x.m, 2)
    FROM (SELECT count(*)::int n, avg(rating_cliente)::numeric m FROM casa_pedidos
           WHERE profissional_id = p.profissional_id AND rating_cliente IS NOT NULL) x
   WHERE c.id = p.profissional_id;
  RETURN jsonb_build_object('ok', true);
END $$;

-- Cancelamento por escalões (tempos nas definições): grátis, metade ou tudo.
CREATE OR REPLACE FUNCTION public._casa_custo_cancelar(p casa_pedidos)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_horas numeric;
BEGIN
  IF p.profissional_id IS NULL THEN RETURN jsonb_build_object('cancel_fee_cents', 0, 'escalao', 'gratis'); END IF;
  v_horas := extract(epoch FROM (p.scheduled_at - now())) / 3600.0;
  IF v_horas >= public._casa_int('casa_cancel_free_hours', 12) THEN
    RETURN jsonb_build_object('cancel_fee_cents', 0, 'escalao', 'gratis');
  ELSIF v_horas >= public._casa_int('casa_cancel_half_hours', 2) THEN
    RETURN jsonb_build_object('cancel_fee_cents', round(p.total_cents * 0.5)::int, 'escalao', 'metade');
  END IF;
  RETURN jsonb_build_object('cancel_fee_cents', p.total_cents, 'escalao', 'total');
END $$;

CREATE OR REPLACE FUNCTION public.casa_cancelar_simulacao(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado NOT IN ('aguarda_pagamento','procura','orcamentos','aceite','a_caminho','chegou') THEN
    RAISE EXCEPTION 'estado_invalido';
  END IF;
  RETURN public._casa_custo_cancelar(p);
END $$;

CREATE OR REPLACE FUNCTION public.casa_cancelar(p_pedido_id uuid, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos; v_custo jsonb; v_fee int;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado NOT IN ('aguarda_pagamento','procura','orcamentos','aceite','a_caminho','chegou') THEN
    RAISE EXCEPTION 'estado_invalido';
  END IF;
  v_custo := public._casa_custo_cancelar(p);
  v_fee := (v_custo ->> 'cancel_fee_cents')::int;
  UPDATE casa_pedidos
     SET estado = 'cancelado', cancelled_at = now(), cancelled_by = 'client',
         cancel_reason = left(COALESCE(p_motivo, ''), 500), cancel_fee_cents = v_fee,
         offer_profissional_id = NULL, offer_expires_at = NULL,
         reembolso_pendente = (payment_status = 'held' AND v_fee < total_cents)
   WHERE id = p.id;
  UPDATE casa_orcamentos SET estado = 'recusado', decidido_em = now() WHERE pedido_id = p.id AND estado = 'enviado';
  UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now() WHERE pedido_id = p.id AND resposta IS NULL;
  PERFORM public._casa_evento(p.id, p.estado, 'cancelado', 'client', v_custo || jsonb_build_object('motivo', p_motivo));
  IF p.profissional_id IS NOT NULL THEN
    PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
      'handyman', 'casa_status', 'Trabalho cancelado',
      'O cliente cancelou o trabalho de ' || to_char(p.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') || '.', p.id);
  END IF;
  RETURN jsonb_build_object('ok', true, 'cancel_fee_cents', v_fee, 'escalao', v_custo ->> 'escalao');
END $$;

-- Chat: só com contacto aberto (aceite e pago); o admin vê e fala sempre.
CREATE OR REPLACE FUNCTION public._casa_papel_no_pedido(p casa_pedidos)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p.client_user_id = auth.uid() THEN 'client'
    WHEN p.profissional_id IS NOT NULL
         AND p.profissional_id = (SELECT id FROM casa_profissionais WHERE user_id = auth.uid()) THEN 'handyman'
    WHEN public.is_admin() THEN 'admin'
  END
$$;

CREATE OR REPLACE FUNCTION public.casa_enviar_mensagem(p_pedido_id uuid, p_texto text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos; v_papel text; v_id uuid; v_txt text := btrim(COALESCE(p_texto, ''));
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  v_papel := public._casa_papel_no_pedido(p);
  IF p.id IS NULL OR v_papel IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF v_papel <> 'admin' AND NOT public._casa_pode_contactar(p) THEN RAISE EXCEPTION 'contacto_fechado'; END IF;
  IF length(v_txt) = 0 OR length(v_txt) > 2000 THEN RAISE EXCEPTION 'mensagem_invalida'; END IF;
  INSERT INTO casa_mensagens (pedido_id, sender_role, message) VALUES (p.id, v_papel, v_txt) RETURNING id INTO v_id;
  IF v_papel <> 'client' THEN
    PERFORM public._casa_notificar(p.client_user_id, 'client', 'casa_status', 'Nova mensagem', left(v_txt, 120), p.id);
  END IF;
  IF v_papel <> 'handyman' AND p.profissional_id IS NOT NULL THEN
    PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
      'handyman', 'casa_status', 'Nova mensagem', left(v_txt, 120), p.id);
  END IF;
  RETURN jsonb_build_object('id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_mensagens(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id;
  IF p.id IS NULL OR public._casa_papel_no_pedido(p) IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', m.id, 'sender_role', m.sender_role,
                     'message', m.message, 'created_at', m.created_at) ORDER BY m.created_at)
                   FROM casa_mensagens m WHERE m.pedido_id = p.id), '[]'::jsonb);
END $$;

-- As leituras de definições aceitam qualquer chave: fechadas a quem chama de fora, senão o erro de
-- conversão de uma chave secreta devolvia o valor na mensagem. Só as funções do servidor as usam.
REVOKE ALL ON FUNCTION public._casa_int(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_num(text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_bool(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_valores_validos() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_testador(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_visivel() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_prof_atual() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_pct_do(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_selos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_confirmar(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_custo_cancelar(casa_pedidos) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_papel_no_pedido(casa_pedidos) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.casa_criar_pedido(uuid, numeric, text, jsonb, text, text, text, double precision, double precision, timestamptz, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_adicionar_foto(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_meus_pedidos() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_pedido(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_aceitar_orcamento(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_responder_extra(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_confirmar_conclusao(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_pedir_refazer(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_avaliar(uuid, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_cancelar_simulacao(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_cancelar(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_enviar_mensagem(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_mensagens(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.casa_config() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.casa_criar_pedido(uuid, numeric, text, jsonb, text, text, text, double precision, double precision, timestamptz, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_adicionar_foto(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_meus_pedidos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_pedido(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_aceitar_orcamento(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_responder_extra(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_confirmar_conclusao(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_pedir_refazer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_avaliar(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_cancelar_simulacao(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_cancelar(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_enviar_mensagem(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_mensagens(uuid) TO authenticated;