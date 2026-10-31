-- Casa & Manutenção — parte 4: funções do profissional, tarefas agendadas e acerto semanal.
-- Molde: Limpeza (oito tarefas: tempo esgotado, nova tentativa, expirar sem ninguém, lembretes
-- 24 h e 2 h, alerta de preso, confirmar sozinho, pagamento por fazer) + expirar orçamentos e
-- validade dos documentos. Acerto semanal em cêntimos, juntado por pessoa.
--
-- ESTADO (31/10, retoma-geral-2026-10-31, bloco 1): ficheiro PENDENTE. Não foi aplicado em
-- produção. Aplica-se no passo PUBLICAR, ANTES de casa_05_admin.sql, e só depois das partes
-- 01..03 (já no ar desde 31/10 06:05-06:52). Revisão de 31/10 acrescentou: meu_orcamento_id nas
-- ofertas (a app precisa dele para retirar o orçamento), recusa de aceitar oferta com o
-- profissional suspenso, acerto sem os pedidos com reembolso pendente (o Danilo decide esse
-- dinheiro), 'casa' no registo de ofertas e os dois baldes privados com as regras (secções 7 e 8).

-- 1) Candidatura, documentos, perfil -------------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_gravar_disponibilidade(p_prof_id uuid, p_slots jsonb)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF p_slots IS NULL OR jsonb_typeof(p_slots) <> 'array' THEN RETURN; END IF;
  DELETE FROM casa_disponibilidade WHERE profissional_id = p_prof_id;
  INSERT INTO casa_disponibilidade (profissional_id, weekday, start_time, end_time)
  SELECT p_prof_id, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time
    FROM jsonb_array_elements(p_slots) x
   WHERE (x ->> 'weekday') IS NOT NULL AND (x ->> 'start')::time < (x ->> 'end')::time;
END $$;

CREATE OR REPLACE FUNCTION public._casa_perfil_json(p_prof_id uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'perfil', jsonb_build_object('id', c.id, 'name', c.name, 'phone', c.phone, 'email', c.email,
       'photo_url', c.photo_url, 'bio', c.bio, 'nif', c.nif, 'base_address', c.base_address,
       'base_lat', c.base_lat, 'base_lng', c.base_lng, 'service_radius_km', c.service_radius_km,
       'has_van', c.has_van, 'has_tools', c.has_tools, 'approval_status', c.approval_status,
       'rejection_reason', c.rejection_reason, 'is_active', c.is_active, 'rating_avg', c.rating_avg,
       'ratings_count', c.ratings_count, 'jobs_done', c.jobs_done, 'sem_comissao_ate', c.sem_comissao_ate),
    'oficios', COALESCE((SELECT jsonb_agg(jsonb_build_object('codigo', po.oficio, 'nome', o.nome, 'fase', o.fase,
                 'documento_exigido', o.documento_exigido, 'estado', po.estado, 'ligado', po.ligado,
                 'motivo', po.motivo) ORDER BY o.ordem)
                 FROM casa_profissional_oficios po JOIN casa_oficios o ON o.codigo = po.oficio
                WHERE po.profissional_id = c.id), '[]'::jsonb),
    'documentos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'oficio', d.oficio,
                 'estado', d.estado, 'validade', d.validade, 'motivo', d.motivo, 'created_at', d.created_at)
                 ORDER BY d.created_at DESC) FROM casa_documentos d WHERE d.profissional_id = c.id), '[]'::jsonb),
    'disponibilidade', COALESCE((SELECT jsonb_agg(jsonb_build_object('weekday', a.weekday,
                 'start', to_char(a.start_time, 'HH24:MI'), 'end', to_char(a.end_time, 'HH24:MI'))
                 ORDER BY a.weekday, a.start_time) FROM casa_disponibilidade a WHERE a.profissional_id = c.id), '[]'::jsonb),
    'aceita_papel', public.aceita_papel(c.user_id, 'handyman'),
    'comissao_pct', public._casa_pct_do(c.id),
    'valores_autorizados', public._casa_valores_validos())
  FROM casa_profissionais c WHERE c.id = p_prof_id
$$;

