-- Casa & Manutenção — parte 2: ajudantes, avisos, rotação de ofertas e convites para orçar.
-- Contrato: .claude/.ai/provas/casa-manutencao-2026-10-30/ESPEC.md. Definições lidas pelas funções da parte 2a.

CREATE OR REPLACE FUNCTION public._casa_visivel()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT public._casa_bool('casa_enabled', false)
      OR (auth.uid() IS NOT NULL AND (public._casa_testador(auth.uid()) OR public.is_admin()))
$$;

CREATE OR REPLACE FUNCTION public._casa_prof_atual()
 RETURNS public.casa_profissionais LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v public.casa_profissionais;
BEGIN
  SELECT * INTO v FROM casa_profissionais WHERE user_id = auth.uid();
  IF v.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional' USING ERRCODE = '42501'; END IF;
  RETURN v;
END $$;

-- Percentagem do Bora para este profissional: 0 durante a promoção dos primeiros.
CREATE OR REPLACE FUNCTION public._casa_pct_do(p_prof_id uuid)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT CASE WHEN p.sem_comissao_ate IS NOT NULL
                   AND p.sem_comissao_ate >= (now() AT TIME ZONE 'Europe/Lisbon')::date THEN 0
              ELSE public._casa_num('casa_bora_pct', 15) END
    FROM casa_profissionais p WHERE p.id = p_prof_id
$$;

CREATE OR REPLACE FUNCTION public._casa_evento(p_pedido_id uuid, p_de text, p_para text, p_papel text, p_detalhe jsonb DEFAULT '{}'::jsonb)
 RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  INSERT INTO casa_pedido_eventos (pedido_id, estado_de, estado_para, por_user_id, por_papel, detalhe)
  VALUES (p_pedido_id, p_de, p_para, auth.uid(), p_papel, COALESCE(p_detalhe, '{}'::jsonb))
$$;

-- 2) Avisos ----------------------------------------------------------------------------------
-- p_papel: 'handyman' (aparelhos do profissional) ou 'client' (aparelhos do cliente).
-- p_tipo: 'casa_offer' (oferta/convite: toque persistente, só dados) ou 'casa_status'.
CREATE OR REPLACE FUNCTION public._casa_notificar(p_user_id uuid, p_papel text, p_tipo text, p_titulo text, p_corpo text, p_pedido_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_url text; v_key text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(p_user_id, p_tipo, p_titulo, p_corpo, p_pedido_id::text);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_tipo, '_casa_notificar:in_app', SQLERRM);
  END;
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_url IS NULL OR v_key IS NULL THEN
      INSERT INTO notification_failures (user_id, kind, source, erro)
      VALUES (p_user_id, p_tipo, '_casa_notificar:fcm', 'vault project_url/service_role_key em falta');
    ELSE
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-handyman',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
        body := jsonb_build_object('targetUserId', p_user_id::text, 'papel', p_papel,
                                   'bookingId', COALESCE(p_pedido_id::text, ''),
                                   'title', p_titulo, 'body', p_corpo, 'kind', p_tipo, 'type', p_tipo));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_tipo, '_casa_notificar:fcm', SQLERRM);
  END;
END $$;

