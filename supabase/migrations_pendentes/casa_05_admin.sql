-- Casa & Manutenção — parte 5: funções do painel admin (o ecrã mostra PT-BR; aqui só códigos curtos).
-- Contrato: .claude/.ai/provas/casa-manutencao-2026-10-30/ESPEC.md (secção Admin).
--
-- ESTADO (31/10, retoma-geral-2026-10-31, bloco 1): ficheiro PENDENTE, nunca aplicado. Aplica-se no
-- passo PUBLICAR DEPOIS de casa_04_profissional_e_tarefas.sql (usa casa_calcular_acertos_todos,
-- _casa_inicio_semana e os baldes da parte 4).
--
-- Molde: funções admin já no ar (admin_provider_atividade_decidir, Limpeza): is_admin(), auditoria por
-- log_admin_action(text,text,text,jsonb), SECURITY DEFINER com search_path fixo, REVOKE de PUBLIC e anon
-- + GRANT só a authenticated (o anon tem GRANT direto nas funções novas do esquema public).
--
-- Sem dinheiro de verdade: os acertos só calculam e marcam estado; "reembolso" só marca
-- reembolso_pendente (o Danilo decide o dinheiro); admin_casa_autorizar_valores só grava o texto, a data
-- e quem, na definição casa_valores_autorizados. Mudar preço, percentagem ou promoção volta a pôr os
-- valores como PROPOSTA.

-- 0) Ajudantes -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._casa_exigir_admin()
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public._casa_motivo(p_motivo text)
 RETURNS text LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v text := btrim(COALESCE(p_motivo, ''));
BEGIN
  IF length(v) < 3 THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;
  RETURN left(v, 1000);
END $$;

-- Volta a pôr os valores como PROPOSTA (guarda o que estava autorizado em 'anterior').
CREATE OR REPLACE FUNCTION public._casa_reabrir_valores(p_razao text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_antes jsonb;
BEGIN
  SELECT value INTO v_antes FROM platform_settings WHERE key = 'casa_valores_autorizados';
  IF NOT COALESCE((v_antes ->> 'autorizado')::boolean, false) THEN RETURN false; END IF;
  UPDATE platform_settings
     SET value = jsonb_build_object('autorizado', false, 'em', NULL, 'por', NULL, 'texto', NULL,
                                    'reaberto_em', now(), 'reaberto_por', auth.uid(), 'reaberto_razao', p_razao,
                                    'anterior', v_antes - 'anterior'),
         updated_at = now(), updated_by = auth.uid()
   WHERE key = 'casa_valores_autorizados';
  PERFORM public.log_admin_action('casa_valores_reabertos'::text, 'platform_settings'::text,
                                  'casa_valores_autorizados'::text,
                                  jsonb_build_object('razao', p_razao, 'antes', v_antes));
  RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public._casa_nome_cliente(p_user_id uuid)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(NULLIF(u.name, ''), split_part(u.email, '@', 1)) FROM users u WHERE u.id = p_user_id $$;

CREATE OR REPLACE FUNCTION public._casa_euro(p_cents integer)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT replace(to_char(COALESCE(p_cents, 0) / 100.0, 'FM999990.00'), '.', ',') || ' €' $$;

-- 1) Resumo ----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_resumo()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT value INTO v FROM platform_settings WHERE key = 'casa_valores_autorizados';
  RETURN jsonb_build_object(
    'enabled', public._casa_bool('casa_enabled', false),
    'valores_autorizados', jsonb_build_object('autorizado', COALESCE((v ->> 'autorizado')::boolean, false),
                                              'em', v -> 'em', 'texto', v -> 'texto'),
    'profissionais_pendentes', (SELECT count(*) FROM casa_profissionais WHERE approval_status = 'pending'),
    'oficios_pendentes', (SELECT count(*) FROM casa_profissional_oficios WHERE estado = 'pending'),
    'documentos_pendentes', (SELECT count(*) FROM casa_documentos WHERE estado = 'pending'),
    'pedidos_ativos', (SELECT count(*) FROM casa_pedidos
                        WHERE estado IN ('aceite','a_caminho','chegou','em_curso','concluido')),
    'pedidos_procura', (SELECT count(*) FROM casa_pedidos WHERE estado = 'procura'),
    'orcamentos_abertos', (SELECT count(*) FROM casa_orcamentos WHERE estado = 'enviado'),
    'disputas', (SELECT count(*) FROM casa_pedidos WHERE estado = 'disputa'),
    'reembolsos_pendentes', (SELECT count(*) FROM casa_pedidos WHERE reembolso_pendente));
END $$;

-- 2) Profissionais ---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_profissionais(p_estado text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'user_id', c.user_id, 'name', c.name, 'phone', c.phone, 'email', c.email,
      'photo_url', c.photo_url, 'approval_status', c.approval_status, 'created_at', c.created_at,
      'approved_at', c.approved_at, 'rating_avg', c.rating_avg, 'ratings_count', c.ratings_count,
      'jobs_done', c.jobs_done, 'is_active', c.is_active, 'sem_comissao_ate', c.sem_comissao_ate,
      'oficios', COALESCE((SELECT jsonb_agg(jsonb_build_object('codigo', po.oficio, 'nome', o.nome,
                     'estado', po.estado, 'ligado', po.ligado) ORDER BY o.ordem)
                   FROM casa_profissional_oficios po JOIN casa_oficios o ON o.codigo = po.oficio
                  WHERE po.profissional_id = c.id), '[]'::jsonb),
      'docs_pendentes', (SELECT count(*) FROM casa_documentos d
                          WHERE d.profissional_id = c.id AND d.estado = 'pending'))
      ORDER BY c.created_at DESC)
      FROM casa_profissionais c
     WHERE p_estado IS NULL OR p_estado IN ('', 'todos') OR c.approval_status = p_estado), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_profissional(p_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais; v_falta text[];
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO c FROM casa_profissionais WHERE id = p_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional'; END IF;
  BEGIN
    v_falta := public._conformidade_em_falta(to_jsonb(c));
  EXCEPTION WHEN OTHERS THEN v_falta := NULL;
  END;
  RETURN jsonb_build_object(
    'perfil', to_jsonb(c),
    'oficios', COALESCE((SELECT jsonb_agg(jsonb_build_object('codigo', o.codigo, 'nome', o.nome, 'fase', o.fase,
                 'documento_exigido', o.documento_exigido, 'ativo_no_catalogo', o.ativo, 'estado', po.estado,
                 'ligado', po.ligado, 'motivo', po.motivo, 'decidido_em', po.decidido_em) ORDER BY o.ordem)
                 FROM casa_profissional_oficios po JOIN casa_oficios o ON o.codigo = po.oficio
                WHERE po.profissional_id = c.id), '[]'::jsonb),
    'documentos', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC)
                 FROM casa_documentos d WHERE d.profissional_id = c.id), '[]'::jsonb),
    'disponibilidade', COALESCE((SELECT jsonb_agg(jsonb_build_object('weekday', a.weekday,
                 'start', to_char(a.start_time, 'HH24:MI'), 'end', to_char(a.end_time, 'HH24:MI'))
                 ORDER BY a.weekday, a.start_time)
                 FROM casa_disponibilidade a WHERE a.profissional_id = c.id), '[]'::jsonb),
    'pedidos', COALESCE((SELECT jsonb_agg(public._casa_pedido_json(x.id, 'admin') ORDER BY x.scheduled_at DESC)
                 FROM (SELECT b.id, b.scheduled_at FROM casa_pedidos b WHERE b.profissional_id = c.id
                        ORDER BY b.scheduled_at DESC LIMIT 50) x), '[]'::jsonb),
    'atividade_status', (SELECT a.atividade_status FROM provider_atividade a WHERE a.user_id = c.user_id),
    'conformidade_em_falta', to_jsonb(COALESCE(v_falta, '{}'::text[])));