CREATE OR REPLACE FUNCTION public.casa_candidatura(
  p_name text, p_phone text, p_email text, p_photo_url text, p_bio text, p_nif text,
  p_base_address text, p_base_lat double precision, p_base_lng double precision, p_service_radius_km numeric,
  p_has_van boolean, p_has_tools boolean, p_oficios text[], p_disponibilidade jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_estado text; v_novo boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF NULLIF(btrim(COALESCE(p_name, '')), '') IS NULL THEN RAISE EXCEPTION 'nome_em_falta'; END IF;
  IF p_oficios IS NULL OR cardinality(p_oficios) = 0 THEN RAISE EXCEPTION 'oficios_em_falta'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(p_oficios) x WHERE x NOT IN (SELECT codigo FROM casa_oficios)) THEN
    RAISE EXCEPTION 'oficio_invalido';
  END IF;
  SELECT approval_status INTO v_estado FROM casa_profissionais WHERE user_id = v_uid;
  IF v_estado = 'banned' THEN RAISE EXCEPTION 'conta_bloqueada' USING ERRCODE = '42501'; END IF;
  v_novo := v_estado IS NULL;

  INSERT INTO casa_profissionais (user_id, name, phone, email, photo_url, bio, nif, base_address,
                                  base_lat, base_lng, service_radius_km, has_van, has_tools)
  VALUES (v_uid, btrim(p_name), COALESCE(p_phone, ''), COALESCE(p_email, ''), COALESCE(p_photo_url, ''),
          left(COALESCE(p_bio, ''), 1000), COALESCE(p_nif, ''), COALESCE(p_base_address, ''),
          p_base_lat, p_base_lng, LEAST(GREATEST(COALESCE(p_service_radius_km, 15), 1), 100),
          COALESCE(p_has_van, false), COALESCE(p_has_tools, true))
  ON CONFLICT (user_id) DO UPDATE SET
    name = EXCLUDED.name, phone = EXCLUDED.phone, email = EXCLUDED.email,
    photo_url = CASE WHEN EXCLUDED.photo_url <> '' THEN EXCLUDED.photo_url ELSE casa_profissionais.photo_url END,
    bio = EXCLUDED.bio, nif = EXCLUDED.nif, base_address = EXCLUDED.base_address,
    base_lat = EXCLUDED.base_lat, base_lng = EXCLUDED.base_lng, service_radius_km = EXCLUDED.service_radius_km,
    has_van = EXCLUDED.has_van, has_tools = EXCLUDED.has_tools,
    approval_status = CASE WHEN casa_profissionais.approval_status = 'rejected' THEN 'pending'
                           ELSE casa_profissionais.approval_status END,
    rejection_reason = CASE WHEN casa_profissionais.approval_status = 'rejected' THEN NULL
                            ELSE casa_profissionais.rejection_reason END
  RETURNING id INTO v_id;

  -- Ofícios novos entram por aprovar; os que saíram da lista e ainda estavam por aprovar saem.
  DELETE FROM casa_profissional_oficios
   WHERE profissional_id = v_id AND estado = 'pending' AND NOT (oficio = ANY (p_oficios));
  INSERT INTO casa_profissional_oficios (profissional_id, oficio)
  SELECT v_id, x FROM unnest(p_oficios) x ON CONFLICT DO NOTHING;
  UPDATE casa_profissional_oficios SET estado = 'pending', motivo = NULL
   WHERE profissional_id = v_id AND estado = 'rejected' AND oficio = ANY (p_oficios);

  PERFORM public._casa_gravar_disponibilidade(v_id, p_disponibilidade);
  IF v_novo THEN
    PERFORM public._casa_notificar_admin('Nova candidatura Casa', btrim(p_name) || ' — ' || array_to_string(p_oficios, ', '));
  END IF;
  RETURN public._casa_perfil_json(v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_registar_documento(p_tipo text, p_oficio text, p_storage_path text, p_numero text, p_validade date)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); v_id uuid;
BEGIN
  IF p_tipo NOT IN ('cartao_cidadao','seguro_acidentes','seguro_rc','dgeg_eletricidade','dgeg_gas','impic','outro') THEN
    RAISE EXCEPTION 'tipo_invalido';
  END IF;
  IF p_oficio IS NOT NULL AND NOT EXISTS (SELECT 1 FROM casa_oficios WHERE codigo = p_oficio) THEN
    RAISE EXCEPTION 'oficio_invalido';
  END IF;
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE c.user_id::text || '/%' THEN RAISE EXCEPTION 'caminho_invalido'; END IF;
  INSERT INTO casa_documentos (profissional_id, oficio, tipo, storage_path, numero, validade)
  VALUES (c.id, p_oficio, p_tipo, p_storage_path, NULLIF(btrim(COALESCE(p_numero, '')), ''), p_validade)
  RETURNING id INTO v_id;
  IF c.approval_status = 'approved' THEN
    PERFORM public._casa_notificar_admin('Casa: documento novo', c.name || ' enviou ' || p_tipo || '.');
  END IF;
  RETURN jsonb_build_object('id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_meu_perfil()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public._casa_perfil_json(id) FROM casa_profissionais WHERE user_id = auth.uid() $$;

CREATE OR REPLACE FUNCTION public.casa_definir_disponibilidade(p_slots jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual();
BEGIN
  PERFORM public._casa_gravar_disponibilidade(c.id, COALESCE(p_slots, '[]'::jsonb));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.casa_ligar_oficio(p_oficio text, p_ligado boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); v_estado text;
BEGIN
  SELECT estado INTO v_estado FROM casa_profissional_oficios WHERE profissional_id = c.id AND oficio = p_oficio;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'oficio_invalido'; END IF;
  IF p_ligado AND v_estado <> 'approved' THEN RAISE EXCEPTION 'oficio_por_aprovar'; END IF;
  UPDATE casa_profissional_oficios SET ligado = p_ligado WHERE profissional_id = c.id AND oficio = p_oficio;
  RETURN jsonb_build_object('ok', true);
END $$;

-- 2) Ofertas e orçamentos ------------------------------------------------------------------
-- Antes de aceitar, o profissional vê a zona e a distância, nunca a porta.
CREATE OR REPLACE FUNCTION public.casa_minhas_ofertas()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais; v_pct numeric;
BEGIN
  SELECT * INTO c FROM casa_profissionais WHERE user_id = auth.uid();
  IF c.id IS NULL OR c.approval_status <> 'approved' THEN RETURN '[]'::jsonb; END IF;
  v_pct := public._casa_pct_do(c.id);
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'pedido_id', b.id, 'tipo', x.tipo, 'oficio', b.oficio,
      'oficio_nome', (SELECT o.nome FROM casa_oficios o WHERE o.codigo = b.oficio),
      'servico_nome', (SELECT s.nome FROM casa_servicos s WHERE s.id = b.servico_id),
      'modo', b.modo, 'quantidade', b.quantidade, 'descricao', b.descricao, 'respostas', b.respostas,
      'localidade', COALESCE(NULLIF(b.address_city, ''), 'Guarda'),
      'distancia_km', CASE WHEN c.base_lat IS NULL OR b.lat IS NULL THEN NULL
                           ELSE round(public._cleaning_distance_km(c.base_lat, c.base_lng, b.lat, b.lng)::numeric, 1) END,
      'scheduled_at', b.scheduled_at, 'duracao_min', b.duracao_min,
      'ganho_cents', CASE WHEN x.tipo = 'oferta' THEN b.total_cents - round(b.total_cents * v_pct / 100.0)::int END,
      'total_cents', CASE WHEN x.tipo = 'oferta' THEN b.total_cents ELSE 0 END,
      'expira_em', x.expira,
      'fotos', COALESCE((SELECT jsonb_agg(f.storage_path ORDER BY f.created_at) FROM casa_pedido_fotos f
                          WHERE f.pedido_id = b.id AND f.tipo = 'problema'), '[]'::jsonb),
      'orcamentos_recebidos', (SELECT count(*) FROM casa_orcamentos q WHERE q.pedido_id = b.id AND q.estado = 'enviado'),
      'ja_orcei', EXISTS (SELECT 1 FROM casa_orcamentos q WHERE q.pedido_id = b.id AND q.profissional_id = c.id AND q.estado = 'enviado'),
      -- 31/10: a app (HandymanStore) guarda este id para poder retirar o orçamento depois de reabrir.
      'meu_orcamento_id', (SELECT q.id FROM casa_orcamentos q WHERE q.pedido_id = b.id AND q.profissional_id = c.id
                              AND q.estado = 'enviado' LIMIT 1))
      ORDER BY x.expira)
    FROM (
      SELECT p.id, 'oferta'::text AS tipo, p.offer_expires_at AS expira
        FROM casa_pedidos p
       WHERE p.offer_profissional_id = c.id AND p.estado = 'procura' AND p.offer_expires_at > now()
      UNION ALL
      SELECT co.pedido_id, 'convite_orcamento', co.expira_em
        FROM casa_ofertas co JOIN casa_pedidos p ON p.id = co.pedido_id
       WHERE co.profissional_id = c.id AND co.tipo = 'convite_orcamento' AND p.estado = 'orcamentos'
         AND (co.resposta IS NULL OR co.resposta = 'orcamento_enviado') AND co.expira_em > now()
    ) x JOIN casa_pedidos b ON b.id = x.id), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.casa_aceitar_oferta(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos;
BEGIN
  -- 31/10: suspenso/banido entre a oferta e o toque não aceita.
  IF c.approval_status <> 'approved' OR NOT c.is_active THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.offer_profissional_id IS DISTINCT FROM c.id OR b.estado <> 'procura'
     OR b.offer_expires_at < now() THEN
    RAISE EXCEPTION 'oferta_expirada';
  END IF;
  IF NOT public._casa_disponivel(c.id, b.scheduled_at, b.duracao_min, b.id) THEN RAISE EXCEPTION 'profissional_ocupado'; END IF;
  UPDATE casa_pedidos
     SET estado = 'aceite', profissional_id = c.id, accepted_at = now(), comissao_pct = public._casa_pct_do(c.id),
         offer_profissional_id = NULL, offer_expires_at = NULL
   WHERE id = b.id;
  UPDATE casa_ofertas SET resposta = 'aceite', respondida_em = now()
   WHERE pedido_id = b.id AND profissional_id = c.id AND resposta IS NULL;
  BEGIN PERFORM public.fechar_oferta(b.id, c.id, 'aceite'); EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM public._casa_evento(b.id, 'procura', 'aceite', 'handyman');
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Pedido confirmado',
    c.name || ' vai fazer o trabalho a ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') || '.', b.id);
  RETURN public._casa_pedido_json(b.id, 'profissional');
