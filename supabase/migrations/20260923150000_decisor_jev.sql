-- Missão jev-decisor-2026-09-23 — O DECISOR: decisões pequenas, tipadas e registadas.
--
-- Porquê: o Danilo mandou pôr o Jev (TypeSafe, modelo "System One") a funcionar, ou algo
-- parecido. O Jev não conversa: devolve uma decisão tipada (choice = escolher entre opções,
-- score = nota numa escala, noul = sim/não) com probabilidades. A Edge Function `decidir`
-- chama o Jev e, sem chave ou com erro, cai no Gemini com o MESMO contrato de saída.
--
-- O que esta migração cria:
--   1. `decisoes`  — cada decisão (pergunta, resposta, confiança, motor, latência, custo) e,
--      mais tarde, o que aconteceu de verdade (`resultado_real`) para medir o acerto.
--   2. Quatro interruptores `decisor_*_modo` em platform_settings (desligado | sombra | ativo),
--      todos a começar em SOMBRA: decide e regista, não manda em nada.
--   3. `decisor_itens_pendentes()` — o que cada regra ainda não decidiu, já com o estado
--      montado e anonimizado (os estafetas vão como estafeta_1, estafeta_2...).
--   4. `decisor_preencher_resultados()` — escreve `resultado_real` a partir das tabelas reais.
--   5. RPCs do painel: resumo de hoje (custo) e mudar o modo de uma regra (auditado).
--   6. Tarefa agendada de 30 em 30 s que chama `decidir` em modo varredura.
--
-- NADA aqui altera preços, taxas, comissões, tokens nem o motor de despacho. O despacho é só
-- OBSERVADO (lê orders/tvde_rides/drivers); o modo "ativo" do despacho não existe nesta
-- migração — ligar o decisor ao motor de despacho é zona 🔴 e fica como proposta.

-- ── 1. Tabela ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.decisoes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quando          timestamptz NOT NULL DEFAULT now(),
  tipo            text NOT NULL CHECK (tipo IN ('choice','score','noul')),
  pergunta        text NOT NULL,
  estado_resumo   text,
  resposta        text,
  confianca       numeric,
  probabilidades  jsonb,
  motor           text NOT NULL CHECK (motor IN ('jev','gemini','nenhum')),
  modelo          text,
  latencia_ms     integer,
  tokens_entrada  integer,
  tokens_saida    integer,
  custo_usd       numeric(14,8),
  usado_por       text NOT NULL,
  contexto_id     text,
  modo            text NOT NULL DEFAULT 'sombra' CHECK (modo IN ('sombra','ativo','teste')),
  mapa_opcoes     jsonb,          -- opção anónima -> id interno (nunca sai para o motor externo)
  acao_tomada     text,           -- só em modo ativo: o que o decisor fez de facto
  erro            text,
  resultado_real  text,
  resultado_em    timestamptz
);

COMMENT ON TABLE public.decisoes IS
  'Decisor (Jev/Gemini) — uma linha por decisão tipada. resultado_real preenchido depois por decisor_preencher_resultados(). Missão jev-decisor-2026-09-23.';

CREATE INDEX IF NOT EXISTS decisoes_quando_idx ON public.decisoes (quando DESC);
CREATE INDEX IF NOT EXISTS decisoes_usado_por_idx ON public.decisoes (usado_por, quando DESC);
-- Uma decisão por coisa e por regra (a varredura pode sobrepor-se; isto é a guarda).
CREATE UNIQUE INDEX IF NOT EXISTS decisoes_uma_por_contexto
  ON public.decisoes (usado_por, contexto_id)
  WHERE contexto_id IS NOT NULL AND modo IN ('sombra','ativo');

ALTER TABLE public.decisoes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS decisoes_admin_select ON public.decisoes;
CREATE POLICY decisoes_admin_select ON public.decisoes
  FOR SELECT TO authenticated USING (public.is_admin());
-- Escrita: só o serviço (service_role ignora RLS). Nenhuma policy de INSERT/UPDATE/DELETE.
REVOKE ALL ON public.decisoes FROM PUBLIC, anon;
GRANT SELECT ON public.decisoes TO authenticated;