END $$;

-- aprovar | recusar | suspender | banir | reativar. Aprovar a pessoa não aprova ofícios (ofício a ofício).
CREATE OR REPLACE FUNCTION public.admin_casa_decidir_profissional(p_id uuid, p_acao text, p_motivo text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  c casa_profissionais;
  v_novo text;
  v_motivo text := NULLIF(btrim(COALESCE(p_motivo, '')), '');
  v_promo date;
  v_titulo text;
  v_corpo text;
  r record;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO c FROM casa_profissionais WHERE id = p_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional'; END IF;
  v_novo := CASE p_acao
              WHEN 'aprovar'   THEN 'approved'
              WHEN 'recusar'   THEN 'rejected'
              WHEN 'suspender' THEN 'suspended'
              WHEN 'banir'     THEN 'banned'
              WHEN 'reativar'  THEN CASE WHEN c.approved_at IS NOT NULL THEN 'approved' ELSE 'pending' END
            END;
  IF v_novo IS NULL THEN RAISE EXCEPTION 'acao_invalida'; END IF;
  IF p_acao IN ('recusar', 'suspender', 'banir') THEN v_motivo := public._casa_motivo(p_motivo); END IF;
  IF p_acao IN ('suspender', 'banir') AND EXISTS (
       SELECT 1 FROM casa_pedidos WHERE profissional_id = c.id AND estado IN ('aceite','a_caminho','chegou','em_curso')) THEN
    RAISE EXCEPTION 'tem_trabalhos_ativos';
  END IF;

  -- Promoção dos primeiros (decisão 2 do Danilo; PROPOSTA até ao "autorizo", o acerto não corre antes):
  -- começa na primeira aprovação; só os primeiros casa_promo_primeiros_n profissionais reais.
  IF v_novo = 'approved' AND c.approved_at IS NULL AND c.sem_comissao_ate IS NULL
     AND NOT COALESCE(public.is_demo_user(c.user_id), false)
     AND (SELECT count(*) FROM casa_profissionais x
           WHERE x.approved_at IS NOT NULL AND x.id <> c.id
             AND NOT COALESCE(public.is_demo_user(x.user_id), false))
         < public._casa_int('casa_promo_primeiros_n', 5) THEN
    v_promo := (now() AT TIME ZONE 'Europe/Lisbon')::date
               + make_interval(months => public._casa_int('casa_promo_meses', 2));
  END IF;

  UPDATE casa_profissionais
     SET approval_status = v_novo,
         approved_at = CASE WHEN v_novo = 'approved' THEN COALESCE(approved_at, now()) ELSE approved_at END,
         approved_by = CASE WHEN v_novo = 'approved' THEN auth.uid() ELSE approved_by END,
         rejection_reason = CASE WHEN p_acao IN ('aprovar', 'reativar') THEN NULL ELSE v_motivo END,
         is_active = v_novo NOT IN ('suspended', 'banned'),
         sem_comissao_ate = COALESCE(v_promo, sem_comissao_ate)
   WHERE id = c.id;

  -- Quem deixou de estar aprovado larga as ofertas em aberto: passam já ao seguinte.
  IF v_novo <> 'approved' THEN
    FOR r IN SELECT id FROM casa_pedidos WHERE offer_profissional_id = c.id AND estado = 'procura' LOOP
      UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now()
       WHERE pedido_id = r.id AND profissional_id = c.id AND resposta IS NULL;
      UPDATE casa_pedidos SET offer_profissional_id = NULL, offer_expires_at = NULL WHERE id = r.id;
      PERFORM public._casa_proxima_oferta(r.id);
    END LOOP;
  END IF;

  PERFORM public.log_admin_action(('casa_profissional_' || p_acao)::text, 'casa_profissionais'::text, c.id::text,
    jsonb_build_object('antes', c.approval_status, 'depois', v_novo, 'motivo', v_motivo,
                       'sem_comissao_ate', v_promo,
                       'via', COALESCE(current_setting('bora.agente', true), 'painel')));

  v_titulo := CASE p_acao
                WHEN 'aprovar'   THEN 'Candidatura Casa aprovada'
                WHEN 'recusar'   THEN 'Candidatura Casa recusada'
                WHEN 'suspender' THEN 'Conta Casa suspensa'
                WHEN 'banir'     THEN 'Conta Casa bloqueada'
                ELSE 'Conta Casa reativada' END;
  v_corpo := CASE
               WHEN p_acao = 'aprovar' THEN 'Bem-vindo! Cada ofício é aprovado à parte: vê o estado na app.'
               WHEN p_acao = 'reativar' AND v_novo = 'pending' THEN 'A tua candidatura voltou a análise.'
               WHEN p_acao = 'reativar' THEN 'Podes voltar a receber trabalhos.'
               ELSE v_motivo END;
  PERFORM public._casa_notificar(c.user_id, 'handyman', 'casa_status', v_titulo, v_corpo, NULL);
  RETURN jsonb_build_object('ok', true, 'antes', c.approval_status, 'depois', v_novo, 'sem_comissao_ate', v_promo);
END $$;

-- aprovar | recusar | suspender um ofício. Ofício com título (fase 2) só com o documento aprovado e válido.
CREATE OR REPLACE FUNCTION public.admin_casa_decidir_oficio(p_profissional_id uuid, p_oficio text, p_acao text, p_motivo text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  c casa_profissionais;
  o casa_oficios;
  po casa_profissional_oficios;
  v_novo text;
  v_motivo text;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO c FROM casa_profissionais WHERE id = p_profissional_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional'; END IF;
  SELECT * INTO o FROM casa_oficios WHERE codigo = p_oficio;
  IF o.codigo IS NULL THEN RAISE EXCEPTION 'oficio_invalido'; END IF;
  SELECT * INTO po FROM casa_profissional_oficios WHERE profissional_id = c.id AND oficio = p_oficio FOR UPDATE;
  IF po.profissional_id IS NULL THEN RAISE EXCEPTION 'oficio_invalido'; END IF;
  v_novo := CASE p_acao WHEN 'aprovar' THEN 'approved' WHEN 'recusar' THEN 'rejected' WHEN 'suspender' THEN 'suspended' END;
  IF v_novo IS NULL THEN RAISE EXCEPTION 'acao_invalida'; END IF;
  IF p_acao <> 'aprovar' THEN v_motivo := public._casa_motivo(p_motivo); END IF;
  IF p_acao = 'aprovar' AND o.documento_exigido IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM casa_documentos d
        WHERE d.profissional_id = c.id AND d.tipo = o.documento_exigido AND d.estado = 'approved'
          AND (d.validade IS NULL OR d.validade >= (now() AT TIME ZONE 'Europe/Lisbon')::date)) THEN
    RAISE EXCEPTION 'documento_em_falta';
  END IF;

  UPDATE casa_profissional_oficios
     SET estado = v_novo,
         ligado = CASE WHEN v_novo = 'approved' THEN ligado ELSE false END,
         decidido_por = auth.uid(), decidido_em = now(), motivo = v_motivo
   WHERE profissional_id = c.id AND oficio = p_oficio;

  PERFORM public.log_admin_action(('casa_oficio_' || p_acao)::text, 'casa_profissionais'::text, c.id::text,
    jsonb_build_object('oficio', p_oficio, 'antes', po.estado, 'depois', v_novo, 'motivo', v_motivo));
  PERFORM public._casa_notificar(c.user_id, 'handyman', 'casa_status',
    CASE p_acao WHEN 'aprovar' THEN 'Ofício aprovado: ' WHEN 'recusar' THEN 'Ofício recusado: '
                ELSE 'Ofício suspenso: ' END || o.nome,
    CASE WHEN p_acao = 'aprovar' THEN 'Já podes receber trabalhos de ' || o.nome || '.' ELSE v_motivo END, NULL);
  RETURN jsonb_build_object('ok', true, 'antes', po.estado, 'depois', v_novo);
END $$;

-- aprovar | recusar um documento (com a validade que o Danilo confere no papel).
CREATE OR REPLACE FUNCTION public.admin_casa_decidir_documento(p_documento_id uuid, p_acao text, p_motivo text DEFAULT NULL, p_validade date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE d casa_documentos; v_user uuid; v_val date; v_motivo text;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO d FROM casa_documentos WHERE id = p_documento_id FOR UPDATE;
  IF d.id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  SELECT user_id INTO v_user FROM casa_profissionais WHERE id = d.profissional_id;
  IF p_acao = 'aprovar' THEN
    v_val := COALESCE(p_validade, d.validade);
    IF v_val IS NOT NULL AND v_val < (now() AT TIME ZONE 'Europe/Lisbon')::date THEN
      RAISE EXCEPTION 'validade_passada';
    END IF;
    UPDATE casa_documentos
       SET estado = 'approved', validade = v_val, decidido_por = auth.uid(), decidido_em = now(),
           motivo = NULL, aviso_caducar_em = NULL
     WHERE id = d.id;
  ELSIF p_acao = 'recusar' THEN
    v_motivo := public._casa_motivo(p_motivo);
    UPDATE casa_documentos
       SET estado = 'rejected', decidido_por = auth.uid(), decidido_em = now(), motivo = v_motivo
     WHERE id = d.id;
  ELSE
    RAISE EXCEPTION 'acao_invalida';
  END IF;
  PERFORM public.log_admin_action(('casa_documento_' || p_acao)::text, 'casa_documentos'::text, d.id::text,
    jsonb_build_object('profissional_id', d.profissional_id, 'tipo', d.tipo, 'oficio', d.oficio,
                       'antes', d.estado, 'validade', v_val, 'motivo', v_motivo));
  PERFORM public._casa_notificar(v_user, 'handyman', 'casa_status',
    CASE WHEN p_acao = 'aprovar' THEN 'Documento aprovado' ELSE 'Documento recusado' END,
    CASE WHEN p_acao = 'aprovar' THEN 'Recebemos e aprovámos o teu documento.'
         ELSE v_motivo || '. Envia de novo na app.' END, NULL);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Chaves aceites: service_radius_km, has_van, has_tools, bio, base_address, base_lat, base_lng.
CREATE OR REPLACE FUNCTION public.admin_casa_editar_profissional(p_id uuid, p_dados jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE c casa_profissionais; n casa_profissionais;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_dados IS NULL OR jsonb_typeof(p_dados) <> 'object' THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  SELECT * INTO c FROM casa_profissionais WHERE id = p_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional'; END IF;
  BEGIN
    UPDATE casa_profissionais SET
      service_radius_km = CASE WHEN p_dados ? 'service_radius_km'
                               THEN (p_dados ->> 'service_radius_km')::numeric ELSE service_radius_km END,
      has_van   = CASE WHEN p_dados ? 'has_van'   THEN COALESCE((p_dados ->> 'has_van')::boolean, has_van) ELSE has_van END,
      has_tools = CASE WHEN p_dados ? 'has_tools' THEN COALESCE((p_dados ->> 'has_tools')::boolean, has_tools) ELSE has_tools END,
      bio = CASE WHEN p_dados ? 'bio' THEN left(COALESCE(p_dados ->> 'bio', ''), 1000) ELSE bio END,
      base_address = CASE WHEN p_dados ? 'base_address' THEN left(COALESCE(p_dados ->> 'base_address', ''), 500) ELSE base_address END,
      base_lat = CASE WHEN p_dados ? 'base_lat' THEN (p_dados ->> 'base_lat')::double precision ELSE base_lat END,
      base_lng = CASE WHEN p_dados ? 'base_lng' THEN (p_dados ->> 'base_lng')::double precision ELSE base_lng END
     WHERE id = c.id
    RETURNING * INTO n;
  EXCEPTION WHEN data_exception OR check_violation OR not_null_violation THEN
    RAISE EXCEPTION 'valor_invalido';
  END;
  PERFORM public.log_admin_action('casa_profissional_editar'::text, 'casa_profissionais'::text, c.id::text,
    jsonb_build_object('chaves', (SELECT jsonb_agg(k) FROM jsonb_object_keys(p_dados) k),
                       'antes', jsonb_build_object('service_radius_km', c.service_radius_km, 'has_van', c.has_van,
                                  'has_tools', c.has_tools, 'base_address', c.base_address,
                                  'base_lat', c.base_lat, 'base_lng', c.base_lng),
                       'depois', jsonb_build_object('service_radius_km', n.service_radius_km, 'has_van', n.has_van,
                                  'has_tools', n.has_tools, 'base_address', n.base_address,
                                  'base_lat', n.base_lat, 'base_lng', n.base_lng)));
  RETURN jsonb_build_object('ok', true);
END $$;

-- 3) Pedidos ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_pedidos(p_estado text DEFAULT NULL, p_limite integer DEFAULT 200)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(public._casa_pedido_json(x.id, 'admin')
                     || jsonb_build_object('cliente_nome', x.cliente_nome, 'profissional_nome', x.prof_nome)
                     ORDER BY x.created_at DESC)
      FROM (SELECT b.id, b.created_at, public._casa_nome_cliente(b.client_user_id) AS cliente_nome,
                   (SELECT c.name FROM casa_profissionais c WHERE c.id = b.profissional_id) AS prof_nome
              FROM casa_pedidos b
             WHERE p_estado IS NULL OR p_estado IN ('', 'todos') OR b.estado = p_estado
             ORDER BY b.created_at DESC
             LIMIT LEAST(GREATEST(COALESCE(p_limite, 200), 1), 500)) x), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_pedido(p_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos; v jsonb;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO b FROM casa_pedidos WHERE id = p_id;
  IF b.id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  v := public._casa_pedido_json(b.id, 'admin');
  RETURN v || jsonb_build_object(
    'cliente_nome', public._casa_nome_cliente(b.client_user_id),
    'profissional_nome', (SELECT c.name FROM casa_profissionais c WHERE c.id = b.profissional_id),
    'cliente', COALESCE((SELECT jsonb_build_object('nome', COALESCE(NULLIF(u.name, ''), split_part(u.email, '@', 1)),
                                                   'email', u.email, 'phone', NULLIF(u.phone, ''))
                           FROM users u WHERE u.id = b.client_user_id), v -> 'cliente'),
    'eventos', COALESCE((SELECT jsonb_agg(jsonb_build_object('estado_de', e.estado_de, 'estado_para', e.estado_para,
                           'por_papel', e.por_papel, 'detalhe', e.detalhe, 'created_at', e.created_at)
                           ORDER BY e.created_at, e.id)
                         FROM casa_pedido_eventos e WHERE e.pedido_id = b.id), '[]'::jsonb),
    'ofertas', COALESCE((SELECT jsonb_agg(jsonb_build_object('profissional_id', o.profissional_id,
                           'profissional_nome', c.name, 'tipo', o.tipo, 'enviada_em', o.enviada_em,
                           'expira_em', o.expira_em, 'tinha_aparelho', o.tinha_aparelho, 'resposta', o.resposta,
                           'respondida_em', o.respondida_em, 'ronda', o.ronda) ORDER BY o.enviada_em, o.id)
                         FROM casa_ofertas o LEFT JOIN casa_profissionais c ON c.id = o.profissional_id
                        WHERE o.pedido_id = b.id), '[]'::jsonb),
    'mensagens', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', m.id, 'sender_role', m.sender_role,
                           'message', m.message, 'created_at', m.created_at) ORDER BY m.created_at)
                         FROM casa_mensagens m WHERE m.pedido_id = b.id), '[]'::jsonb));