END $$;

CREATE OR REPLACE FUNCTION public.casa_recusar_oferta(p_pedido_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF b.offer_profissional_id = c.id AND b.estado = 'procura' THEN
    UPDATE casa_ofertas SET resposta = 'recusada', respondida_em = now()
     WHERE pedido_id = b.id AND profissional_id = c.id AND resposta IS NULL;
    BEGIN PERFORM public.fechar_oferta(b.id, c.id, 'recusada'); EXCEPTION WHEN OTHERS THEN NULL; END;
    UPDATE casa_pedidos SET offer_profissional_id = NULL, offer_expires_at = NULL WHERE id = b.id;
    PERFORM public._casa_proxima_oferta(b.id);
  ELSIF b.estado = 'orcamentos' AND EXISTS (SELECT 1 FROM casa_ofertas WHERE pedido_id = b.id AND profissional_id = c.id
                                              AND tipo = 'convite_orcamento') THEN
    UPDATE casa_ofertas SET resposta = 'recusada', respondida_em = now()
     WHERE pedido_id = b.id AND profissional_id = c.id AND tipo = 'convite_orcamento';
    PERFORM public._casa_convidar(b.id);
  ELSE
    RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.casa_enviar_orcamento(p_pedido_id uuid, p_preco_cents integer, p_inclui text,
  p_materiais text, p_materiais_incluidos boolean, p_prazo text, p_duracao_min integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos; v_id uuid;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado <> 'orcamentos' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF NOT EXISTS (SELECT 1 FROM casa_ofertas WHERE pedido_id = b.id AND profissional_id = c.id
                   AND tipo = 'convite_orcamento' AND expira_em > now()
                   AND (resposta IS NULL OR resposta = 'orcamento_enviado')) THEN
    RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
  END IF;
  IF p_preco_cents IS NULL OR p_preco_cents <= 0 OR p_preco_cents > 1000000 THEN RAISE EXCEPTION 'preco_invalido'; END IF;
  IF NOT EXISTS (SELECT 1 FROM casa_orcamentos WHERE pedido_id = b.id AND profissional_id = c.id AND estado = 'enviado')
     AND (SELECT count(*) FROM casa_orcamentos WHERE pedido_id = b.id AND estado = 'enviado')
         >= public._casa_int('casa_quote_max_pros', 3) THEN
    RAISE EXCEPTION 'orcamentos_completos';
  END IF;
  INSERT INTO casa_orcamentos (pedido_id, profissional_id, preco_cents, inclui, materiais, materiais_incluidos,
                               prazo, duracao_min, estado, expira_em)
  VALUES (b.id, c.id, p_preco_cents, left(COALESCE(p_inclui, ''), 1000), left(COALESCE(p_materiais, ''), 1000),
          COALESCE(p_materiais_incluidos, false), left(COALESCE(p_prazo, ''), 200), p_duracao_min, 'enviado',
          now() + make_interval(hours => public._casa_int('casa_quote_validade_horas', 72)))
  ON CONFLICT (pedido_id, profissional_id) DO UPDATE SET
    preco_cents = EXCLUDED.preco_cents, inclui = EXCLUDED.inclui, materiais = EXCLUDED.materiais,
    materiais_incluidos = EXCLUDED.materiais_incluidos, prazo = EXCLUDED.prazo, duracao_min = EXCLUDED.duracao_min,
    estado = 'enviado', expira_em = EXCLUDED.expira_em, decidido_em = NULL, created_at = now()
  WHERE casa_orcamentos.estado IN ('enviado','retirado','expirado')
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  UPDATE casa_ofertas SET resposta = 'orcamento_enviado', respondida_em = now()
   WHERE pedido_id = b.id AND profissional_id = c.id AND tipo = 'convite_orcamento';
  PERFORM public._casa_evento(b.id, 'orcamentos', 'orcamentos', 'handyman',
                              jsonb_build_object('orcamento_id', v_id, 'preco_cents', p_preco_cents));
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Recebeste um orçamento',
    c.name || ': ' || replace(to_char(p_preco_cents / 100.0, 'FM999990.00'), '.', ',') || ' €. Compara e escolhe na app.', b.id);
  RETURN jsonb_build_object('id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_retirar_orcamento(p_orcamento_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); q casa_orcamentos;
BEGIN
  SELECT * INTO q FROM casa_orcamentos WHERE id = p_orcamento_id FOR UPDATE;
  IF q.id IS NULL OR q.profissional_id <> c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF q.estado <> 'enviado' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  UPDATE casa_orcamentos SET estado = 'retirado', decidido_em = now() WHERE id = q.id;
  PERFORM public._casa_evento(q.pedido_id, 'orcamentos', 'orcamentos', 'handyman', jsonb_build_object('orcamento_retirado', q.id));
  RETURN jsonb_build_object('ok', true);
END $$;

-- 3) O trabalho -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.casa_meus_trabalhos()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(public._casa_pedido_json(x.id, 'profissional') ORDER BY x.ordem, x.scheduled_at), '[]'::jsonb)
    FROM (SELECT b.id, b.scheduled_at,
                 CASE WHEN b.estado IN ('aceite','a_caminho','chegou','em_curso','concluido','disputa') THEN 0 ELSE 1 END AS ordem
            FROM casa_pedidos b JOIN casa_profissionais c ON c.id = b.profissional_id
           WHERE c.user_id = auth.uid()
           ORDER BY ordem, b.scheduled_at DESC LIMIT 100) x