CREATE OR REPLACE FUNCTION public._casa_notificar_admin(p_titulo text, p_corpo text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_url text; v_key text;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/notify-admin-urgent',
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      body := jsonb_build_object('kind', 'generic', 'ref', 'servico_admin', 'title', p_titulo, 'body', p_corpo, 'source', 'casa'));
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 3) Selos, contacto e o JSON do pedido -------------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_selos(p_prof_id uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH d AS (
    SELECT tipo FROM casa_documentos
     WHERE profissional_id = p_prof_id AND estado = 'approved'
       AND (validade IS NULL OR validade >= (now() AT TIME ZONE 'Europe/Lisbon')::date))
  SELECT to_jsonb(ARRAY(SELECT s FROM (VALUES
      (CASE WHEN EXISTS (SELECT 1 FROM d WHERE tipo = 'cartao_cidadao') THEN 'documentos_verificados' END),
      (CASE WHEN EXISTS (SELECT 1 FROM d WHERE tipo IN ('seguro_acidentes','seguro_rc')) THEN 'seguro' END),
      (CASE WHEN EXISTS (SELECT 1 FROM d WHERE tipo IN ('dgeg_eletricidade','dgeg_gas')) THEN 'dgeg' END),
      (CASE WHEN EXISTS (SELECT 1 FROM d WHERE tipo = 'impic') THEN 'impic' END)) AS t(s) WHERE s IS NOT NULL))
$$;

-- Decisão 4 do Danilo: telefone, chat e ligar só depois de aceite e pago
-- (cartão/MB Way retido; no dinheiro, o trabalho aceite).
CREATE OR REPLACE FUNCTION public._casa_pode_contactar(p public.casa_pedidos)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $$
  SELECT p.profissional_id IS NOT NULL
     AND p.estado IN ('aceite','a_caminho','chegou','em_curso','concluido','disputa')
     AND (p.payment_method = 'cash' OR p.payment_status IN ('held','released'))
$$;

CREATE OR REPLACE FUNCTION public._casa_pessoa_prof(p_prof_id uuid, p_com_telefone boolean)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object('id', p.id, 'name', p.name, 'photo_url', p.photo_url,
           'rating_avg', p.rating_avg, 'ratings_count', p.ratings_count, 'jobs_done', p.jobs_done,
           'selos', public._casa_selos(p.id),
           'phone', CASE WHEN p_com_telefone THEN NULLIF(p.phone, '') END)
    FROM casa_profissionais p WHERE p.id = p_prof_id
$$;

-- p_vista: 'cliente' | 'profissional' | 'admin'
CREATE OR REPLACE FUNCTION public._casa_pedido_json(p_id uuid, p_vista text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  p casa_pedidos;
  v_contacto boolean;
  v_out jsonb;
  v_cli jsonb;
BEGIN
  SELECT * INTO p FROM casa_pedidos WHERE id = p_id;
  IF p.id IS NULL THEN RETURN NULL; END IF;
  v_contacto := public._casa_pode_contactar(p);

  v_out := jsonb_build_object(
    'id', p.id, 'servico_id', p.servico_id,
    'servico_nome', (SELECT s.nome FROM casa_servicos s WHERE s.id = p.servico_id),
    'oficio', p.oficio, 'oficio_nome', (SELECT o.nome FROM casa_oficios o WHERE o.codigo = p.oficio),
    'modo', p.modo, 'quantidade', p.quantidade, 'descricao', p.descricao, 'respostas', p.respostas,
    'morada', jsonb_build_object('street', p.address_street, 'city', p.address_city,
                                 'postal', p.address_postal, 'lat', p.lat, 'lng', p.lng),
    'scheduled_at', p.scheduled_at, 'duracao_min', p.duracao_min, 'estado', p.estado,
    'payment_method', p.payment_method, 'payment_status', p.payment_status,
    'preco_cents', p.preco_cents, 'extras_cents', p.extras_cents, 'total_cents', p.total_cents,
    'is_test', p.is_test_order, 'created_at', p.created_at, 'accepted_at', p.accepted_at,
    'on_the_way_at', p.on_the_way_at, 'arrived_at', p.arrived_at, 'started_at', p.started_at,
    'done_at', p.done_at, 'confirmed_at', p.confirmed_at, 'cancelled_at', p.cancelled_at,
    'cancelled_by', p.cancelled_by, 'cancel_reason', p.cancel_reason, 'cancel_fee_cents', p.cancel_fee_cents,
    'rating_cliente', p.rating_cliente, 'comentario_cliente', p.comentario_cliente,
    'rating_profissional', p.rating_profissional, 'refazer_pedido_em', p.refazer_pedido_em,
    'garantia_ate', CASE WHEN p.confirmed_at IS NOT NULL
                         THEN p.confirmed_at + make_interval(days => public._casa_int('casa_garantia_dias', 7)) END,
    'pode_contactar', v_contacto,
    'fotos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo,
                         'storage_path', f.storage_path, 'created_at', f.created_at) ORDER BY f.created_at)
                       FROM casa_pedido_fotos f WHERE f.pedido_id = p.id), '[]'::jsonb),
    'extras', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'valor_cents', e.valor_cents,
                         'motivo', e.motivo, 'estado', e.estado, 'created_at', e.created_at) ORDER BY e.created_at)
                        FROM casa_extras e WHERE e.pedido_id = p.id), '[]'::jsonb),
    'profissional', CASE WHEN p.profissional_id IS NOT NULL
                         THEN public._casa_pessoa_prof(p.profissional_id, v_contacto OR p_vista = 'admin') END);

  IF p_vista IN ('cliente', 'admin') THEN
    v_out := v_out || jsonb_build_object('orcamentos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', o.id, 'preco_cents', o.preco_cents, 'inclui', o.inclui,
               'materiais', o.materiais, 'materiais_incluidos', o.materiais_incluidos, 'prazo', o.prazo,
               'duracao_min', o.duracao_min, 'estado', o.estado, 'expira_em', o.expira_em,
               'created_at', o.created_at, 'profissional', public._casa_pessoa_prof(o.profissional_id, false))
             ORDER BY o.preco_cents)
        FROM casa_orcamentos o WHERE o.pedido_id = p.id), '[]'::jsonb));
  END IF;

  IF p_vista IN ('profissional', 'admin') THEN
    SELECT jsonb_build_object('nome', COALESCE(NULLIF(u.name, ''), split_part(u.email, '@', 1)),
                              'phone', CASE WHEN v_contacto OR p_vista = 'admin' THEN NULLIF(u.phone, '') END)
      INTO v_cli FROM users u WHERE u.id = p.client_user_id;
    v_out := v_out || jsonb_build_object('ganho_cents',
               CASE WHEN p.ganho_cents > 0 THEN p.ganho_cents
                    WHEN p.profissional_id IS NOT NULL
                      THEN p.total_cents - round(p.total_cents * COALESCE(p.comissao_pct, public._casa_pct_do(p.profissional_id)) / 100.0)::int
               END,
             'cliente', COALESCE(v_cli, jsonb_build_object('nome', 'Cliente')));
  END IF;

  IF p_vista = 'admin' THEN
    v_out := v_out || jsonb_build_object('comissao_cents', p.comissao_cents, 'comissao_pct', p.comissao_pct,
             'reembolso_pendente', p.reembolso_pendente, 'refazer_motivo', p.refazer_motivo,
             'client_user_id', p.client_user_id, 'profissional_id', p.profissional_id,
             'offer_profissional_id', p.offer_profissional_id, 'offer_expires_at', p.offer_expires_at,
             'offer_round', p.offer_round);
  END IF;
  RETURN v_out;