END $$;

-- Passa o pedido a outro profissional aprovado no ofício. A janela semanal não trava (o Danilo combinou
-- com ele), mas um trabalho já marcado à mesma hora trava.
CREATE OR REPLACE FUNCTION public.admin_casa_reatribuir(p_pedido_id uuid, p_profissional_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos; c casa_profissionais; v_antigo uuid; v_pct numeric; v_ganho int;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado NOT IN ('procura','aceite','a_caminho','chegou') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF b.modo = 'orcamento' AND b.orcamento_aceite_id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  IF b.payment_method IN ('card','mbway') AND b.payment_status NOT IN ('held','released') THEN
    RAISE EXCEPTION 'estado_invalido';
  END IF;
  SELECT * INTO c FROM casa_profissionais WHERE id = p_profissional_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'nao_e_profissional'; END IF;
  IF b.profissional_id = c.id THEN RETURN public._casa_pedido_json(b.id, 'admin'); END IF;
  IF c.approval_status <> 'approved' OR NOT c.is_active OR c.user_id = b.client_user_id
     OR NOT EXISTS (SELECT 1 FROM casa_profissional_oficios po
                     WHERE po.profissional_id = c.id AND po.oficio = b.oficio AND po.estado = 'approved') THEN
    RAISE EXCEPTION 'profissional_sem_oficio';
  END IF;
  IF EXISTS (SELECT 1 FROM casa_oficios o WHERE o.codigo = b.oficio AND o.documento_exigido IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM casa_documentos d
                                WHERE d.profissional_id = c.id AND d.tipo = o.documento_exigido AND d.estado = 'approved'
                                  AND (d.validade IS NULL OR d.validade >= (now() AT TIME ZONE 'Europe/Lisbon')::date))) THEN
    RAISE EXCEPTION 'documento_em_falta';
  END IF;
  IF EXISTS (SELECT 1 FROM casa_pedidos x
              WHERE x.profissional_id = c.id AND x.id <> b.id AND x.estado IN ('aceite','a_caminho','chegou','em_curso')
                AND tstzrange(x.scheduled_at, x.scheduled_at + make_interval(mins => x.duracao_min))
                    && tstzrange(b.scheduled_at, b.scheduled_at + make_interval(mins => b.duracao_min))) THEN
    RAISE EXCEPTION 'profissional_ocupado';
  END IF;

  v_antigo := b.profissional_id;
  v_pct := public._casa_pct_do(c.id);
  v_ganho := b.total_cents - round(b.total_cents * v_pct / 100.0)::int;
  UPDATE casa_pedidos
     SET profissional_id = c.id, estado = 'aceite', accepted_at = now(), on_the_way_at = NULL, arrived_at = NULL,
         comissao_pct = v_pct, offer_profissional_id = NULL, offer_expires_at = NULL,
         reminder_24h_sent_at = NULL, reminder_2h_sent_at = NULL, stuck_alerted_at = NULL
   WHERE id = b.id;
  UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now() WHERE pedido_id = b.id AND resposta IS NULL;
  IF b.offer_profissional_id IS NOT NULL THEN
    BEGIN PERFORM public.fechar_oferta(b.id, b.offer_profissional_id, 'reatribuida'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  PERFORM public._casa_evento(b.id, b.estado, 'aceite', 'admin',
                              jsonb_build_object('reatribuido_de', v_antigo, 'para', c.id));
  PERFORM public.log_admin_action('casa_pedido_reatribuir'::text, 'casa_pedidos'::text, b.id::text,
    jsonb_build_object('estado_antes', b.estado, 'de', v_antigo, 'para', c.id));

  PERFORM public._casa_notificar(c.user_id, 'handyman', 'casa_status', 'Trabalho Casa atribuído',
    COALESCE((SELECT s.nome FROM casa_servicos s WHERE s.id = b.servico_id), 'Trabalho') || ' em '
    || COALESCE(NULLIF(b.address_city, ''), 'Guarda') || ' a '
    || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
    || ' — ganhas ' || public._casa_euro(v_ganho) || '. Vê os detalhes na app.', b.id);
  IF v_antigo IS NOT NULL THEN
    PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = v_antigo), 'handyman', 'casa_status',
      'Trabalho reatribuído',
      'O trabalho de ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
      || ' passou para outro profissional.', b.id);
  END IF;
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'O teu pedido tem profissional',
    c.name || ' vai fazer o trabalho a ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') || '.',
    b.id);
  RETURN public._casa_pedido_json(b.id, 'admin');