$$;

CREATE OR REPLACE FUNCTION public.casa_avancar(p_pedido_id uuid, p_para text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos; v_de text;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  v_de := CASE p_para WHEN 'a_caminho' THEN 'aceite' WHEN 'chegou' THEN 'a_caminho'
                      WHEN 'em_curso' THEN 'chegou' WHEN 'concluido' THEN 'em_curso' END;
  IF v_de IS NULL OR b.estado <> v_de THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF p_para = 'concluido' THEN
    IF NOT EXISTS (SELECT 1 FROM casa_pedido_fotos WHERE pedido_id = b.id AND tipo = 'depois') THEN
      RAISE EXCEPTION 'foto_depois_em_falta';
    END IF;
    IF EXISTS (SELECT 1 FROM casa_extras WHERE pedido_id = b.id AND estado = 'pedido') THEN
      RAISE EXCEPTION 'extra_por_responder';
    END IF;
  END IF;
  UPDATE casa_pedidos SET estado = p_para,
         on_the_way_at = CASE WHEN p_para = 'a_caminho' THEN now() ELSE on_the_way_at END,
         arrived_at = CASE WHEN p_para = 'chegou' THEN now() ELSE arrived_at END,
         started_at = CASE WHEN p_para = 'em_curso' THEN now() ELSE started_at END,
         done_at = CASE WHEN p_para = 'concluido' THEN now() ELSE done_at END
   WHERE id = b.id;
  PERFORM public._casa_evento(b.id, v_de, p_para, 'handyman');
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status',
    CASE p_para WHEN 'a_caminho' THEN 'O profissional está a caminho' WHEN 'chegou' THEN 'O profissional chegou'
                WHEN 'em_curso' THEN 'O trabalho começou' ELSE 'Trabalho terminado' END,
    CASE p_para WHEN 'concluido' THEN 'Vê as fotos e confirma na app se ficou bem.'
                ELSE c.name || ' — ' || COALESCE((SELECT nome FROM casa_servicos WHERE id = b.servico_id), 'Casa') || '.' END,
    b.id);
  RETURN public._casa_pedido_json(b.id, 'profissional');
END $$;