END $$;

-- 4) Quem pode receber este pedido ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_disponivel(p_prof_id uuid, p_start timestamptz, p_duracao_min integer, p_ignorar uuid DEFAULT NULL)
 RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_local timestamp := p_start AT TIME ZONE 'Europe/Lisbon';
  v_fim timestamp := (p_start AT TIME ZONE 'Europe/Lisbon') + make_interval(mins => p_duracao_min);
BEGIN
  IF v_fim::date > v_local::date THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM casa_disponibilidade d
                  WHERE d.profissional_id = p_prof_id
                    AND d.weekday = EXTRACT(dow FROM v_local)::smallint
                    AND d.start_time <= v_local::time AND d.end_time >= v_fim::time) THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM casa_pedidos b
     WHERE b.profissional_id = p_prof_id AND b.id IS DISTINCT FROM p_ignorar
       AND b.estado IN ('aceite','a_caminho','chegou','em_curso')
       AND tstzrange(b.scheduled_at, b.scheduled_at + make_interval(mins => b.duracao_min))
           && tstzrange(p_start, p_start + make_interval(mins => p_duracao_min)));
END $$;

CREATE OR REPLACE FUNCTION public._casa_elegiveis(p_pedido_id uuid)
 RETURNS TABLE(profissional_id uuid, user_id uuid, nome text, distancia_km double precision, tem_aparelho boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT c.id, c.user_id, c.name,
         CASE WHEN c.base_lat IS NULL OR b.lat IS NULL THEN NULL
              ELSE public._cleaning_distance_km(c.base_lat, c.base_lng, b.lat, b.lng) END,
         public.tem_aparelho(c.user_id, 'handyman')
    FROM casa_pedidos b
    JOIN casa_oficios o ON o.codigo = b.oficio AND o.ativo
    JOIN casa_profissionais c ON c.approval_status = 'approved' AND c.is_active
    JOIN casa_profissional_oficios po ON po.profissional_id = c.id AND po.oficio = b.oficio
                                     AND po.estado = 'approved' AND po.ligado
   WHERE b.id = p_pedido_id
     AND c.user_id <> b.client_user_id
     AND public.aceita_papel(c.user_id, 'handyman')
     -- Fase 2: o servidor, e não só o ecrã, recusa ofícios sem o documento aprovado e válido.
     AND (o.documento_exigido IS NULL OR EXISTS (
            SELECT 1 FROM casa_documentos d
             WHERE d.profissional_id = c.id AND d.tipo = o.documento_exigido AND d.estado = 'approved'
               AND (d.validade IS NULL OR d.validade >= (now() AT TIME ZONE 'Europe/Lisbon')::date)))
     AND (c.base_lat IS NULL OR b.lat IS NULL
          OR public._cleaning_distance_km(c.base_lat, c.base_lng, b.lat, b.lng) <= c.service_radius_km)
     AND public._casa_disponivel(c.id, b.scheduled_at, b.duracao_min, b.id)
   ORDER BY 5 DESC, 4 ASC NULLS LAST, c.rating_avg DESC, c.jobs_done DESC
$$;

-- 5) Rotação de ofertas (preço fixo e à hora) ------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_proxima_oferta(p_pedido_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  b casa_pedidos;
  e record;
  v_timeout int := public._casa_int('casa_offer_timeout_min', 15);
  v_curto int := public._casa_int('oferta_sem_aparelho_min', 1);
  v_ganho int;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado <> 'procura' OR b.profissional_id IS NOT NULL THEN RETURN; END IF;
  IF b.payment_method IN ('card','mbway') AND b.payment_status = 'unpaid' THEN RETURN; END IF;

  -- Quem recusou não volta a receber este pedido; a 2.ª volta repete quem só não respondeu.
  SELECT x.* INTO e FROM public._casa_elegiveis(p_pedido_id) x
   WHERE NOT (x.profissional_id = ANY (b.offered_profissional_ids))
     AND NOT EXISTS (SELECT 1 FROM casa_ofertas co WHERE co.pedido_id = b.id
                       AND co.profissional_id = x.profissional_id AND co.resposta = 'recusada')
   LIMIT 1;

  IF e.profissional_id IS NULL AND b.offer_round < public._casa_int('casa_offer_rondas', 2)
     AND cardinality(b.offered_profissional_ids) > 0 THEN
    UPDATE casa_pedidos SET offer_round = offer_round + 1, offered_profissional_ids = '{}' WHERE id = b.id;
    b.offer_round := b.offer_round + 1; b.offered_profissional_ids := '{}';
    SELECT x.* INTO e FROM public._casa_elegiveis(p_pedido_id) x
     WHERE NOT EXISTS (SELECT 1 FROM casa_ofertas co WHERE co.pedido_id = b.id
                         AND co.profissional_id = x.profissional_id AND co.resposta = 'recusada')
     LIMIT 1;
  END IF;

  IF e.profissional_id IS NULL THEN
    UPDATE casa_pedidos SET offer_profissional_id = NULL, offer_expires_at = NULL,
                            convites_enviados_em = now() WHERE id = b.id;
    IF cardinality(b.offered_profissional_ids) = 0 AND b.offer_round = 1 THEN
      PERFORM public._casa_notificar_admin('Casa sem profissional',
        'Pedido ' || b.id || ' para ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI')
        || ' sem profissional disponível no ofício ' || b.oficio || '.');
    END IF;
    RETURN;
  END IF;

  IF NOT e.tem_aparelho THEN v_timeout := LEAST(v_timeout, GREATEST(v_curto, 1)); END IF;
  v_ganho := b.total_cents - round(b.total_cents * public._casa_pct_do(e.profissional_id) / 100.0)::int;

  UPDATE casa_pedidos
     SET offer_profissional_id = e.profissional_id,
         offer_expires_at = now() + make_interval(mins => v_timeout),
         offered_profissional_ids = offered_profissional_ids || e.profissional_id,
         convites_enviados_em = now()
   WHERE id = b.id;

  INSERT INTO casa_ofertas (pedido_id, profissional_id, user_id, tipo, expira_em, tinha_aparelho, ronda)
  VALUES (b.id, e.profissional_id, e.user_id, CASE WHEN b.offer_round > 1 THEN 'repeticao' ELSE 'oferta' END,
          now() + make_interval(mins => v_timeout), e.tem_aparelho, b.offer_round);
  BEGIN
    PERFORM public.registar_oferta('casa', b.id, e.profissional_id, e.user_id, e.nome, e.tem_aparelho, v_timeout);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM public._casa_notificar(e.user_id, 'handyman', 'casa_offer', 'Novo trabalho Casa',
    (SELECT s.nome FROM casa_servicos s WHERE s.id = b.servico_id) || ' em ' || COALESCE(NULLIF(b.address_city, ''), 'Guarda')
    || ' a ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
    || ' — ganhas ' || replace(to_char(v_ganho / 100.0, 'FM999990.00'), '.', ',') || ' €. Tens ' || v_timeout || ' min para aceitar.',
    b.id);