END $$;

-- Cancela pelo Bora. Se havia pagamento retido, só marca reembolso_pendente (o Danilo decide).
CREATE OR REPLACE FUNCTION public.admin_casa_cancelar(p_pedido_id uuid, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos; v_motivo text := public._casa_motivo(p_motivo); v_reemb boolean;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado IN ('confirmado','cancelado','expirado') THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  v_reemb := b.reembolso_pendente OR b.payment_status = 'held';
  UPDATE casa_pedidos
     SET estado = 'cancelado', cancelled_at = now(), cancelled_by = 'admin', cancel_reason = left(v_motivo, 500),
         offer_profissional_id = NULL, offer_expires_at = NULL, reembolso_pendente = v_reemb
   WHERE id = b.id;
  UPDATE casa_orcamentos SET estado = 'recusado', decidido_em = now() WHERE pedido_id = b.id AND estado = 'enviado';
  UPDATE casa_extras SET estado = 'recusado', respondido_em = now() WHERE pedido_id = b.id AND estado = 'pedido';
  UPDATE casa_ofertas SET resposta = 'expirada', respondida_em = now() WHERE pedido_id = b.id AND resposta IS NULL;
  IF b.offer_profissional_id IS NOT NULL THEN
    BEGIN PERFORM public.fechar_oferta(b.id, b.offer_profissional_id, 'cancelada'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  PERFORM public._casa_evento(b.id, b.estado, 'cancelado', 'admin',
                              jsonb_build_object('motivo', v_motivo, 'reembolso_pendente', v_reemb));
  PERFORM public.log_admin_action('casa_pedido_cancelar'::text, 'casa_pedidos'::text, b.id::text,
    jsonb_build_object('estado_antes', b.estado, 'motivo', v_motivo, 'payment_status', b.payment_status,
                       'reembolso_pendente', v_reemb));
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Pedido cancelado',
    'O teu pedido Casa foi cancelado pelo Bora. Vamos contactar-te se for preciso.', b.id);
  IF b.profissional_id IS NOT NULL THEN
    PERFORM public._casa_notificar((SELECT user_id FROM casa_profissionais WHERE id = b.profissional_id),
      'handyman', 'casa_status', 'Trabalho cancelado',
      'O trabalho de ' || to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
      || ' foi cancelado pelo Bora.', b.id);
  END IF;
  RETURN jsonb_build_object('ok', true, 'reembolso_pendente', v_reemb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_marcar_teste(p_pedido_id uuid, p_is_test boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  UPDATE casa_pedidos SET is_test_order = COALESCE(p_is_test, false) WHERE id = b.id;
  PERFORM public._casa_evento(b.id, b.estado, b.estado, 'admin', jsonb_build_object('is_test', COALESCE(p_is_test, false)));
  PERFORM public.log_admin_action('casa_pedido_marcar_teste'::text, 'casa_pedidos'::text, b.id::text,
    jsonb_build_object('antes', b.is_test_order, 'depois', COALESCE(p_is_test, false)));
  RETURN jsonb_build_object('ok', true, 'is_test', COALESCE(p_is_test, false));
END $$;

-- Dá o trabalho por feito e confirmado (o mesmo caminho da confirmação do cliente).
CREATE OR REPLACE FUNCTION public.admin_casa_forcar_conclusao(p_pedido_id uuid, p_motivo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos; v_motivo text := public._casa_motivo(p_motivo);
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.profissional_id IS NULL
     OR b.estado NOT IN ('aceite','a_caminho','chegou','em_curso','concluido','disputa') THEN
    RAISE EXCEPTION 'estado_invalido';
  END IF;
  UPDATE casa_extras SET estado = 'recusado', respondido_em = now() WHERE pedido_id = b.id AND estado = 'pedido';
  IF b.estado = 'disputa' AND b.confirmed_at IS NOT NULL THEN
    -- Já tinha sido confirmado antes da disputa: volta a confirmado sem contar outra vez.
    UPDATE casa_pedidos SET estado = 'confirmado' WHERE id = b.id;
    PERFORM public._casa_evento(b.id, b.estado, 'confirmado', 'admin', jsonb_build_object('forcado', true, 'motivo', v_motivo));
  ELSE
    IF b.estado <> 'concluido' THEN
      UPDATE casa_pedidos SET estado = 'concluido', done_at = COALESCE(done_at, now()) WHERE id = b.id;
    END IF;
    PERFORM public._casa_evento(b.id, b.estado, 'concluido', 'admin', jsonb_build_object('forcado', true, 'motivo', v_motivo));
    PERFORM public._casa_confirmar(b.id, true);
  END IF;
  PERFORM public.log_admin_action('casa_pedido_forcar_conclusao'::text, 'casa_pedidos'::text, b.id::text,
    jsonb_build_object('estado_antes', b.estado, 'motivo', v_motivo));
  RETURN public._casa_pedido_json(b.id, 'admin');
END $$;

-- refeito | sem_razao | reembolso_pendente (este só marca; o dinheiro é decisão do Danilo e o pedido
-- fica fora do acerto semanal enquanto reembolso_pendente for true).
CREATE OR REPLACE FUNCTION public.admin_casa_resolver_disputa(p_pedido_id uuid, p_resolucao text, p_nota text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE b casa_pedidos; v_nota text := left(btrim(COALESCE(p_nota, '')), 1000); v_det jsonb;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_resolucao IS NULL OR p_resolucao NOT IN ('refeito','sem_razao','reembolso_pendente') THEN
    RAISE EXCEPTION 'acao_invalida';
  END IF;
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado <> 'disputa' THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  v_det := jsonb_build_object('resolucao', p_resolucao, 'nota', v_nota);
  IF p_resolucao = 'reembolso_pendente' THEN
    UPDATE casa_pedidos SET reembolso_pendente = true WHERE id = b.id;
  END IF;
  IF b.confirmed_at IS NOT NULL THEN
    UPDATE casa_pedidos SET estado = 'confirmado' WHERE id = b.id;
    PERFORM public._casa_evento(b.id, 'disputa', 'confirmado', 'admin', v_det);
  ELSE
    UPDATE casa_pedidos SET estado = 'concluido', done_at = COALESCE(done_at, now()) WHERE id = b.id;
    PERFORM public._casa_evento(b.id, 'disputa', 'concluido', 'admin', v_det);
    PERFORM public._casa_confirmar(b.id, true);
  END IF;
  PERFORM public.log_admin_action('casa_disputa_resolver'::text, 'casa_pedidos'::text, b.id::text, v_det);
  PERFORM public._casa_notificar(b.client_user_id, 'client', 'casa_status', 'Pedido revisto',
    CASE p_resolucao
      WHEN 'refeito' THEN 'O trabalho foi refeito. Obrigado pela paciência.'
      WHEN 'sem_razao' THEN 'Revimos o teu pedido e o trabalho fica como está. Se precisares, fala connosco.'
      ELSE 'Revimos o teu pedido. Vamos contactar-te sobre o valor.' END, b.id);
  RETURN jsonb_build_object('ok', true, 'resolucao', p_resolucao);
END $$;

-- 4) Orçamentos e registo de ofertas ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_orcamentos(p_estado text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', q.id, 'pedido_id', q.pedido_id, 'pedido_estado', b.estado, 'servico_nome', s.nome,
      'profissional_id', q.profissional_id, 'profissional_nome', c.name, 'preco_cents', q.preco_cents,
      'estado', q.estado, 'expira_em', q.expira_em, 'created_at', q.created_at,
      'tempo_resposta_min', (SELECT round(extract(epoch FROM (q.created_at - min(o.enviada_em))) / 60.0)::int
                               FROM casa_ofertas o
                              WHERE o.pedido_id = q.pedido_id AND o.profissional_id = q.profissional_id
                                AND o.tipo = 'convite_orcamento'),
      'ganhou', COALESCE(q.estado = 'aceite' OR b.orcamento_aceite_id = q.id, false))
      ORDER BY q.created_at DESC)
      FROM (SELECT * FROM casa_orcamentos
             WHERE p_estado IS NULL OR p_estado IN ('', 'todos') OR estado = p_estado
             ORDER BY created_at DESC LIMIT 500) q
      JOIN casa_pedidos b ON b.id = q.pedido_id
      LEFT JOIN casa_servicos s ON s.id = b.servico_id
      LEFT JOIN casa_profissionais c ON c.id = q.profissional_id), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_ofertas(p_pedido_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id', o.id, 'pedido_id', o.pedido_id, 'profissional_id', o.profissional_id,
             'profissional_nome', c.name, 'tipo', o.tipo, 'enviada_em', o.enviada_em, 'expira_em', o.expira_em,
             'tinha_aparelho', o.tinha_aparelho, 'resposta', o.resposta, 'respondida_em', o.respondida_em,
             'ronda', o.ronda) ORDER BY o.enviada_em DESC, o.id DESC)
      FROM (SELECT * FROM casa_ofertas WHERE p_pedido_id IS NULL OR pedido_id = p_pedido_id
             ORDER BY enviada_em DESC LIMIT 500) o
      LEFT JOIN casa_profissionais c ON c.id = o.profissional_id), '[]'::jsonb);