CREATE OR REPLACE FUNCTION public.casa_pedir_extra(p_pedido_id uuid, p_valor_cents integer, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos; v_id uuid;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF b.estado NOT IN ('chegou','em_curso') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF p_valor_cents IS NULL OR p_valor_cents <= 0 OR p_valor_cents > 100000 THEN RAISE EXCEPTION 'preco_invalido'; END IF;
  IF length(btrim(COALESCE(p_motivo, ''))) < 3 THEN RAISE EXCEPTION 'motivo_em_falta'; END IF;
  IF EXISTS (SELECT 1 FROM casa_extras WHERE pedido_id = b.id AND estado = 'pedido') THEN RAISE EXCEPTION 'extra_por_responder'; END IF;
  INSERT INTO casa_extras (pedido_id, valor_cents, motivo, pedido_por)
  VALUES (b.id, p_valor_cents, left(btrim(p_motivo), 500), auth.uid()) RETURNING id INTO v_id;
  PERFORM public._casa_evento(b.id, b.estado, b.estado, 'handyman', jsonb_build_object('extra_id', v_id, 'valor_cents', p_valor_cents));
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Pedido de valor extra',
    replace(to_char(p_valor_cents / 100.0, 'FM999990.00'), '.', ',') || ' € — ' || left(btrim(p_motivo), 100) || '. Aceita ou recusa na app.', b.id);
  RETURN jsonb_build_object('id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.casa_avaliar_cliente(p_pedido_id uuid, p_nota integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF b.estado <> 'confirmado' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF b.rating_profissional IS NOT NULL THEN RAISE EXCEPTION 'ja_avaliado'; END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'nota_invalida'; END IF;
  UPDATE casa_pedidos SET rating_profissional = p_nota WHERE id = b.id;
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.casa_desistir(p_pedido_id uuid, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); b casa_pedidos;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
  IF b.estado NOT IN ('aceite','a_caminho') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  UPDATE casa_ofertas SET resposta = 'recusada', respondida_em = now() WHERE pedido_id = b.id AND profissional_id = c.id;
  IF b.orcamento_aceite_id IS NOT NULL THEN
    UPDATE casa_orcamentos SET estado = 'retirado', decidido_em = now() WHERE id = b.orcamento_aceite_id;
    UPDATE casa_orcamentos SET estado = 'enviado', decidido_em = NULL
     WHERE pedido_id = b.id AND estado = 'recusado' AND expira_em > now();
    UPDATE casa_pedidos SET estado = 'orcamentos', profissional_id = NULL, orcamento_aceite_id = NULL,
           preco_cents = 0, total_cents = extras_cents, accepted_at = NULL, on_the_way_at = NULL, comissao_pct = NULL
     WHERE id = b.id;
    PERFORM public._casa_convidar(b.id);
  ELSE
    UPDATE casa_pedidos SET estado = 'procura', profissional_id = NULL, accepted_at = NULL, on_the_way_at = NULL,
           comissao_pct = NULL
     WHERE id = b.id;
    PERFORM public._casa_proxima_oferta(b.id);
  END IF;
  PERFORM public._casa_evento(b.id, b.estado, CASE WHEN b.orcamento_aceite_id IS NOT NULL THEN 'orcamentos' ELSE 'procura' END,
                              'handyman', jsonb_build_object('desistiu', c.id, 'motivo', p_motivo));
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'O profissional teve de cancelar',
    'Estamos a procurar outro profissional para o teu pedido.', b.id);
  PERFORM public._casa_notificar_admin('Casa: profissional desistiu', c.name || ' desistiu do pedido ' || b.id || ': ' || COALESCE(p_motivo, ''));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public._casa_inicio_semana(p_ts timestamptz)
 RETURNS timestamptz LANGUAGE sql IMMUTABLE
AS $$ SELECT (date_trunc('week', p_ts AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon' $$;

CREATE OR REPLACE FUNCTION public.casa_meus_ganhos()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais := public._casa_prof_atual(); v_ini timestamptz := public._casa_inicio_semana(now()); s record;
BEGIN
  SELECT count(*)::int AS n, COALESCE(sum(total_cents), 0)::int AS bruto, COALESCE(sum(comissao_cents), 0)::int AS com,
         COALESCE(sum(ganho_cents), 0)::int AS ganho,
         COALESCE(sum(total_cents) FILTER (WHERE payment_method = 'cash'), 0)::int AS mao,
         (COALESCE(sum(ganho_cents) FILTER (WHERE payment_method <> 'cash'), 0)
          - COALESCE(sum(comissao_cents) FILTER (WHERE payment_method = 'cash'), 0))::int AS a_receber
    INTO s FROM casa_pedidos
   WHERE profissional_id = c.id AND estado = 'confirmado' AND NOT reembolso_pendente AND confirmed_at >= v_ini;
  RETURN jsonb_build_object(
    'semana', jsonb_build_object('inicio', v_ini, 'fim', v_ini + interval '7 days', 'trabalhos', s.n,
                                 'bruto_cents', s.bruto, 'comissao_cents', s.com, 'ganho_cents', s.ganho,
                                 'recebido_em_mao_cents', s.mao, 'a_receber_cents', s.a_receber),
    'acertos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'week_start_at', a.week_start_at,
                 'week_end_at', a.week_end_at, 'total_jobs', a.total_jobs, 'net_payout_cents', a.net_payout_cents,
                 'direction', a.direction, 'status', a.status, 'paid_at', a.paid_at) ORDER BY a.week_start_at DESC)
                 FROM casa_acertos_semanais a WHERE a.profissional_id = c.id), '[]'::jsonb),
    'trabalhos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', b.id,
                 'servico_nome', (SELECT nome FROM casa_servicos WHERE id = b.servico_id), 'confirmed_at', b.confirmed_at,
                 'total_cents', b.total_cents, 'comissao_cents', b.comissao_cents, 'ganho_cents', b.ganho_cents,
                 'payment_method', b.payment_method) ORDER BY b.confirmed_at DESC)
                 FROM (SELECT * FROM casa_pedidos WHERE profissional_id = c.id AND estado = 'confirmado'
                        ORDER BY confirmed_at DESC LIMIT 50) b), '[]'::jsonb));
END $$;