-- ── 2. Interruptores e preços ────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('decisor_despacho_modo', '"sombra"'::jsonb,
   'Decisor: escolhe o melhor estafeta/motorista quando há 2+ candidatos. desligado|sombra (só regista). Ativo não existe: ligar ao motor de despacho é zona protegida.', 'decisor'),
  ('decisor_noshow_modo', '"sombra"'::jsonb,
   'Decisor: nota de risco de não-comparência ao criar uma marcação de serviço. desligado|sombra.', 'decisor'),
  ('decisor_robotb_modo', '"sombra"'::jsonb,
   'Decisor: "vale a pena abrir esta sugestão do Robot B?". desligado|sombra|ativo (ativo = arquiva como rejeitada a sugestão nova com sim < limiar).', 'decisor'),
  ('decisor_suporte_modo', '"sombra"'::jsonb,
   'Decisor: "esta mensagem do suporte deve passar a humano?". desligado|sombra.', 'decisor'),
  ('decisor_robotb_limiar', '0.25'::jsonb,
   'Decisor/Robot B em modo ativo: abaixo desta probabilidade de "vale a pena" a sugestão nova é arquivada.', 'decisor'),
  ('decisor_preco_jev_usd_mtok', '0.042'::jsonb,
   'Custo do Jev em USD por milhão de tokens de entrada (docs.typesafe.ai/models, 23/09/2026: 42 USD por mil milhões; saída grátis).', 'decisor'),
  ('decisor_preco_gemini_usd_mtok', '0'::jsonb,
   'Custo do Gemini de reserva em USD por milhão de tokens. 0 enquanto a GEMINI_API_KEY estiver num projecto sem faturação (nota de 12/08 no robot-b).', 'decisor')
ON CONFLICT (key) DO NOTHING;

-- ── 3. Chave do Jev (Vault) — só para o serviço ──────────────────────────────
CREATE OR REPLACE FUNCTION public.decisor_chave_typesafe()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'vault'
AS $$
  SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'typesafe_api_key' LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.decisor_chave_typesafe() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decisor_chave_typesafe() TO service_role;