END $$;

-- 5) Catálogo, definições, interruptor e "autorizo" ------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_catalogo()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN jsonb_build_object(
    'oficios', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.ordem, o.codigo) FROM casa_oficios o), '[]'::jsonb),
    'servicos', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.oficio, s.ordem, s.nome) FROM casa_servicos s), '[]'::jsonb),
    'valores_autorizados', COALESCE((SELECT value FROM platform_settings WHERE key = 'casa_valores_autorizados'),
                                    jsonb_build_object('autorizado', false)));
END $$;

-- p_id null = serviço novo. Mudar o preço ou o modo volta a pôr os valores como PROPOSTA.
CREATE OR REPLACE FUNCTION public.admin_casa_guardar_servico(p_id uuid, p_dados jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE s casa_servicos; v_antes jsonb; v_modo text; v_preco int; v_mudou boolean := false; v_reaberto boolean := false;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_dados IS NULL OR jsonb_typeof(p_dados) <> 'object' THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  IF p_dados ? 'oficio' AND NOT EXISTS (SELECT 1 FROM casa_oficios WHERE codigo = p_dados ->> 'oficio') THEN
    RAISE EXCEPTION 'oficio_invalido';
  END IF;
  BEGIN
    IF p_id IS NULL THEN
      IF NOT (p_dados ? 'oficio') OR NULLIF(btrim(COALESCE(p_dados ->> 'nome', '')), '') IS NULL THEN
        RAISE EXCEPTION 'valor_invalido';
      END IF;
      v_modo := COALESCE(p_dados ->> 'modo', 'fixo');
      v_preco := CASE WHEN v_modo = 'orcamento' THEN NULL ELSE (p_dados ->> 'preco_cents')::int END;
      INSERT INTO casa_servicos (oficio, nome, descricao, modo, preco_cents, unidade, min_quantidade, max_quantidade,
                                 duracao_min, perguntas, ativo, ordem, updated_by)
      VALUES (p_dados ->> 'oficio', btrim(p_dados ->> 'nome'), left(COALESCE(p_dados ->> 'descricao', ''), 1000),
              v_modo, v_preco, COALESCE(p_dados ->> 'unidade', 'tarefa'),
              COALESCE((p_dados ->> 'min_quantidade')::numeric, 1), COALESCE((p_dados ->> 'max_quantidade')::numeric, 10),
              COALESCE((p_dados ->> 'duracao_min')::int, 60),
              CASE WHEN jsonb_typeof(p_dados -> 'perguntas') = 'array' THEN p_dados -> 'perguntas' ELSE '[]'::jsonb END,
              COALESCE((p_dados ->> 'ativo')::boolean, true), COALESCE((p_dados ->> 'ordem')::int, 0), auth.uid())
      RETURNING * INTO s;
      v_mudou := v_preco IS NOT NULL;
    ELSE
      SELECT * INTO s FROM casa_servicos WHERE id = p_id FOR UPDATE;
      IF s.id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
      v_antes := to_jsonb(s);
      v_modo := COALESCE(p_dados ->> 'modo', s.modo);
      v_preco := CASE WHEN v_modo = 'orcamento' THEN NULL
                      WHEN p_dados ? 'preco_cents' THEN (p_dados ->> 'preco_cents')::int
                      ELSE s.preco_cents END;
      v_mudou := v_preco IS DISTINCT FROM s.preco_cents OR v_modo IS DISTINCT FROM s.modo;
      UPDATE casa_servicos SET
        oficio = COALESCE(p_dados ->> 'oficio', oficio),
        nome = COALESCE(NULLIF(btrim(COALESCE(p_dados ->> 'nome', '')), ''), nome),
        descricao = CASE WHEN p_dados ? 'descricao' THEN left(COALESCE(p_dados ->> 'descricao', ''), 1000) ELSE descricao END,
        modo = v_modo, preco_cents = v_preco,
        unidade = COALESCE(p_dados ->> 'unidade', unidade),
        min_quantidade = COALESCE((p_dados ->> 'min_quantidade')::numeric, min_quantidade),
        max_quantidade = COALESCE((p_dados ->> 'max_quantidade')::numeric, max_quantidade),
        duracao_min = COALESCE((p_dados ->> 'duracao_min')::int, duracao_min),
        perguntas = CASE WHEN jsonb_typeof(p_dados -> 'perguntas') = 'array' THEN p_dados -> 'perguntas' ELSE perguntas END,
        ativo = COALESCE((p_dados ->> 'ativo')::boolean, ativo),
        ordem = COALESCE((p_dados ->> 'ordem')::int, ordem),
        updated_at = now(), updated_by = auth.uid()
       WHERE id = s.id
      RETURNING * INTO s;
    END IF;
  EXCEPTION WHEN data_exception OR check_violation OR not_null_violation THEN
    RAISE EXCEPTION 'valor_invalido';
  END;
  IF v_mudou THEN v_reaberto := public._casa_reabrir_valores('servico ' || s.nome); END IF;
  PERFORM public.log_admin_action(CASE WHEN p_id IS NULL THEN 'casa_servico_criar' ELSE 'casa_servico_guardar' END::text,
    'casa_servicos'::text, s.id::text,
    jsonb_build_object('antes', v_antes, 'depois', to_jsonb(s), 'valor_mudou', v_mudou, 'valores_reabertos', v_reaberto));
  RETURN jsonb_build_object('id', s.id, 'valor_mudou', v_mudou, 'valores_reabertos', v_reaberto);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_guardar_oficio(p_codigo text, p_ativo boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o casa_oficios;
BEGIN
  PERFORM public._casa_exigir_admin();
  SELECT * INTO o FROM casa_oficios WHERE codigo = p_codigo FOR UPDATE;
  IF o.codigo IS NULL THEN RAISE EXCEPTION 'oficio_invalido'; END IF;
  UPDATE casa_oficios SET ativo = COALESCE(p_ativo, false), updated_at = now(), updated_by = auth.uid()
   WHERE codigo = o.codigo;
  PERFORM public.log_admin_action('casa_oficio_catalogo'::text, 'casa_oficios'::text, o.codigo::text,
    jsonb_build_object('antes', o.ativo, 'depois', COALESCE(p_ativo, false), 'fase', o.fase));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_definicoes()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._casa_exigir_admin();
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'description', s.description,
                                                       'updated_at', s.updated_at) ORDER BY s.key)
                     FROM platform_settings s
                    WHERE left(s.key, 5) = 'casa_' AND NOT COALESCE(s.is_secret, false)), '[]'::jsonb);