-- 4) Acerto semanal (cêntimos; o que o Bora recebeu paga-se, o que o profissional recebeu em mão
-- não se paga outra vez e desconta a parte do Bora — regra 1.21) -----------------------------
CREATE OR REPLACE FUNCTION public.casa_calcular_acerto(p_prof_id uuid, p_week_start timestamptz, p_persist boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais; v record; v_net int; v_dir text; v_fim timestamptz := p_week_start + interval '7 days';
BEGIN
  SELECT * INTO c FROM casa_profissionais WHERE id = p_prof_id;
  IF c.id IS NULL THEN RETURN NULL; END IF;
  IF COALESCE(public.is_demo_email(c.email), false) OR COALESCE(public.is_demo_user(c.user_id), false) THEN
    RETURN jsonb_build_object('ignorado', 'demo');
  END IF;
  SELECT count(*)::int AS n, COALESCE(sum(total_cents), 0)::int AS bruto, COALESCE(sum(comissao_cents), 0)::int AS com,
         COALESCE(sum(total_cents) FILTER (WHERE payment_method = 'cash'), 0)::int AS mao,
         COALESCE(sum(ganho_cents) FILTER (WHERE payment_method <> 'cash'), 0)::int AS app_ganho,
         COALESCE(sum(comissao_cents) FILTER (WHERE payment_method = 'cash'), 0)::int AS com_mao
    INTO v FROM casa_pedidos
   WHERE profissional_id = p_prof_id AND estado = 'confirmado' AND NOT is_test_order
     AND NOT reembolso_pendente  -- 31/10: com reembolso por decidir, o Danilo decide antes de pagar
     AND confirmed_at >= p_week_start AND confirmed_at < v_fim;
  v_net := v.app_ganho - v.com_mao;
  v_dir := CASE WHEN v_net > 0 THEN 'bora_to_handyman' WHEN v_net < 0 THEN 'handyman_to_bora' ELSE 'zero' END;
  IF p_persist AND v.n > 0 THEN
    INSERT INTO casa_acertos_semanais (profissional_id, user_id, week_start_at, week_end_at, total_jobs,
           total_bruto_cents, total_comissao_cents, recebido_em_mao_cents, net_payout_cents, direction)
    VALUES (c.id, c.user_id, p_week_start, v_fim, v.n, v.bruto, v.com, v.mao, abs(v_net), v_dir)
    ON CONFLICT (profissional_id, week_start_at) DO UPDATE SET
      total_jobs = EXCLUDED.total_jobs, total_bruto_cents = EXCLUDED.total_bruto_cents,
      total_comissao_cents = EXCLUDED.total_comissao_cents, recebido_em_mao_cents = EXCLUDED.recebido_em_mao_cents,
      net_payout_cents = EXCLUDED.net_payout_cents, direction = EXCLUDED.direction
    WHERE casa_acertos_semanais.status = 'pending';
  END IF;
  RETURN jsonb_build_object('profissional_id', c.id, 'trabalhos', v.n, 'bruto_cents', v.bruto, 'comissao_cents', v.com,
                            'recebido_em_mao_cents', v.mao, 'net_payout_cents', abs(v_net), 'direction', v_dir);
END $$;

CREATE OR REPLACE FUNCTION public.casa_calcular_acertos_todos(p_week_start timestamptz DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz := COALESCE(p_week_start, public._casa_inicio_semana(now()) - interval '7 days'); r record; n int := 0;
BEGIN
  -- Sem o "autorizo" dos valores não há percentagem válida para acertar.
  IF NOT public._casa_valores_validos() THEN RETURN jsonb_build_object('ignorado', 'valores_por_autorizar'); END IF;
  FOR r IN SELECT DISTINCT profissional_id FROM casa_pedidos
            WHERE estado = 'confirmado' AND NOT is_test_order AND NOT reembolso_pendente
              AND confirmed_at >= v_ini AND confirmed_at < v_ini + interval '7 days'
  LOOP
    PERFORM public.casa_calcular_acerto(r.profissional_id, v_ini, true);
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('semana', v_ini, 'calculados', n);
END $$;

-- 5) Tarefas agendadas (uma por minuto; cada bloco isolado para um erro não parar os outros) --
CREATE OR REPLACE FUNCTION public.casa_tick()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE r record; v jsonb := '{}'::jsonb; n int;
BEGIN
  -- 1. Oferta sem resposta a tempo: passa ao seguinte.
  BEGIN
    n := 0;
    FOR r IN SELECT id, offer_profissional_id FROM casa_pedidos
              WHERE estado = 'procura' AND offer_profissional_id IS NOT NULL AND offer_expires_at < now() LOOP
      UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now()
       WHERE pedido_id = r.id AND profissional_id = r.offer_profissional_id AND resposta IS NULL;
      BEGIN PERFORM public.fechar_oferta(r.id, r.offer_profissional_id, 'sem_resposta'); EXCEPTION WHEN OTHERS THEN NULL; END;
      UPDATE casa_pedidos SET offer_profissional_id = NULL, offer_expires_at = NULL WHERE id = r.id;
      PERFORM public._casa_proxima_oferta(r.id);
      n := n + 1;
    END LOOP;
    v := v || jsonb_build_object('ofertas_esgotadas', n);
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_ofertas', SQLERRM); END;

  -- 2. Nova tentativa: pedido sem ninguém a ver, de 10 em 10 minutos (pode ter entrado alguém novo).
  BEGIN
    n := 0;
    FOR r IN SELECT id FROM casa_pedidos
              WHERE estado = 'procura' AND offer_profissional_id IS NULL
                AND (convites_enviados_em IS NULL OR convites_enviados_em < now() - interval '10 minutes')
                AND scheduled_at > now() + interval '1 hour' AND created_at > now() - interval '24 hours' LOOP
      PERFORM public._casa_proxima_oferta(r.id);
      n := n + 1;
    END LOOP;
    FOR r IN SELECT id FROM casa_pedidos
              WHERE estado = 'orcamentos' AND (convites_enviados_em IS NULL OR convites_enviados_em < now() - interval '30 minutes')
                AND scheduled_at > now() + interval '1 hour' LOOP
      PERFORM public._casa_convidar(r.id);
      n := n + 1;
    END LOOP;
    v := v || jsonb_build_object('novas_tentativas', n);
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_tentativas', SQLERRM); END;

  -- 3. Expirar sem ninguém (preço fixo) e pedidos de orçamento sem respostas.
  BEGIN
    UPDATE casa_orcamentos SET estado = 'expirado' WHERE estado = 'enviado' AND expira_em < now();
    n := 0;
    FOR r IN SELECT * FROM casa_pedidos b
              WHERE (b.estado = 'procura' AND b.offer_profissional_id IS NULL
                     AND (b.scheduled_at <= now() + interval '1 hour' OR b.created_at <= now() - interval '24 hours'))
                 OR (b.estado = 'orcamentos'
                     AND NOT EXISTS (SELECT 1 FROM casa_orcamentos q WHERE q.pedido_id = b.id AND q.estado = 'enviado')
                     AND (b.scheduled_at <= now()
                          OR b.created_at <= now() - make_interval(hours => public._casa_int('casa_quote_pedido_horas', 48)))) LOOP
      UPDATE casa_pedidos SET estado = 'expirado', reembolso_pendente = (payment_status = 'held') WHERE id = r.id;
      UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now() WHERE pedido_id = r.id AND resposta IS NULL;
      PERFORM public._casa_evento(r.id, r.estado, 'expirado', 'sistema');
      PERFORM public._casa_notificar(r.client_user_id, 'client', 'casa_status', 'Sem profissional disponível',
        'Lamentamos: não houve profissional disponível para o teu pedido. Não pagas nada.', r.id);
      n := n + 1;
    END LOOP;
    v := v || jsonb_build_object('expirados', n);
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_expirar', SQLERRM); END;

  -- 4. Lembretes 24 h e 2 h (profissional e cliente).
  BEGIN
    FOR r IN SELECT b.*, c.user_id AS prof_user FROM casa_pedidos b JOIN casa_profissionais c ON c.id = b.profissional_id
              WHERE b.estado = 'aceite' AND b.reminder_24h_sent_at IS NULL
                AND b.scheduled_at BETWEEN now() + interval '2 hours' AND now() + interval '24 hours' LOOP
      UPDATE casa_pedidos SET reminder_24h_sent_at = now() WHERE id = r.id;
      PERFORM public._casa_notificar(r.prof_user, 'handyman', 'casa_status', 'Trabalho amanhã',
        'Lembrete: trabalho Casa a ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') || '.', r.id);
      PERFORM public._casa_notificar(r.client_user_id, 'client', 'casa_status', 'Lembrete',
        'O profissional vem a ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') || '.', r.id);
    END LOOP;
    FOR r IN SELECT b.*, c.user_id AS prof_user FROM casa_pedidos b JOIN casa_profissionais c ON c.id = b.profissional_id
              WHERE b.estado = 'aceite' AND b.reminder_2h_sent_at IS NULL
                AND b.scheduled_at BETWEEN now() AND now() + interval '2 hours' LOOP
      UPDATE casa_pedidos SET reminder_2h_sent_at = now() WHERE id = r.id;
      PERFORM public._casa_notificar(r.prof_user, 'handyman', 'casa_status', 'Trabalho daqui a pouco',
        'Às ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || ' em ' || COALESCE(NULLIF(r.address_city, ''), 'Guarda')
        || '. Carrega em "A caminho" quando saíres.', r.id);
      PERFORM public._casa_notificar(r.client_user_id, 'client', 'casa_status', 'Daqui a pouco',
        'O profissional vem às ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || '.', r.id);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_lembretes', SQLERRM); END;

  -- 5. Alerta de preso ao admin.
  BEGIN
    FOR r IN SELECT * FROM casa_pedidos
              WHERE stuck_alerted_at IS NULL
                AND ((estado = 'em_curso' AND started_at < now() - make_interval(hours => public._casa_int('casa_stuck_after_hours', 6)))
                     OR (estado = 'aceite' AND scheduled_at < now() - interval '1 hour')) LOOP
      UPDATE casa_pedidos SET stuck_alerted_at = now() WHERE id = r.id;
      PERFORM public._casa_notificar_admin('Casa: trabalho parado',
        'Pedido ' || r.id || ' está em "' || r.estado || '" há demasiado tempo.');
    END LOOP;
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_preso', SQLERRM); END;

  -- 6. Lembrete para confirmar e confirmação sozinha.
  BEGIN
    FOR r IN SELECT * FROM casa_pedidos WHERE estado = 'concluido' AND client_confirm_reminded_at IS NULL
                AND done_at < now() - make_interval(hours => public._casa_int('casa_lembrete_confirmar_horas', 6)) LOOP
      UPDATE casa_pedidos SET client_confirm_reminded_at = now() WHERE id = r.id;
      PERFORM public._casa_notificar(r.client_user_id, 'client', 'casa_status', 'Confirma o trabalho',
        'O trabalho está terminado. Confirma na app se ficou bem.', r.id);
    END LOOP;
    n := 0;
    FOR r IN SELECT id FROM casa_pedidos WHERE estado = 'concluido'
                AND done_at < now() - make_interval(hours => public._casa_int('casa_auto_confirm_hours', 24)) LOOP
      PERFORM public._casa_confirmar(r.id, true);
      n := n + 1;
    END LOOP;
    v := v || jsonb_build_object('confirmados_sozinhos', n);
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_confirmar', SQLERRM); END;

  -- 7. Pagamento por fazer (cartão/MB Way) que não chegou: cai.
  BEGIN
    FOR r IN SELECT * FROM casa_pedidos WHERE estado = 'aguarda_pagamento' AND created_at < now() - interval '30 minutes' LOOP
      UPDATE casa_pedidos SET estado = 'cancelado', cancelled_at = now(), cancelled_by = 'sistema',
             cancel_reason = 'pagamento_nao_feito' WHERE id = r.id;
      PERFORM public._casa_evento(r.id, 'aguarda_pagamento', 'cancelado', 'sistema');
    END LOOP;
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_pagamento', SQLERRM); END;

  -- 8. Documentos: aviso 15 dias antes; depois da data o ofício que dependia dele desliga sozinho.
  BEGIN
    FOR r IN SELECT d.*, c.user_id FROM casa_documentos d JOIN casa_profissionais c ON c.id = d.profissional_id
              WHERE d.estado = 'approved' AND d.validade IS NOT NULL AND d.aviso_caducar_em IS NULL
                AND d.validade <= (now() AT TIME ZONE 'Europe/Lisbon')::date + 15 LOOP
      UPDATE casa_documentos SET aviso_caducar_em = now() WHERE id = r.id;
      PERFORM public._casa_notificar(r.user_id, 'handyman', 'casa_status', 'Documento a caducar',
        'Um documento teu caduca a ' || to_char(r.validade, 'DD/MM/YYYY') || '. Envia o novo na app.', NULL);
    END LOOP;
    FOR r IN SELECT d.*, c.user_id FROM casa_documentos d JOIN casa_profissionais c ON c.id = d.profissional_id
              WHERE d.estado = 'approved' AND d.validade IS NOT NULL
                AND d.validade < (now() AT TIME ZONE 'Europe/Lisbon')::date LOOP
      UPDATE casa_documentos SET estado = 'expired' WHERE id = r.id;
      UPDATE casa_profissional_oficios po SET estado = 'suspended', ligado = false,
             motivo = 'documento caducado: ' || r.tipo, decidido_em = now()
        FROM casa_oficios o
       WHERE po.profissional_id = r.profissional_id AND o.codigo = po.oficio AND o.documento_exigido = r.tipo
         AND po.estado = 'approved';
      PERFORM public._casa_notificar(r.user_id, 'handyman', 'casa_status', 'Documento caducado',
        'O teu documento caducou. Envia o novo na app para voltares a receber esses trabalhos.', NULL);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN v := v || jsonb_build_object('erro_documentos', SQLERRM); END;

  RETURN v;
