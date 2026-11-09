-- ════════════════════════════════════════════════════════════════════════════
-- CASA & MANUTENÇÃO — cartão e MB Way pelo caminho da Limpeza (missão m11, 09/11/2026).
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO: só se aplica com o "autorizo" do Danilo.
-- Nasce DESLIGADO (casa_pagamento_app_ativo = false). Idempotente: pode correr 2 vezes.
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 1. Onde fica o pagamento e a devolução ──────────────────────────────────
alter table public.casa_pedidos
  add column if not exists stripe_payment_intent_id text,
  add column if not exists stripe_account text,
  add column if not exists reembolso_ref text,
  add column if not exists reembolso_cents integer,
  add column if not exists reembolsado_em timestamptz;

create unique index if not exists ux_casa_pedidos_payment_intent
  on public.casa_pedidos (stripe_payment_intent_id) where stripe_payment_intent_id is not null;

-- ─── 2. O interruptor (nasce desligado) ──────────────────────────────────────
insert into public.platform_settings (key, value, description, category, is_secret)
values ('casa_pagamento_app_ativo', 'false'::jsonb,
        'Casa: aceitar cartão e MB Way na app (ligar só com o "autorizo" do Danilo)',
        'casa', false)
on conflict (key) do nothing;

-- ─── 3. casa_config: o cartão segue o interruptor ────────────────────────────
create or replace function public.casa_config()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  SELECT jsonb_build_object(
    'visivel', public._casa_visivel(),
    'enabled', public._casa_bool('casa_enabled', false),
    'valores_autorizados', public._casa_valores_validos(),
    'pagamento_cartao', public._casa_bool('casa_pagamento_app_ativo', false),
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
$function$;

-- ─── 4. casa_criar_pedido: cartão/MB Way → 'aguarda_pagamento' ───────────────
create or replace function public.casa_criar_pedido(p_servico_id uuid, p_quantidade numeric, p_descricao text, p_respostas jsonb, p_address_street text, p_address_city text, p_address_postal text, p_lat double precision, p_lng double precision, p_scheduled_at timestamp with time zone, p_payment_method text, p_idempotency_key text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    IF v_metodo IN ('card','mbway') THEN
      -- 09/11 (m11): cartão e MB Way pelo caminho da Limpeza, só com o interruptor ligado.
      IF NOT public._casa_bool('casa_pagamento_app_ativo', false) THEN
        RAISE EXCEPTION 'pagamento_cartao_indisponivel';
      END IF;
      IF v_preco < 50 THEN RAISE EXCEPTION 'valor_abaixo_do_minimo'; END IF;
      v_estado := 'aguarda_pagamento';
    ELSE
      IF v_preco > public._casa_int('max_cash_amount_cents', 4000) THEN RAISE EXCEPTION 'dinheiro_acima_do_limite'; END IF;
      v_estado := 'procura';
    END IF;
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

  -- Pedido por pagar (cartão/MB Way) NÃO vai a ninguém: só depois de casa_pagamento_confirmado.
  BEGIN
    IF v_estado = 'procura' THEN PERFORM public._casa_proxima_oferta(v_id);
    ELSIF v_estado = 'orcamentos' THEN PERFORM public._casa_convidar(v_id); END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'casa_criar_pedido: oferta falhou (pedido=%): %', v_id, SQLERRM;
  END;

  IF NOT v_teste AND v_estado <> 'aguarda_pagamento' THEN
    PERFORM public._casa_notificar_admin('Novo pedido Casa',
      (SELECT nome FROM casa_servicos WHERE id = s.id) || ' para '
      || to_char(p_scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
  END IF;
  RETURN public._casa_pedido_json(v_id, 'cliente');
END $function$;

-- ─── 5. casa_aceitar_orcamento: orçamento pago na app ────────────────────────
create or replace function public.casa_aceitar_orcamento(p_orcamento_id uuid, p_payment_method text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  q casa_orcamentos;
  p casa_pedidos;
  v_metodo text := COALESCE(p_payment_method, 'cash');
  v_pct numeric;
  v_app boolean;
  r record;
BEGIN
  SELECT * INTO q FROM casa_orcamentos WHERE id = p_orcamento_id FOR UPDATE;
  IF q.id IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  SELECT * INTO p FROM casa_pedidos WHERE id = q.pedido_id FOR UPDATE;
  IF p.client_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF p.estado <> 'orcamentos' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF q.estado <> 'enviado' OR q.expira_em < now() THEN RAISE EXCEPTION 'orcamento_expirado'; END IF;
  IF v_metodo NOT IN ('cash','card','mbway') THEN RAISE EXCEPTION 'metodo_invalido'; END IF;
  v_app := v_metodo IN ('card','mbway');
  IF v_app THEN
    IF NOT public._casa_bool('casa_pagamento_app_ativo', false) THEN
      RAISE EXCEPTION 'pagamento_cartao_indisponivel';
    END IF;
    IF q.preco_cents + p.extras_cents < 50 THEN RAISE EXCEPTION 'valor_abaixo_do_minimo'; END IF;
  ELSIF q.preco_cents + p.extras_cents > public._casa_int('max_cash_amount_cents', 4000) THEN
    RAISE EXCEPTION 'dinheiro_acima_do_limite';
  END IF;
  IF NOT public._casa_disponivel(q.profissional_id, p.scheduled_at, COALESCE(q.duracao_min, p.duracao_min), p.id) THEN
    RAISE EXCEPTION 'profissional_ocupado';
  END IF;

  v_pct := public._casa_pct_do(q.profissional_id);
  -- Pago na app: o pedido fica com o profissional escolhido mas 'aguarda_pagamento'; o profissional só é
  -- avisado quando o pagamento ficar retido (casa_pagamento_confirmado). Em dinheiro: como antes.
  UPDATE casa_pedidos
     SET estado = CASE WHEN v_app THEN 'aguarda_pagamento' ELSE 'aceite' END,
         profissional_id = q.profissional_id, orcamento_aceite_id = q.id,
         preco_cents = q.preco_cents, total_cents = q.preco_cents + extras_cents,
         duracao_min = COALESCE(q.duracao_min, duracao_min), payment_method = v_metodo,
         accepted_at = now(), comissao_pct = v_pct
   WHERE id = p.id;
  UPDATE casa_orcamentos SET estado = 'aceite', decidido_em = now() WHERE id = q.id;
  UPDATE casa_ofertas SET resposta = 'aceite', respondida_em = now()
   WHERE pedido_id = p.id AND profissional_id = q.profissional_id AND tipo = 'convite_orcamento';
  PERFORM public._casa_evento(p.id, 'orcamentos', CASE WHEN v_app THEN 'aguarda_pagamento' ELSE 'aceite' END, 'client',
                              jsonb_build_object('orcamento_id', q.id, 'preco_cents', q.preco_cents));

  IF NOT v_app THEN
    PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = q.profissional_id),
      'handyman', 'casa_status', 'Orçamento aceite',
      'O cliente aceitou o teu orçamento para ' || to_char(p.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
      || ' — ganhas ' || replace(to_char((q.preco_cents - round(q.preco_cents * v_pct / 100.0)) / 100.0, 'FM999990.00'), '.', ',') || ' €.',
      p.id);
  END IF;

  FOR r IN SELECT o.id, c.user_id FROM casa_orcamentos o JOIN casa_profissionais c ON c.id = o.profissional_id
            WHERE o.pedido_id = p.id AND o.id <> q.id AND o.estado = 'enviado' LOOP
    UPDATE casa_orcamentos SET estado = 'recusado', decidido_em = now() WHERE id = r.id;
    PERFORM public._casa_notificar(r.user_id, 'handyman', 'casa_status', 'Orçamento não escolhido',
      'O cliente escolheu outro orçamento. Obrigado por responderes.', p.id);
  END LOOP;
  RETURN public._casa_pedido_json(p.id, 'cliente');
END $function$;

-- ─── 6. Cancelar um pedido ainda por pagar é sempre 0 € ──────────────────────
create or replace function public._casa_custo_cancelar(p casa_pedidos)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
DECLARE v_horas numeric;
BEGIN
  IF p.profissional_id IS NULL THEN RETURN jsonb_build_object('cancel_fee_cents', 0, 'escalao', 'gratis'); END IF;
  -- 09/11 (m11): pago na app mas o pagamento ainda não ficou retido → nada a cobrar.
  IF p.estado = 'aguarda_pagamento' THEN RETURN jsonb_build_object('cancel_fee_cents', 0, 'escalao', 'gratis'); END IF;
  v_horas := extract(epoch FROM (p.scheduled_at - now())) / 3600.0;
  IF v_horas >= public._casa_int('casa_cancel_free_hours', 12) THEN
    RETURN jsonb_build_object('cancel_fee_cents', 0, 'escalao', 'gratis');
  ELSIF v_horas >= public._casa_int('casa_cancel_half_hours', 2) THEN
    RETURN jsonb_build_object('cancel_fee_cents', round(p.total_cents * 0.5)::int, 'escalao', 'metade');
  END IF;
  RETURN jsonb_build_object('cancel_fee_cents', p.total_cents, 'escalao', 'total');
END $function$;

-- ─── 7. Valor extra em pedido pago na app: fase 2 ────────────────────────────
create or replace function public.casa_pedir_extra(p_pedido_id uuid, p_valor_cents integer, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos; v_id uuid;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF b.estado NOT IN ('chegou','em_curso') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  -- 09/11 (m11): o cliente pagou na app (cartão/MB Way); cobrar um extra na app fica para a fase 2.
  IF b.payment_method IN ('card','mbway') THEN RAISE EXCEPTION 'extra_indisponivel_pago_na_app'; END IF;
  IF p_valor_cents IS NULL OR p_valor_cents <= 0 OR p_valor_cents > 100000 THEN RAISE EXCEPTION 'preco_invalido'; END IF;
  IF length(btrim(COALESCE(p_motivo, ''))) < 3 THEN RAISE EXCEPTION 'motivo_em_falta'; END IF;
  IF EXISTS (SELECT 1 FROM casa_extras WHERE pedido_id = b.id AND estado = 'pedido') THEN RAISE EXCEPTION 'extra_por_responder'; END IF;
  INSERT INTO casa_extras (pedido_id, valor_cents, motivo, pedido_por)
  VALUES (b.id, p_valor_cents, left(btrim(p_motivo), 500), auth.uid()) RETURNING id INTO v_id;
  PERFORM public._casa_evento(b.id, b.estado, b.estado, 'handyman', jsonb_build_object('extra_id', v_id, 'valor_cents', p_valor_cents));
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Pedido de valor extra',
    replace(to_char(p_valor_cents / 100.0, 'FM999990.00'), '.', ',') || ' € — ' || left(btrim(p_motivo), 100) || '. Aceita ou recusa na app.', b.id);
  RETURN jsonb_build_object('id', v_id);
END $function$;

-- ─── 8. Pagamento confirmado (só o servidor chama) ───────────────────────────
-- Chamada pela Edge casa-checkout (mark_held, depois de ler o pagamento na Stripe) e, depois do remendo,
-- pelo stripe-webhook (a garantia, como na Limpeza). Idempotente. Recusas de negócio voltam ok=false.
create or replace function public.casa_pagamento_confirmado(
  p_pedido_id uuid, p_payment_intent_id text, p_amount_cents integer,
  p_stripe_account text default null, p_origem text default 'casa-checkout')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  p casa_pedidos;
  v_conta text := CASE WHEN p_stripe_account IN ('pessoal','empresa') THEN p_stripe_account ELSE NULL END;
  v_novo text;
  v_pct numeric;
BEGIN
  IF p_payment_intent_id IS NULL OR left(p_payment_intent_id, 3) <> 'pi_' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'pagamento_invalido');
  END IF;
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'pedido_nao_existe'); END IF;
  IF p.payment_method NOT IN ('card','mbway') THEN RETURN jsonb_build_object('ok', false, 'erro', 'nao_e_pago_na_app'); END IF;
  IF p_amount_cents IS DISTINCT FROM p.total_cents THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'valor_diferente', 'esperado', p.total_cents, 'recebido', p_amount_cents);
  END IF;
  IF p.stripe_payment_intent_id IS NOT NULL THEN
    IF p.stripe_payment_intent_id = p_payment_intent_id THEN
      RETURN jsonb_build_object('ok', true, 'ja_estava', true, 'estado', p.estado,
                                'reembolsar', p.reembolso_pendente);
    END IF;
    -- Já há OUTRO pagamento retido neste pedido: este segundo tem de ser devolvido à parte.
    RETURN jsonb_build_object('ok', false, 'erro', 'outro_pagamento_ja_retido');
  END IF;

  IF p.estado = 'aguarda_pagamento' THEN
    v_novo := CASE WHEN p.profissional_id IS NULL THEN 'procura' ELSE 'aceite' END;
    UPDATE casa_pedidos
       SET payment_status = 'held', stripe_payment_intent_id = p_payment_intent_id,
           stripe_account = COALESCE(v_conta, stripe_account), estado = v_novo
     WHERE id = p.id;
    PERFORM public._casa_evento(p.id, 'aguarda_pagamento', v_novo, 'sistema',
                                jsonb_build_object('pagamento', p.payment_method, 'origem', p_origem));
    IF v_novo = 'procura' THEN
      BEGIN
        PERFORM public._casa_proxima_oferta(p.id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'casa_pagamento_confirmado: oferta falhou (pedido=%): %', p.id, SQLERRM;
      END;
    ELSE
      v_pct := COALESCE(p.comissao_pct, public._casa_pct_do(p.profissional_id), 0);
      PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = p.profissional_id),
        'handyman', 'casa_status', 'Orçamento aceite',
        'O cliente aceitou e pagou o teu orçamento para ' || to_char(p.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
        || ' — ganhas ' || replace(to_char((p.total_cents - round(p.total_cents * v_pct / 100.0)) / 100.0, 'FM999990.00'), '.', ',') || ' €.',
        p.id);
    END IF;
    IF NOT p.is_test_order THEN
      PERFORM public._casa_notificar_admin('Novo pedido Casa (pago na app)',
        (SELECT nome FROM casa_servicos WHERE id = p.servico_id) || ' para '
        || to_char(p.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
    END IF;
    RETURN jsonb_build_object('ok', true, 'estado', v_novo);
  END IF;

  -- O pagamento chegou com o pedido já caído (cancelado, ou 30 min sem pagar): fica retido e marcado
  -- para devolver por inteiro (a Edge devolve logo; o painel mostra "reembolso pendente").
  IF p.estado IN ('cancelado','expirado') THEN
    UPDATE casa_pedidos
       SET payment_status = 'held', stripe_payment_intent_id = p_payment_intent_id,
           stripe_account = COALESCE(v_conta, stripe_account), cancel_fee_cents = 0, reembolso_pendente = true
     WHERE id = p.id;
    PERFORM public._casa_evento(p.id, p.estado, p.estado, 'sistema',
                                jsonb_build_object('pagamento_tarde', true, 'origem', p_origem));
    RETURN jsonb_build_object('ok', true, 'estado', p.estado, 'reembolsar', true);
  END IF;

  RETURN jsonb_build_object('ok', false, 'erro', 'estado_inesperado', 'estado', p.estado);
END $function$;

-- ─── 9. Devolução registada (só o servidor chama, depois de a Stripe devolver) ─
create or replace function public.casa_reembolso_registado(
  p_pedido_id uuid, p_refund_ref text, p_valor_cents integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE p casa_pedidos;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'pedido_nao_existe'); END IF;
  IF p.estado NOT IN ('cancelado','expirado') THEN RETURN jsonb_build_object('ok', false, 'erro', 'pedido_nao_cancelado'); END IF;
  IF p.payment_status = 'estornado' THEN RETURN jsonb_build_object('ok', true, 'ja_estava', true); END IF;
  IF p_valor_cents IS NULL OR p_valor_cents < 0 OR p_valor_cents > p.total_cents THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'valor_invalido');
  END IF;
  UPDATE casa_pedidos
     SET payment_status = 'estornado', reembolso_pendente = false, reembolso_ref = left(p_refund_ref, 200),
         reembolso_cents = p_valor_cents, reembolsado_em = now()
   WHERE id = p.id;
  PERFORM public._casa_evento(p.id, p.estado, p.estado, 'sistema',
                              jsonb_build_object('reembolso_cents', p_valor_cents));
  IF p_valor_cents > 0 THEN
    PERFORM public._casa_notificar(p.client_user_id, 'client', 'casa_status', 'Devolução feita',
      'Devolvemos ' || replace(to_char(p_valor_cents / 100.0, 'FM999990.00'), '.', ',')
      || ' € ao teu ' || CASE WHEN p.payment_method = 'mbway' THEN 'MB Way' ELSE 'cartão' END
      || '. Pode levar alguns dias a aparecer.', p.id);
  END IF;
  RETURN jsonb_build_object('ok', true);
END $function$;

-- As duas funções do pagamento só as chama o servidor (Edge com a chave de servidor, webhook).
revoke all on function public.casa_pagamento_confirmado(uuid, text, integer, text, text) from public, anon, authenticated;
revoke all on function public.casa_reembolso_registado(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.casa_pagamento_confirmado(uuid, text, integer, text, text) to service_role;
grant execute on function public.casa_reembolso_registado(uuid, text, integer) to service_role;