END $$;

-- casa_enabled só pelo interruptor; casa_valores_autorizados só pelo "autorizo". O valor novo tem de ter o
-- mesmo tipo do antigo. Mudar a percentagem ou a promoção volta a pôr os valores como PROPOSTA.
CREATE OR REPLACE FUNCTION public.admin_casa_guardar_definicao(p_key text, p_value jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_antes jsonb; v_reaberto boolean := false;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_key = 'casa_enabled' THEN RAISE EXCEPTION 'usar_interruptor'; END IF;
  IF p_key IS NULL OR left(p_key, 5) <> 'casa_' OR p_key = 'casa_valores_autorizados' THEN
    RAISE EXCEPTION 'chave_invalida';
  END IF;
  SELECT value INTO v_antes FROM platform_settings WHERE key = p_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'chave_invalida'; END IF;
  IF p_value IS NULL OR jsonb_typeof(p_value) IS DISTINCT FROM jsonb_typeof(v_antes) THEN
    RAISE EXCEPTION 'valor_invalido';
  END IF;
  IF jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}')::numeric < 0 THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  IF p_key = 'casa_bora_pct' AND (p_value #>> '{}')::numeric > 100 THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  IF p_key = 'casa_testadores' AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_value) x
        WHERE jsonb_typeof(x) <> 'string'
           OR (x #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
    RAISE EXCEPTION 'valor_invalido';
  END IF;
  UPDATE platform_settings SET value = p_value, updated_at = now(), updated_by = auth.uid() WHERE key = p_key;
  IF (p_key = 'casa_bora_pct' OR left(p_key, 11) = 'casa_promo_' OR position('comissao' in p_key) > 0)
     AND v_antes IS DISTINCT FROM p_value THEN
    v_reaberto := public._casa_reabrir_valores('definicao ' || p_key);
  END IF;
  PERFORM public.log_admin_action('casa_definicao_guardar'::text, 'platform_settings'::text, p_key::text,
    jsonb_build_object('antes', v_antes, 'depois', p_value, 'valores_reabertos', v_reaberto));
  RETURN jsonb_build_object('ok', true, 'valores_reabertos', v_reaberto);
END $$;

-- Só o Danilo usa, pelo painel, com o texto dele (tem de conter "autorizo"). Guarda o texto, a data, quem
-- e uma fotografia dos valores autorizados (percentagem, promoção e preços do catálogo).
CREATE OR REPLACE FUNCTION public.admin_casa_autorizar_valores(p_texto text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_txt text := btrim(COALESCE(p_texto, '')); v_antes jsonb; v_novo jsonb;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF position('autorizo' in lower(v_txt)) = 0 THEN RAISE EXCEPTION 'texto_sem_autorizo'; END IF;
  SELECT value INTO v_antes FROM platform_settings WHERE key = 'casa_valores_autorizados' FOR UPDATE;
  v_novo := jsonb_build_object(
    'autorizado', true, 'em', now(), 'por', auth.uid(), 'texto', left(v_txt, 2000),
    'valores', jsonb_build_object(
      'casa_bora_pct', (SELECT value FROM platform_settings WHERE key = 'casa_bora_pct'),
      'casa_promo_primeiros_n', (SELECT value FROM platform_settings WHERE key = 'casa_promo_primeiros_n'),
      'casa_promo_meses', (SELECT value FROM platform_settings WHERE key = 'casa_promo_meses'),
      'servicos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'modo', s.modo,
                                       'unidade', s.unidade, 'preco_cents', s.preco_cents) ORDER BY s.oficio, s.ordem)
                              FROM casa_servicos s WHERE s.preco_cents IS NOT NULL), '[]'::jsonb)));
  UPDATE platform_settings SET value = v_novo, updated_at = now(), updated_by = auth.uid()
   WHERE key = 'casa_valores_autorizados';
  IF NOT FOUND THEN
    INSERT INTO platform_settings (key, value, description, category, updated_by)
    VALUES ('casa_valores_autorizados', v_novo,
            'Preços do catálogo, percentagem e promoção da Casa só valem com o autorizo datado do Danilo', 'casa', auth.uid());
  END IF;
  PERFORM public.log_admin_action('casa_valores_autorizar'::text, 'platform_settings'::text,
                                  'casa_valores_autorizados'::text,
                                  jsonb_build_object('antes', v_antes, 'depois', v_novo));
  RETURN jsonb_build_object('ok', true, 'em', v_novo -> 'em');
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_interruptor(p_ligado boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_antes boolean := public._casa_bool('casa_enabled', false); v_novo boolean := COALESCE(p_ligado, false);
BEGIN
  PERFORM public._casa_exigir_admin();
  UPDATE platform_settings SET value = to_jsonb(v_novo), updated_at = now(), updated_by = auth.uid()
   WHERE key = 'casa_enabled';
  IF NOT FOUND THEN
    INSERT INTO platform_settings (key, value, description, category, updated_by)
    VALUES ('casa_enabled', to_jsonb(v_novo), 'Interruptor geral da categoria Casa. Nasce DESLIGADO.', 'casa', auth.uid());
  END IF;
  PERFORM public.log_admin_action('casa_interruptor'::text, 'platform_settings'::text, 'casa_enabled'::text,
    jsonb_build_object('antes', v_antes, 'depois', v_novo, 'valores_autorizados', public._casa_valores_validos()));
  RETURN jsonb_build_object('ok', true, 'enabled', v_novo);
END $$;

-- 6) Acertos semanais (só calcular e marcar estado) e exportar -----------------------------------
CREATE OR REPLACE FUNCTION public.admin_casa_acertos(p_week_start date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_week_start IS NOT NULL THEN
    v_ini := date_trunc('week', p_week_start::timestamp) AT TIME ZONE 'Europe/Lisbon';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(a) || jsonb_build_object('profissional_nome', c.name) ORDER BY a.week_start_at DESC, c.name)
      FROM casa_acertos_semanais a LEFT JOIN casa_profissionais c ON c.id = a.profissional_id
     WHERE (v_ini IS NULL AND a.week_start_at >= now() - interval '12 weeks') OR a.week_start_at = v_ini), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_casa_calcular_acertos(p_week_start date)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz; v jsonb; n int;
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_week_start IS NULL THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  IF NOT public._casa_valores_validos() THEN RAISE EXCEPTION 'valores_por_autorizar'; END IF;
  v_ini := date_trunc('week', p_week_start::timestamp) AT TIME ZONE 'Europe/Lisbon';
  v := public.casa_calcular_acertos_todos(v_ini);
  SELECT count(*) INTO n FROM casa_acertos_semanais WHERE week_start_at = v_ini;
  PERFORM public.log_admin_action('casa_acertos_calcular'::text, 'casa_acertos_semanais'::text, v_ini::date::text,
    v || jsonb_build_object('linhas', n));
  RETURN v || jsonb_build_object('criados', n, 'semana', v_ini);