END $$;

REVOKE ALL ON FUNCTION public._casa_gravar_disponibilidade(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_perfil_json(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.casa_tick() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.casa_calcular_acerto(uuid, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.casa_calcular_acertos_todos(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.casa_candidatura(text, text, text, text, text, text, text, double precision, double precision, numeric, boolean, boolean, text[], jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_registar_documento(text, text, text, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_meu_perfil() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_definir_disponibilidade(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_ligar_oficio(text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_minhas_ofertas() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_aceitar_oferta(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_recusar_oferta(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_enviar_orcamento(uuid, integer, text, text, boolean, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_retirar_orcamento(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_meus_trabalhos() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_avancar(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_pedir_extra(uuid, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_avaliar_cliente(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_desistir(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.casa_meus_ganhos() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.casa_candidatura(text, text, text, text, text, text, text, double precision, double precision, numeric, boolean, boolean, text[], jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_registar_documento(text, text, text, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_meu_perfil() TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_definir_disponibilidade(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_ligar_oficio(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_minhas_ofertas() TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_aceitar_oferta(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_recusar_oferta(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_enviar_orcamento(uuid, integer, text, text, boolean, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_retirar_orcamento(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_meus_trabalhos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_avancar(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_pedir_extra(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_avaliar_cliente(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_desistir(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.casa_meus_ganhos() TO authenticated;

-- 6) Agenda: a cada minuto e o acerto à segunda-feira de madrugada.
SELECT cron.schedule('casa_tick', '* * * * *', $cron$SELECT public.casa_tick()$cron$);
SELECT cron.schedule('casa_acertos_semanais', '20 4 * * 1', $cron$SELECT public.casa_calcular_acertos_todos(NULL)$cron$);

-- 7) Registo de ofertas do painel (31/10): a lista fechada só tinha limpeza e lavagem, por isso o
-- registar_oferta('casa', ...) das partes 2b e 4 falhava calado (está dentro de EXCEPTION).
ALTER TABLE public.ofertas_prestador_log DROP CONSTRAINT IF EXISTS ofertas_prestador_log_categoria_check;
ALTER TABLE public.ofertas_prestador_log ADD CONSTRAINT ofertas_prestador_log_categoria_check
  CHECK (categoria = ANY (ARRAY['limpeza'::text, 'lavagem'::text, 'casa'::text]));

-- 8) Baldes privados da Casa (contrato do ESPEC; a app já os usa e não existiam no ar a 31/10).
-- handyman-documents: <uid>/<tag>_<ms>.<ext>   ·   casa-fotos: <uid>/<pedido_id>/<tipo>_<ms>.jpg
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('handyman-documents', 'handyman-documents', false, 10485760),
       ('casa-fotos', 'casa-fotos', false, 10485760)
ON CONFLICT (id) DO NOTHING;

-- Quem vê uma foto de um pedido: o cliente, o profissional atribuído, quem recebeu a oferta ou o
-- convite para orçar (vê as fotos do problema antes de aceitar) e o admin. Lê o pedido do caminho.
CREATE OR REPLACE FUNCTION public._casa_foto_visivel(p_nome text)
 RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_parte text := split_part(COALESCE(p_nome, ''), '/', 2); v_pedido uuid; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  IF public.is_admin() THEN RETURN true; END IF;
  IF v_parte !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
  v_pedido := v_parte::uuid;
  RETURN EXISTS (SELECT 1 FROM casa_pedidos p WHERE p.id = v_pedido AND p.client_user_id = v_uid)
      OR EXISTS (SELECT 1 FROM casa_pedidos p JOIN casa_profissionais c ON c.id = p.profissional_id
                  WHERE p.id = v_pedido AND c.user_id = v_uid)
      OR EXISTS (SELECT 1 FROM casa_ofertas o WHERE o.pedido_id = v_pedido AND o.user_id = v_uid);
END $$;
REVOKE ALL ON FUNCTION public._casa_foto_visivel(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._casa_foto_visivel(text) TO authenticated;

DROP POLICY IF EXISTS casa_docs_dono_inserir ON storage.objects;
CREATE POLICY casa_docs_dono_inserir ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'handyman-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS casa_docs_dono_atualizar ON storage.objects;
CREATE POLICY casa_docs_dono_atualizar ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'handyman-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS casa_docs_ler ON storage.objects;
CREATE POLICY casa_docs_ler ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'handyman-documents'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

DROP POLICY IF EXISTS casa_fotos_dono_inserir ON storage.objects;
CREATE POLICY casa_fotos_dono_inserir ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'casa-fotos' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS casa_fotos_ler ON storage.objects;
CREATE POLICY casa_fotos_ler ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'casa-fotos'
         AND ((storage.foldername(name))[1] = auth.uid()::text OR public._casa_foto_visivel(name)));