-- ── 4. Modo de uma regra (lido pela varredura) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.decisor_modo(p_regra text)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((SELECT value #>> '{}' FROM platform_settings WHERE key = 'decisor_' || p_regra || '_modo'), 'desligado');
$$;
REVOKE ALL ON FUNCTION public.decisor_modo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decisor_modo(text) TO authenticated, service_role;

-- ── 5. O que falta decidir, com o estado montado ─────────────────────────────
-- Devolve uma linha por item: regra, contexto_id, tipo, pergunta, estado (jsonb), opcoes, mapa.
-- Janela curta (15 min) — o decisor olha para o que está a acontecer agora, não para o passado.
CREATE OR REPLACE FUNCTION public.decisor_itens_pendentes(p_limite integer DEFAULT 20)
RETURNS TABLE (usado_por text, contexto_id text, tipo text, pergunta text,
               estado jsonb, opcoes jsonb, mapa_opcoes jsonb, modo text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
#variable_conflict use_column
DECLARE
  v_m_desp  text := public.decisor_modo('despacho');
  v_m_nosh  text := public.decisor_modo('noshow');
  v_m_rob   text := public.decisor_modo('robotb');
  v_m_sup   text := public.decisor_modo('suporte');
BEGIN
  -- a) DESPACHO — pedidos a chamar estafeta e corridas TVDE à procura, com 2+ candidatos.
  IF v_m_desp <> 'desligado' THEN
    RETURN QUERY
    WITH trabalhos AS (
      SELECT 'pedido'::text AS tipo_trab, o.id::text AS cid, o.pickup_lat::numeric AS plat, o.pickup_lng::numeric AS plng,
             COALESCE(o.tried_driver_ids, '{}')::text[] AS tentados, o.service_type::text AS servico,
             COALESCE(o.is_test_order, false) AS teste
        FROM orders o
       WHERE o.status = 'callingDriver' AND o.created_at > now() - interval '3 hours'
         AND o.pickup_lat IS NOT NULL AND o.assigned_driver_id IS NULL
      UNION ALL
      SELECT 'corrida', r.id::text, r.origin_lat::numeric, r.origin_lng::numeric,
             COALESCE(r.tried_driver_ids, '{}')::text[], 'tvde', false
        FROM tvde_rides r
       WHERE r.status = 'a_procurar' AND r.created_at > now() - interval '3 hours'
         AND r.origin_lat IS NOT NULL AND r.driver_id IS NULL
    ),
    pendentes AS (
      SELECT t.* FROM trabalhos t
       WHERE NOT EXISTS (SELECT 1 FROM decisoes d WHERE d.usado_por = 'despacho' AND d.contexto_id = t.cid AND d.modo IN ('sombra','ativo'))
    ),
    cand AS (
      SELECT p.cid, dr.user_id, dr.id AS driver_row,
             round(public._haversine_km(p.plat, p.plng, dr.lat::numeric, dr.lng::numeric), 2) AS dist_km,
             (SELECT count(*) FROM orders o2 WHERE o2.assigned_driver_id = dr.user_id::text AND o2.created_at > now() - interval '7 days') AS aceites_7d,
             (SELECT count(*) FROM orders o3 WHERE o3.assigned_driver_id = dr.user_id::text
                 AND o3.status IN ('driverAccepted','pickedUp','onTheWay')) AS carga_atual,
             round(COALESCE(dr.avg_rating, 0), 2) AS avaliacao, COALESCE(dr.ratings_count, 0) AS n_avaliacoes,
             dr.vehicle_type AS veiculo,
             row_number() OVER (PARTITION BY p.cid ORDER BY public._haversine_km(p.plat, p.plng, dr.lat::numeric, dr.lng::numeric)) AS ordem
        FROM pendentes p
        JOIN drivers dr ON dr.is_online AND dr.last_heartbeat_at > now() - interval '90 seconds'
                       AND dr.approval_status = 'approved' AND COALESCE(dr.is_banned, false) = false
                       AND dr.deleted_at IS NULL AND dr.lat IS NOT NULL
                       AND NOT (dr.id::text = ANY (p.tentados)) AND NOT (dr.user_id::text = ANY (p.tentados))
    ),
    cand8 AS (SELECT * FROM cand WHERE ordem <= 8)
    SELECT 'despacho'::text, p.cid, 'choice'::text,
           'Which courier should get this job? Prefer short pickup distance, good rating, proven reliability (recent accepted jobs) and low current load.'::text,
           jsonb_build_object('trabalho', p.tipo_trab, 'servico', p.servico, 'teste', p.teste,
             'candidatos', jsonb_object_agg('estafeta_' || c.ordem,
                jsonb_build_object('distancia_recolha_km', c.dist_km, 'aceites_ultimos_7_dias', c.aceites_7d,
                                   'avaliacao_media', c.avaliacao, 'numero_avaliacoes', c.n_avaliacoes,
                                   'trabalhos_em_curso', c.carga_atual, 'veiculo', c.veiculo))),
           jsonb_agg('estafeta_' || c.ordem ORDER BY c.ordem),
           jsonb_object_agg('estafeta_' || c.ordem, c.user_id::text),
           v_m_desp
      FROM pendentes p JOIN cand8 c ON c.cid = p.cid
     GROUP BY p.cid, p.tipo_trab, p.servico, p.teste
    HAVING count(*) >= 2
     LIMIT p_limite;
  END IF;

  -- b) NO-SHOW — marcações de serviço criadas nos últimos 15 minutos.
  IF v_m_nosh <> 'desligado' THEN
    RETURN QUERY
    SELECT 'noshow'::text, a.id::text, 'score'::text,
           'How likely is this client NOT to show up for this booked appointment?'::text,
           jsonb_build_object(
             'horas_ate_marcacao', round(extract(epoch FROM (a.scheduled_at - a.created_at)) / 3600.0, 1),
             'dia_semana', to_char(a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'FMDay'),
             'hora_local', to_char(a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'),
             'preco_servico_eur', round(COALESCE(a.service_price_cents, 0) / 100.0, 2),
             'sinal_pago', COALESCE(a.deposit_status, 'sem_sinal'),
             'metodo_pagamento', a.full_payment_method,
             'remarcacoes', COALESCE(a.reschedule_count, 0),
             'deixou_notas', (COALESCE(a.client_notes, '') <> ''),
             'historico_cliente', (SELECT jsonb_build_object(
                 'marcacoes_anteriores', count(*),
                 'faltou', count(*) FILTER (WHERE h.status = 'no_show'),
                 'cancelou', count(*) FILTER (WHERE h.status = 'cancelled'),
                 'compareceu', count(*) FILTER (WHERE h.status = 'completed'))
               FROM appointments h
              WHERE h.id <> a.id AND h.created_at < a.created_at
                AND ((a.client_user_id IS NOT NULL AND h.client_user_id = a.client_user_id)
                  OR (a.client_user_id IS NULL AND a.client_phone IS NOT NULL AND h.client_phone = a.client_phone)))),
           '["Very low risk","Low risk","Medium risk","High risk","Very high risk"]'::jsonb,
           NULL::jsonb, v_m_nosh
      FROM appointments a
     WHERE a.created_at > now() - interval '15 minutes'
       AND COALESCE(a.is_walk_in, false) = false
       AND NOT EXISTS (SELECT 1 FROM decisoes d WHERE d.usado_por = 'noshow' AND d.contexto_id = a.id::text AND d.modo IN ('sombra','ativo'))
     LIMIT p_limite;
  END IF;

  -- c) ROBOT B — sugestões novas: vale a pena abrir?
  IF v_m_rob <> 'desligado' THEN
    RETURN QUERY
    SELECT 'robotb'::text, s.id::text, 'noul'::text,
           'Is this automatic suggestion worth the owner''s attention (real, actionable and not a repeat)? Use the history of how the owner handled this category.'::text,
           jsonb_build_object('titulo', s.titulo, 'categoria', s.categoria, 'nivel', s.nivel,
             'severidade', s.severidade, 'proposta', left(COALESCE(s.proposta, ''), 1200),
             'evidencia', left(COALESCE(s.evidencia::text, ''), 1500),
             'historico_da_categoria', (SELECT jsonb_build_object(
                 'aplicadas', count(*) FILTER (WHERE h.status IN ('aplicada','aprovada','aprovada-emerson')),
                 'rejeitadas', count(*) FILTER (WHERE h.status = 'rejeitada'),
                 'expiradas_sem_resposta', count(*) FILTER (WHERE h.status = 'expirada'))
               FROM robot_suggestions h WHERE h.categoria = s.categoria AND h.id <> s.id)),
           '{"true":"Worth opening: real problem, actionable, owner usually acts on this kind","false":"Not worth it: noise, repeat, or the owner usually rejects or ignores this kind"}'::jsonb,
           NULL::jsonb, v_m_rob
      FROM robot_suggestions s
     WHERE s.status = 'nova' AND s.created_at > now() - interval '15 minutes'
       AND NOT EXISTS (SELECT 1 FROM decisoes d WHERE d.usado_por = 'robotb' AND d.contexto_id = s.id::text AND d.modo IN ('sombra','ativo'))
     LIMIT p_limite;
  END IF;

  -- d) SUPORTE — cada mensagem nova do utilizador: passar a humano?
  IF v_m_sup <> 'desligado' THEN
    RETURN QUERY
    SELECT 'suporte'::text, m.id::text, 'noul'::text,
           'Should this support conversation be handed to a human now?'::text,
           jsonb_build_object('papel_utilizador', se.user_role, 'mensagens_na_sessao', se.messages_count,
             'tem_pedido_associado', se.order_id IS NOT NULL,
             'mensagem', left(COALESCE(m.content, ''), 1500),
             'mensagens_anteriores', (SELECT jsonb_agg(jsonb_build_object('quem', x.role, 'texto', left(x.content, 400)) ORDER BY x.created_at)
                FROM (SELECT p.role, p.content, p.created_at FROM support_chatbot_messages p
                       WHERE p.session_id = m.session_id AND p.created_at < m.created_at AND p.role IN ('user','assistant')
                       ORDER BY p.created_at DESC LIMIT 6) x)),
           '{"true":"Hand to a human: dispute, money/refund, legal or privacy, anger, safety, or the bot is failing","false":"The bot can keep answering"}'::jsonb,
           NULL::jsonb, v_m_sup
      FROM support_chatbot_messages m
      JOIN support_chatbot_sessions se ON se.id = m.session_id
     WHERE m.role = 'user' AND m.created_at > now() - interval '15 minutes'
       AND NOT EXISTS (SELECT 1 FROM decisoes d WHERE d.usado_por = 'suporte' AND d.contexto_id = m.id::text AND d.modo IN ('sombra','ativo'))
     LIMIT p_limite;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.decisor_itens_pendentes(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decisor_itens_pendentes(integer) TO service_role;

-- ── 6. O que aconteceu de verdade ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decisor_preencher_resultados()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE n integer := 0; k integer;
BEGIN
  -- despacho: quem ficou com o trabalho (chave anónima se estava entre as opções).
  UPDATE decisoes d SET resultado_em = now(),
         resultado_real = COALESCE((SELECT e.key FROM jsonb_each_text(d.mapa_opcoes) e WHERE e.value = x.quem LIMIT 1), 'outro')
    FROM (SELECT o.id::text AS cid, o.assigned_driver_id::text AS quem FROM orders o WHERE o.assigned_driver_id IS NOT NULL
          UNION ALL SELECT r.id::text, r.driver_id::text FROM tvde_rides r WHERE r.driver_id IS NOT NULL) x
   WHERE d.usado_por = 'despacho' AND d.resultado_real IS NULL AND d.contexto_id = x.cid;
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
  UPDATE decisoes d SET resultado_em = now(), resultado_real = 'ninguem'
    FROM (SELECT o.id::text cid FROM orders o WHERE o.status IN ('cancelled','rejected') AND o.assigned_driver_id IS NULL
          UNION ALL SELECT r.id::text FROM tvde_rides r WHERE r.status LIKE 'cancelada%' AND r.driver_id IS NULL) x
   WHERE d.usado_por = 'despacho' AND d.resultado_real IS NULL AND d.contexto_id = x.cid;
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;

  -- no-show: estado final da marcação.
  UPDATE decisoes d SET resultado_em = now(),
         resultado_real = CASE a.status WHEN 'no_show' THEN 'faltou' WHEN 'completed' THEN 'compareceu' ELSE 'cancelou' END
    FROM appointments a
   WHERE d.usado_por = 'noshow' AND d.resultado_real IS NULL AND d.contexto_id = a.id::text
     AND a.status IN ('no_show','completed','cancelled');
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;

  -- robot b: o que o Danilo fez com a sugestão (arquivos do próprio decisor não contam).
  UPDATE decisoes d SET resultado_em = now(),
         resultado_real = CASE WHEN s.status IN ('aplicada','aprovada','aprovada-emerson','em_execucao') THEN 'sim' ELSE 'nao' END
    FROM robot_suggestions s
   WHERE d.usado_por = 'robotb' AND d.resultado_real IS NULL AND d.contexto_id = s.id::text
     AND s.status <> 'nova' AND COALESCE(s.motivo_rejeicao, '') NOT LIKE 'Decisor:%';
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;

  -- suporte: a sessão acabou por ir a humano? (fecha "nao" após 24 h sem escalar)
  UPDATE decisoes d SET resultado_em = now(),
         resultado_real = CASE WHEN se.escalated OR COALESCE(se.escalated_pending, false)
                                 OR EXISTS (SELECT 1 FROM support_escalations e WHERE e.session_id = se.id) THEN 'sim' ELSE 'nao' END
    FROM support_chatbot_messages m JOIN support_chatbot_sessions se ON se.id = m.session_id
   WHERE d.usado_por = 'suporte' AND d.resultado_real IS NULL AND d.contexto_id = m.id::text
     AND (se.escalated OR COALESCE(se.escalated_pending, false)
          OR EXISTS (SELECT 1 FROM support_escalations e WHERE e.session_id = se.id)
          OR d.quando < now() - interval '24 hours');
  GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.decisor_preencher_resultados() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decisor_preencher_resultados() TO service_role;

-- ── 7. Painel admin ──────────────────────────────────────────────────────────
-- Resumo de hoje (hora de Lisboa): chamadas, tokens e custo por motor + modo de cada regra.
CREATE OR REPLACE FUNCTION public.admin_decisor_resumo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE = '42501'; END IF;
  RETURN jsonb_build_object(
    'hoje', (SELECT COALESCE(jsonb_object_agg(motor, x), '{}'::jsonb) FROM (
        SELECT motor, jsonb_build_object('chamadas', count(*), 'tokens_entrada', COALESCE(sum(tokens_entrada), 0),
               'tokens_saida', COALESCE(sum(tokens_saida), 0), 'custo_usd', COALESCE(sum(custo_usd), 0),
               'latencia_mediana_ms', percentile_disc(0.5) WITHIN GROUP (ORDER BY latencia_ms)) x
          FROM decisoes WHERE quando >= v_ini GROUP BY motor) t),
    'acerto', (SELECT COALESCE(jsonb_object_agg(usado_por || ':' || motor, x), '{}'::jsonb) FROM (
        SELECT usado_por, motor, jsonb_build_object('com_resultado', count(*),
               -- no-show: acerta se nota >= 2 (risco médio ou mais) coincide com ter faltado.
               'acertou', count(*) FILTER (WHERE CASE WHEN tipo = 'score'
                                                  THEN CASE WHEN resposta ~ '^[0-9]+(\.[0-9]+)?$' THEN (resposta::numeric >= 2) = (resultado_real = 'faltou') ELSE false END
                                                  ELSE resposta = resultado_real END)) x
          FROM decisoes WHERE resultado_real IS NOT NULL AND motor <> 'nenhum' AND modo <> 'teste'
         GROUP BY usado_por, motor) t),
    'modos', (SELECT jsonb_object_agg(r, public.decisor_modo(r)) FROM unnest(ARRAY['despacho','noshow','robotb','suporte']) r),
    'tem_chave_jev', EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'typesafe_api_key'),
    'preco_jev_usd_mtok', (SELECT value FROM platform_settings WHERE key = 'decisor_preco_jev_usd_mtok'));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_decisor_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_decisor_resumo() TO authenticated;