END $$;

-- Só marca o estado do acerto (pago/recebido/disputa/pendente) e a referência. Não move dinheiro.
CREATE OR REPLACE FUNCTION public.admin_casa_acerto_marcar(p_id uuid, p_status text, p_payment_method text DEFAULT NULL, p_reference text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE a casa_acertos_semanais; v_metodo text := NULLIF(btrim(COALESCE(p_payment_method, '')), '');
        v_ref text := NULLIF(btrim(COALESCE(p_reference, '')), '');
BEGIN
  PERFORM public._casa_exigir_admin();
  IF p_status IS NULL OR p_status NOT IN ('pending','paid','received','disputed') THEN RAISE EXCEPTION 'acao_invalida'; END IF;
  IF v_metodo IS NOT NULL AND v_metodo NOT IN ('transferencia','mbway','dinheiro') THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  SELECT * INTO a FROM casa_acertos_semanais WHERE id = p_id FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'estado_invalido'; END IF;
  UPDATE casa_acertos_semanais
     SET status = p_status,
         payment_method = COALESCE(v_metodo, payment_method),
         payment_reference = COALESCE(left(v_ref, 200), payment_reference),
         paid_at = CASE WHEN p_status IN ('paid','received') THEN COALESCE(paid_at, now()) ELSE NULL END,
         paid_by = CASE WHEN p_status IN ('paid','received') THEN auth.uid() ELSE NULL END
   WHERE id = a.id;
  PERFORM public.log_admin_action('casa_acerto_marcar'::text, 'casa_acertos_semanais'::text, a.id::text,
    jsonb_build_object('antes', a.status, 'depois', p_status, 'metodo', v_metodo, 'referencia', v_ref,
                       'net_payout_cents', a.net_payout_cents, 'direction', a.direction));
  IF p_status IN ('paid','received') AND a.status NOT IN ('paid','received') THEN
    PERFORM public._casa_notificar(a.user_id, 'handyman', 'casa_status', 'Acerto semanal',
      CASE WHEN a.direction = 'bora_to_handyman'
           THEN 'O Bora registou o pagamento de ' || public._casa_euro(a.net_payout_cents)
                || ' da semana de ' || to_char(a.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '.'
           ELSE 'Registámos o acerto da semana de ' || to_char(a.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '. Obrigado.'
      END, NULL);
  END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

-- Linhas planas para CSV. pedidos: criados entre as datas (Lisboa); ganhos: confirmados entre as datas;
-- profissionais: todos (as datas não se aplicam). Sem IBAN, sem referências de pagamento.
CREATE OR REPLACE FUNCTION public.admin_casa_exportar(p_tipo text, p_de date, p_ate date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_de timestamptz := COALESCE(p_de, v_hoje - 30)::timestamp AT TIME ZONE 'Europe/Lisbon';
  v_ate timestamptz := (COALESCE(p_ate, v_hoje) + 1)::timestamp AT TIME ZONE 'Europe/Lisbon';
BEGIN
  PERFORM public._casa_exigir_admin();
  IF v_ate <= v_de THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  IF p_tipo = 'pedidos' THEN
    RETURN COALESCE((
      SELECT jsonb_agg((to_jsonb(b) - ARRAY['respostas','offered_profissional_ids','idempotency_key','pagamento_ref'])
                       || jsonb_build_object('servico_nome', s.nome, 'cliente_nome', public._casa_nome_cliente(b.client_user_id),
                                             'profissional_nome', c.name)
                       ORDER BY b.created_at)
        FROM casa_pedidos b
        LEFT JOIN casa_servicos s ON s.id = b.servico_id
        LEFT JOIN casa_profissionais c ON c.id = b.profissional_id
       WHERE b.created_at >= v_de AND b.created_at < v_ate), '[]'::jsonb);
  ELSIF p_tipo = 'ganhos' THEN
    RETURN COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'pedido_id', b.id, 'confirmado_em', b.confirmed_at, 'profissional_id', c.id, 'profissional_nome', c.name,
               'profissional_nif', c.nif, 'servico_nome', s.nome, 'oficio', b.oficio, 'payment_method', b.payment_method,
               'payment_status', b.payment_status, 'total_cents', b.total_cents, 'comissao_pct', b.comissao_pct,
               'comissao_cents', b.comissao_cents, 'ganho_cents', b.ganho_cents, 'is_test', b.is_test_order,
               'reembolso_pendente', b.reembolso_pendente) ORDER BY b.confirmed_at)
        FROM casa_pedidos b
        LEFT JOIN casa_servicos s ON s.id = b.servico_id
        LEFT JOIN casa_profissionais c ON c.id = b.profissional_id
       WHERE b.estado = 'confirmado' AND b.confirmed_at >= v_de AND b.confirmed_at < v_ate), '[]'::jsonb);
  ELSIF p_tipo = 'profissionais' THEN
    RETURN COALESCE((
      SELECT jsonb_agg((to_jsonb(c) - ARRAY['docs','iban'])
                       || jsonb_build_object('oficios', (SELECT string_agg(po.oficio || ':' || po.estado, ', ' ORDER BY po.oficio)
                                                           FROM casa_profissional_oficios po WHERE po.profissional_id = c.id))
                       ORDER BY c.created_at)
        FROM casa_profissionais c), '[]'::jsonb);
  END IF;
  RAISE EXCEPTION 'acao_invalida';