END $$;

-- 6) Convites para orçar (até casa_quote_convidar_n; aceita até casa_quote_max_pros) ---------
CREATE OR REPLACE FUNCTION public._casa_convidar(p_pedido_id uuid)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  b casa_pedidos;
  e record;
  v_ja int;
  v_n int := public._casa_int('casa_quote_convidar_n', 6);
  v_expira timestamptz;
  v_feitos int := 0;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado <> 'orcamentos' THEN RETURN 0; END IF;
  IF (SELECT count(*) FROM casa_orcamentos WHERE pedido_id = b.id AND estado = 'enviado')
       >= public._casa_int('casa_quote_max_pros', 3) THEN RETURN 0; END IF;
  SELECT count(*) INTO v_ja FROM casa_ofertas WHERE pedido_id = b.id AND tipo = 'convite_orcamento';
  v_expira := b.created_at + make_interval(hours => public._casa_int('casa_quote_pedido_horas', 48));

  FOR e IN
    SELECT x.* FROM public._casa_elegiveis(p_pedido_id) x
     WHERE NOT EXISTS (SELECT 1 FROM casa_ofertas co WHERE co.pedido_id = b.id AND co.profissional_id = x.profissional_id)
     LIMIT GREATEST(v_n - v_ja, 0)
  LOOP
    INSERT INTO casa_ofertas (pedido_id, profissional_id, user_id, tipo, expira_em, tinha_aparelho, ronda)
    VALUES (b.id, e.profissional_id, e.user_id, 'convite_orcamento', v_expira, e.tem_aparelho, 1);
    BEGIN
      PERFORM public.registar_oferta('casa', b.id, e.profissional_id, e.user_id, e.nome, e.tem_aparelho,
                                     GREATEST(1, (extract(epoch FROM (v_expira - now())) / 60)::int));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    -- 1.13: o primeiro aviso de um pedido de orçamento ainda não tem valor (exceção escrita no ESPEC).
    PERFORM public._casa_notificar(e.user_id, 'handyman', 'casa_offer', 'Pedido de orçamento Casa',
      COALESCE((SELECT s.nome FROM casa_servicos s WHERE s.id = b.servico_id), 'Trabalho') || ' em '
      || COALESCE(NULLIF(b.address_city, ''), 'Guarda') || '. Vê as fotos e envia o teu preço.', b.id);
    v_feitos := v_feitos + 1;
  END LOOP;

  UPDATE casa_pedidos SET convites_enviados_em = now() WHERE id = b.id;
  IF v_ja + v_feitos = 0 THEN
    PERFORM public._casa_notificar_admin('Casa sem profissional para orçar',
      'Pedido de orçamento ' || b.id || ' (' || b.oficio || ') sem profissional disponível.');
  END IF;
  RETURN v_feitos;
END $$;

REVOKE ALL ON FUNCTION public._casa_notificar(uuid, text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_notificar_admin(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_proxima_oferta(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_convidar(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_elegiveis(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_pedido_json(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_evento(uuid, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_pessoa_prof(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_disponivel(uuid, timestamptz, integer, uuid) FROM PUBLIC, anon, authenticated;