-- Mudar o modo de uma regra (auditado em admin_audit_log).
CREATE OR REPLACE FUNCTION public.admin_decisor_set_modo(p_regra text, p_modo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_antes text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Sem permissão' USING ERRCODE = '42501'; END IF;
  IF p_regra NOT IN ('despacho','noshow','robotb','suporte') THEN RAISE EXCEPTION 'Regra desconhecida: %', p_regra; END IF;
  IF p_modo NOT IN ('desligado','sombra','ativo') THEN RAISE EXCEPTION 'Modo inválido: %', p_modo; END IF;
  -- Só o Robot B tem modo ativo ligado a uma ação. Despacho = zona protegida (proposta);
  -- no-show e suporte ainda não têm ação definida — ficam em sombra até haver.
  IF p_modo = 'ativo' AND p_regra <> 'robotb' THEN
    RAISE EXCEPTION 'Modo ativo ainda não disponível para "%": por agora só sombra ou desligado.', p_regra;
  END IF;
  v_antes := public.decisor_modo(p_regra);
  UPDATE platform_settings SET value = to_jsonb(p_modo), updated_at = now(), updated_by = auth.uid()
   WHERE key = 'decisor_' || p_regra || '_modo';
  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), 'decisor_set_modo', 'platform_setting', 'decisor_' || p_regra || '_modo',
          jsonb_build_object('antes', v_antes, 'depois', p_modo));
  RETURN jsonb_build_object('regra', p_regra, 'antes', v_antes, 'depois', p_modo);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_decisor_set_modo(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_decisor_set_modo(text, text) TO authenticated;

-- ── 8. Varredura agendada (30 em 30 s) ───────────────────────────────────────
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'decisor-varrer';
SELECT cron.schedule('decisor-varrer', '30 seconds', $cron$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/decidir',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := '{"acao":"varrer"}'::jsonb,
    timeout_milliseconds := 55000);
$cron$);