END $$;

-- 7) Permissões ------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._casa_exigir_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_motivo(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_reabrir_valores(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_nome_cliente(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._casa_euro(integer) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.admin_casa_resumo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_profissionais(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_profissional(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_decidir_profissional(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_decidir_oficio(uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_decidir_documento(uuid, text, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_editar_profissional(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_pedidos(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_pedido(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_reatribuir(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_cancelar(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_marcar_teste(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_forcar_conclusao(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_resolver_disputa(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_orcamentos(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_ofertas(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_catalogo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_guardar_servico(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_guardar_oficio(text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_definicoes() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_guardar_definicao(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_autorizar_valores(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_interruptor(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_acertos(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_calcular_acertos(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_acerto_marcar(uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_casa_exportar(text, date, date) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_casa_resumo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_profissionais(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_profissional(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_decidir_profissional(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_decidir_oficio(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_decidir_documento(uuid, text, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_editar_profissional(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_pedidos(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_pedido(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_reatribuir(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_cancelar(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_marcar_teste(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_forcar_conclusao(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_resolver_disputa(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_orcamentos(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_ofertas(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_catalogo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_guardar_servico(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_guardar_oficio(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_definicoes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_guardar_definicao(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_autorizar_valores(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_interruptor(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_acertos(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_calcular_acertos(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_acerto_marcar(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_casa_exportar(text, date, date) TO authenticated;
