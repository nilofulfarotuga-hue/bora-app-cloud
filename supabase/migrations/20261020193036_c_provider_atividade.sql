-- Bloco C · fechar-pendencias-2026-10-20 — comprovativo de atividade aberta nas Finanças.
--
-- UMA verdade por pessoa (user_id): uma conta, todos os perfis (PADRAO_BORA §1.25). Em vez de
-- colunas espalhadas pelas tabelas de cada papel, a tabela `provider_atividade` guarda o NIF, o
-- comprovativo (foto ou PDF, bucket privado) e o estado (por_enviar / em_analise / aprovada /
-- recusada) de quem trabalha no Bora — estafeta, motorista TVDE, limpeza, lavagem, serviços.
--
-- Só ADITIVO: tabelas novas, bucket novo, funções novas e gatilhos novos. Nenhuma coluna nova em
-- tabelas que as versões antigas da app escrevem; nenhuma função existente é redefinida.
--
-- Quem já trabalhava antes da data de corte NÃO fica bloqueado: ganha a linha 'por_enviar' com
-- obrigatoria=false e só vê o aviso. O gatilho de aprovação só trava candidaturas criadas DEPOIS
-- da data de corte, com o interruptor `provider_atividade_obrigatoria` ligado (o mesmo molde do
-- gatilho de conformidade que já existe nas tabelas dos papéis).

-- ─────────────────────────────────────────────── 1) interruptor e data de corte
INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('provider_atividade_obrigatoria', 'true'::jsonb,
   'Comprovativo de atividade nas Finanças: com isto ligado, as candidaturas de prestador criadas depois da data de corte só podem ser aprovadas com o comprovativo aprovado. Quem já trabalhava antes não fica bloqueado (só vê o aviso).',
   'fiscal'),
  ('provider_atividade_corte',
   to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
   'Data de corte do comprovativo de atividade: candidaturas de prestador criadas antes desta data não ficam bloqueadas pela falta do comprovativo.',
   'fiscal')
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────── 2) a tabela (uma linha por pessoa)
CREATE TABLE IF NOT EXISTS public.provider_atividade (
  user_id             uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nif                 text,
  documento_path      text,
  documento_tipo      text CHECK (documento_tipo IS NULL OR documento_tipo IN ('pdf', 'jpg', 'png')),
  documento_bytes     integer,
  atividade_status    text NOT NULL DEFAULT 'por_enviar'
                      CHECK (atividade_status IN ('por_enviar', 'em_analise', 'aprovada', 'recusada')),
  enviado_em          timestamptz,
  decidido_em         timestamptz,
  decidido_por        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  motivo              text,
  obrigatoria         boolean NOT NULL DEFAULT false,
  lembrete_enviado_em timestamptz,
  lembretes_enviados  integer NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.provider_atividade IS
  'Comprovativo de atividade aberta nas Finanças, uma linha por pessoa (user_id). Escrita só pelas RPC provider_atividade_enviar e admin_provider_atividade_*.';

ALTER TABLE public.provider_atividade ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.provider_atividade FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.provider_atividade TO authenticated;
GRANT ALL ON TABLE public.provider_atividade TO service_role;
CREATE POLICY provider_atividade_ler ON public.provider_atividade
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

-- histórico (o que a própria pessoa, o admin e o sistema fizeram)
CREATE TABLE IF NOT EXISTS public.provider_atividade_eventos (
  id            bigserial PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  evento        text NOT NULL,
  estado_antes  text,
  estado_depois text,
  motivo        text,
  autor         uuid,
  autor_tipo    text NOT NULL CHECK (autor_tipo IN ('proprio', 'admin', 'sistema')),
  detalhe       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS provider_atividade_eventos_user_idx
  ON public.provider_atividade_eventos (user_id, created_at DESC);
ALTER TABLE public.provider_atividade_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.provider_atividade_eventos FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.provider_atividade_eventos_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.provider_atividade_eventos TO authenticated;
GRANT ALL ON TABLE public.provider_atividade_eventos TO service_role;
GRANT ALL ON SEQUENCE public.provider_atividade_eventos_id_seq TO service_role;
CREATE POLICY provider_atividade_eventos_ler ON public.provider_atividade_eventos
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

-- ─────────────────────────────────────────────── 3) bucket privado <user_id>/<ficheiro>
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('provider-atividade', 'provider-atividade', false, 10485760,
        ARRAY['image/jpeg', 'image/png', 'application/pdf'])
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY provider_atividade_proprio_ler ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'provider-atividade'
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);
CREATE POLICY provider_atividade_proprio_enviar ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'provider-atividade'
              AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);
CREATE POLICY provider_atividade_proprio_substituir ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'provider-atividade'
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)
  WITH CHECK (bucket_id = 'provider-atividade'
              AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);
CREATE POLICY provider_atividade_admin_ler ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'provider-atividade' AND public.is_admin());

-- ─────────────────────────────────────────────── 4) ajudantes internos (fechados a todos)
CREATE OR REPLACE FUNCTION public._provider_atividade_config()
RETURNS TABLE (ligado boolean, corte timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings
                    WHERE key = 'provider_atividade_obrigatoria'), false),
         (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings
           WHERE key = 'provider_atividade_corte');
$$;

-- Os papéis de prestador que a pessoa tem hoje (candidaturas recusadas não contam).
CREATE OR REPLACE FUNCTION public._provider_atividade_papeis(p_uid uuid)
RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(array_agg(DISTINCT x.p ORDER BY x.p), '{}'::text[])
  FROM (
    SELECT CASE WHEN d.vehicle_type = 'carro_passageiros' THEN 'motorista_tvde' ELSE 'estafeta' END AS p
      FROM public.drivers d
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL
       AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL
    SELECT 'estafeta'
      FROM public.drivers d
      JOIN public.user_roles ur ON ur.user_id = d.user_id AND ur.role = 'delivery'
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL
       AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL
    SELECT 'limpeza' FROM public.cleaners c
     WHERE c.user_id = p_uid AND c.approval_status <> 'rejected'
    UNION ALL
    SELECT 'lavagem' FROM public.washers w
     WHERE w.user_id = p_uid AND w.approval_status <> 'rejected'
    UNION ALL
    SELECT 'servicos' FROM public.service_providers s
     WHERE s.user_id = p_uid AND s.approval_status <> 'rejected'
  ) x;
$$;

-- A candidatura mais recente (não recusada) da pessoa, para saber se nasceu depois do corte.
CREATE OR REPLACE FUNCTION public._provider_atividade_ultima_candidatura(p_uid uuid)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT max(t) FROM (
    SELECT d.created_at AS t FROM public.drivers d
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL SELECT c.created_at FROM public.cleaners c
     WHERE c.user_id = p_uid AND c.approval_status <> 'rejected'
    UNION ALL SELECT w.created_at FROM public.washers w
     WHERE w.user_id = p_uid AND w.approval_status <> 'rejected'
    UNION ALL SELECT s.created_at FROM public.service_providers s
     WHERE s.user_id = p_uid AND s.approval_status <> 'rejected'
  ) x;
$$;

-- O NIF que a pessoa já deu noutro sítio (só para pré-preencher o ecrã; não se grava).
CREATE OR REPLACE FUNCTION public._provider_atividade_nif_conhecido(p_uid uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT n FROM (
    SELECT 1 AS o, regexp_replace(COALESCE(f.nif, ''), '\D', '', 'g') AS n
      FROM public.driver_fiscal_status f WHERE f.user_id = p_uid
    UNION ALL SELECT 2, regexp_replace(COALESCE(c.nif, ''), '\D', '', 'g') FROM public.cleaners c WHERE c.user_id = p_uid
    UNION ALL SELECT 3, regexp_replace(COALESCE(w.nif, ''), '\D', '', 'g') FROM public.washers w WHERE w.user_id = p_uid
    UNION ALL SELECT 4, regexp_replace(COALESCE(d.nif, ''), '\D', '', 'g') FROM public.drivers d WHERE d.user_id = p_uid
    UNION ALL SELECT 5, regexp_replace(COALESCE(s.nif, ''), '\D', '', 'g') FROM public.service_providers s WHERE s.user_id = p_uid
  ) x
  WHERE public._nif_valido(x.n)
  ORDER BY x.o
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._provider_atividade_evento(
  p_uid uuid, p_evento text, p_antes text, p_depois text, p_motivo text,
  p_autor uuid, p_autor_tipo text, p_detalhe jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.provider_atividade_eventos
    (user_id, evento, estado_antes, estado_depois, motivo, autor, autor_tipo, detalhe)
  VALUES (p_uid, p_evento, p_antes, p_depois, p_motivo, p_autor, p_autor_tipo, COALESCE(p_detalhe, '{}'::jsonb));
$$;

-- Garante a linha da pessoa. `obrigatoria` só passa de false a true (candidatura nova depois do
-- corte com o interruptor ligado); nunca volta atrás sozinha.
CREATE OR REPLACE FUNCTION public._provider_atividade_garantir(p_uid uuid)
RETURNS public.provider_atividade
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg  record;
  v_nova boolean;
  v_row  public.provider_atividade;
  v_novo boolean;
BEGIN
  SELECT * INTO v_cfg FROM public._provider_atividade_config();
  v_nova := COALESCE(v_cfg.ligado, false) AND v_cfg.corte IS NOT NULL
            AND COALESCE(public._provider_atividade_ultima_candidatura(p_uid) >= v_cfg.corte, false);
  v_novo := NOT EXISTS (SELECT 1 FROM public.provider_atividade WHERE user_id = p_uid);
  INSERT INTO public.provider_atividade (user_id, obrigatoria)
  VALUES (p_uid, v_nova)
  ON CONFLICT (user_id) DO UPDATE
    SET obrigatoria = public.provider_atividade.obrigatoria OR EXCLUDED.obrigatoria,
        updated_at = CASE WHEN EXCLUDED.obrigatoria AND NOT public.provider_atividade.obrigatoria
                          THEN now() ELSE public.provider_atividade.updated_at END
  RETURNING * INTO v_row;
  IF v_novo THEN
    PERFORM public._provider_atividade_evento(p_uid, 'criado', NULL, v_row.atividade_status, NULL,
      NULL, 'sistema', jsonb_build_object('obrigatoria', v_row.obrigatoria));
  END IF;
  RETURN v_row;
END $$;

-- Aviso à pessoa: caixa da app (sino) + push pelo canal que os prestadores já recebem
-- (Edge notify-admin-message: junta os aparelhos da pessoa de todos os papéis). O toque abre o
-- ecrã do comprovativo (kind provider_atividade). Falhar aqui nunca estraga a decisão, mas
-- fica registado no e2e_log (nada de falha calada).
CREATE OR REPLACE FUNCTION public._provider_atividade_avisar(p_uid uuid, p_titulo text, p_corpo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_inapp  uuid;
  v_key    text;
  v_url    text;
  v_header jsonb;
  v_req    bigint;
BEGIN
  v_inapp := public._push_in_app_notification(p_uid, 'provider_atividade', p_titulo, p_corpo, 'provider_atividade');
  BEGIN
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'sb_secret_backend';
    IF v_key IS NOT NULL THEN
      v_header := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json');
    ELSE
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
      IF v_key IS NOT NULL THEN
        v_header := jsonb_build_object('apikey', v_key, 'Authorization', 'Bearer ' || v_key,
                                       'Content-Type', 'application/json');
      END IF;
    END IF;
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
    IF v_header IS NULL THEN
      INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
      VALUES ('provider-atividade', 'push', 'falhou', p_uid::text || ' sem chave no cofre', 'servidor');
      RETURN jsonb_build_object('inapp', v_inapp IS NOT NULL, 'push', false, 'erro', 'sem_chave');
    END IF;
    SELECT net.http_post(
      url     := COALESCE(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/notify-admin-message',
      headers := v_header,
      body    := jsonb_build_object('targetUserId', p_uid::text, 'title', p_titulo, 'body', p_corpo,
                                    'kind', 'provider_atividade', 'relatedId', 'provider_atividade'))
      INTO v_req;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('provider-atividade', 'push', 'falhou', p_uid::text || ' ' || SQLERRM, 'servidor');
    RETURN jsonb_build_object('inapp', v_inapp IS NOT NULL, 'push', false, 'erro', SQLERRM);
  END;
  RETURN jsonb_build_object('inapp', v_inapp IS NOT NULL, 'push', true, 'pedido', v_req);
END $$;

-- O texto do lembrete conforme o estado (PT-PT).
CREATE OR REPLACE FUNCTION public._provider_atividade_texto_lembrete(p_row public.provider_atividade)
RETURNS TABLE (titulo text, corpo text)
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT
    CASE WHEN p_row.atividade_status = 'recusada' THEN 'Comprovativo de atividade recusado'
         ELSE 'Falta o comprovativo de atividade' END,
    CASE
      WHEN p_row.atividade_status = 'recusada' THEN
        COALESCE('Motivo: ' || NULLIF(trim(p_row.motivo), '') || '. ', '')
        || 'Envia um novo comprovativo de atividade aberta nas Finanças pela app: toca aqui.'
      WHEN p_row.atividade_status = 'em_analise' AND p_row.documento_path IS NULL THEN
        'Disseste-nos que já tens atividade aberta nas Finanças. Falta enviares o comprovativo pela app: toca aqui.'
      ELSE
        'Envia pela app o comprovativo de atividade aberta nas Finanças e o teu NIF. Demora um minuto: toca aqui.'
    END;
$$;

-- ─────────────────────────────────────────────── 5) RPC da própria pessoa
CREATE OR REPLACE FUNCTION public.provider_atividade_get()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_papeis text[];
  v_cfg    record;
  v_row    public.provider_atividade;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_cfg FROM public._provider_atividade_config();
  v_papeis := public._provider_atividade_papeis(v_uid);
  IF COALESCE(array_length(v_papeis, 1), 0) = 0 THEN
    RETURN jsonb_build_object('e_prestador', false, 'interruptor', v_cfg.ligado);
  END IF;
  v_row := public._provider_atividade_garantir(v_uid);
  RETURN jsonb_build_object(
    'e_prestador',      true,
    'papeis',           to_jsonb(v_papeis),
    'atividade_status', v_row.atividade_status,
    'tem_documento',    v_row.documento_path IS NOT NULL,
    'documento_tipo',   v_row.documento_tipo,
    'nif',              v_row.nif,
    'nif_sugerido',     COALESCE(v_row.nif, public._provider_atividade_nif_conhecido(v_uid)),
    'enviado_em',       v_row.enviado_em,
    'decidido_em',      v_row.decidido_em,
    'motivo',           v_row.motivo,
    'obrigatoria',      v_row.obrigatoria AND COALESCE(v_cfg.ligado, false),
    'interruptor',      COALESCE(v_cfg.ligado, false));
END $$;

-- A pessoa envia o NIF + o comprovativo que já subiu para o bucket (pasta <user_id>/).
-- Nunca se põe 'aprovada' a si própria: o envio deixa sempre 'em_analise'.
CREATE OR REPLACE FUNCTION public.provider_atividade_enviar(p_nif text, p_documento_path text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_nif   text := regexp_replace(COALESCE(p_nif, ''), '\D', '', 'g');
  v_meta  jsonb;
  v_tipo  text;
  v_row   public.provider_atividade;
  v_antes text;
  v_nome  text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao' USING ERRCODE = '42501'; END IF;
  IF COALESCE(array_length(public._provider_atividade_papeis(v_uid), 1), 0) = 0 THEN
    RAISE EXCEPTION 'nao_e_prestador';
  END IF;
  IF NOT public._nif_valido(v_nif) THEN RAISE EXCEPTION 'nif_invalido'; END IF;
  IF p_documento_path IS NULL OR split_part(p_documento_path, '/', 1) <> v_uid::text THEN
    RAISE EXCEPTION 'documento_invalido';
  END IF;
  SELECT o.metadata INTO v_meta
    FROM storage.objects o
   WHERE o.bucket_id = 'provider-atividade' AND o.name = p_documento_path
     AND (o.owner = v_uid OR o.owner_id = v_uid::text);
  IF NOT FOUND THEN RAISE EXCEPTION 'documento_nao_encontrado'; END IF;
  v_tipo := CASE lower(COALESCE(v_meta ->> 'mimetype', ''))
              WHEN 'application/pdf' THEN 'pdf'
              WHEN 'image/png' THEN 'png'
              WHEN 'image/jpeg' THEN 'jpg'
              ELSE NULL END;
  IF v_tipo IS NULL THEN RAISE EXCEPTION 'tipo_invalido'; END IF;

  v_row := public._provider_atividade_garantir(v_uid);
  IF v_row.atividade_status = 'aprovada' THEN RAISE EXCEPTION 'ja_aprovada'; END IF;
  v_antes := v_row.atividade_status;

  UPDATE public.provider_atividade
     SET nif = v_nif, documento_path = p_documento_path, documento_tipo = v_tipo,
         documento_bytes = NULLIF(v_meta ->> 'size', '')::integer,
         atividade_status = 'em_analise', enviado_em = now(),
         decidido_em = NULL, decidido_por = NULL, motivo = NULL, updated_at = now()
   WHERE user_id = v_uid
  RETURNING * INTO v_row;

  PERFORM public._provider_atividade_evento(v_uid, 'enviado', v_antes, 'em_analise', NULL, v_uid, 'proprio',
    jsonb_build_object('tipo', v_tipo, 'bytes', v_row.documento_bytes));

  -- Estafeta: o NIF + comprovativo vale como a confirmação de atividade que já existia
  -- (driver_fiscal_status), pela mesma RPC que o cartão do estafeta usa — sem lógica gémea.
  IF EXISTS (SELECT 1 FROM public.drivers WHERE user_id = v_uid) THEN
    PERFORM public.driver_confirm_fiscal_activity(v_nif);
  END IF;

  SELECT COALESCE(NULLIF(u.name, ''), NULLIF(c.name, ''), NULLIF(w.name, ''), NULLIF(d.name, ''), 'Prestador')
    INTO v_nome
    FROM (SELECT v_uid AS id) k
    LEFT JOIN public.users u ON u.id = k.id
    LEFT JOIN public.cleaners c ON c.user_id = k.id
    LEFT JOIN public.washers w ON w.user_id = k.id
    LEFT JOIN public.drivers d ON d.user_id = k.id
   LIMIT 1;
  PERFORM public.notify_admin_event('provider_atividade_enviada', 'low',
    'Comprovativo de atividade para analisar: ' || v_nome,
    'provider_atividade', v_uid::text, jsonb_build_object('tipo', v_tipo), '/admin/comprovativo-atividade');

  RETURN public.provider_atividade_get();
END $$;

-- ─────────────────────────────────────────────── 6) RPC do painel (validam is_admin())
CREATE OR REPLACE FUNCTION public.admin_provider_atividade_listar(p_filtro text DEFAULT 'todos')
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg  record;
  v_demo boolean := public.admin_demo_visible();
  v_out  jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_cfg FROM public._provider_atividade_config();
  WITH pessoas AS (
    SELECT d.user_id FROM public.drivers d
     WHERE d.user_id IS NOT NULL AND d.deleted_at IS NULL AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION SELECT c.user_id FROM public.cleaners c WHERE c.approval_status <> 'rejected'
    UNION SELECT w.user_id FROM public.washers w WHERE w.approval_status <> 'rejected'
    UNION SELECT s.user_id FROM public.service_providers s WHERE s.user_id IS NOT NULL AND s.approval_status <> 'rejected'
  ), base AS (
    SELECT p.user_id,
           COALESCE(NULLIF(u.name, ''), NULLIF(c.name, ''), NULLIF(w.name, ''), NULLIF(d.name, ''), NULLIF(s.name, ''), '(sem nome)') AS nome,
           au.email,
           COALESCE(NULLIF(u.phone, ''), NULLIF(c.phone, ''), NULLIF(w.phone, ''), NULLIF(d.phone, ''), NULLIF(s.phone, '')) AS telefone,
           public._provider_atividade_papeis(p.user_id) AS papeis,
           COALESCE(a.atividade_status, 'por_enviar') AS atividade_status,
           a.documento_path IS NOT NULL AS tem_documento,
           a.documento_tipo, a.nif, a.enviado_em, a.decidido_em, a.motivo,
           (SELECT x.email FROM auth.users x WHERE x.id = a.decidido_por) AS decidido_por_email,
           COALESCE(a.obrigatoria, false) AS obrigatoria,
           a.lembrete_enviado_em, COALESCE(a.lembretes_enviados, 0) AS lembretes_enviados,
           public.is_demo_user(p.user_id) AS demo
      FROM pessoas p
      JOIN auth.users au ON au.id = p.user_id
      LEFT JOIN public.provider_atividade a ON a.user_id = p.user_id
      LEFT JOIN public.users u ON u.id = p.user_id
      LEFT JOIN LATERAL (SELECT name, phone FROM public.cleaners WHERE user_id = p.user_id LIMIT 1) c ON true
      LEFT JOIN LATERAL (SELECT name, phone FROM public.washers WHERE user_id = p.user_id LIMIT 1) w ON true
      LEFT JOIN LATERAL (SELECT name, phone FROM public.drivers WHERE user_id = p.user_id LIMIT 1) d ON true
      LEFT JOIN LATERAL (SELECT name, phone FROM public.service_providers WHERE user_id = p.user_id LIMIT 1) s ON true
  )
  SELECT jsonb_build_object(
           'interruptor', COALESCE(v_cfg.ligado, false),
           'corte', v_cfg.corte,
           'linhas', COALESCE(jsonb_agg(to_jsonb(b) ORDER BY
                       CASE b.atividade_status WHEN 'em_analise' THEN 0 WHEN 'recusada' THEN 1
                                               WHEN 'por_enviar' THEN 2 ELSE 3 END, b.nome), '[]'::jsonb))
    INTO v_out
    FROM base b
   WHERE (v_demo OR NOT b.demo)
     AND CASE COALESCE(p_filtro, 'todos')
           WHEN 'sem_atividade' THEN b.atividade_status <> 'aprovada'
           WHEN 'por_enviar'    THEN b.atividade_status = 'por_enviar'
           WHEN 'em_analise'    THEN b.atividade_status = 'em_analise'
           WHEN 'aprovada'      THEN b.atividade_status = 'aprovada'
           WHEN 'recusada'      THEN b.atividade_status = 'recusada'
           ELSE true END;
  RETURN v_out;
END $$;

-- O caminho do documento para o painel pedir uma URL assinada de curta duração.
-- Fica registado quem viu e quando.
CREATE OR REPLACE FUNCTION public.admin_provider_atividade_documento(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.provider_atividade;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_row FROM public.provider_atividade WHERE user_id = p_user_id;
  IF NOT FOUND OR v_row.documento_path IS NULL THEN RAISE EXCEPTION 'sem_documento'; END IF;
  PERFORM public.log_admin_action('provider_atividade_ver_documento'::text, 'provider_atividade'::text,
    p_user_id::text, jsonb_build_object('tipo', v_row.documento_tipo));
  PERFORM public._provider_atividade_evento(p_user_id, 'documento_visto', v_row.atividade_status,
    v_row.atividade_status, NULL, auth.uid(), 'admin', '{}'::jsonb);
  RETURN jsonb_build_object('bucket', 'provider-atividade', 'path', v_row.documento_path,
                            'tipo', v_row.documento_tipo);
END $$;

-- Decidir: aprovar · recusar (motivo obrigatório) · em_analise · pedir_de_novo (volta a por_enviar).
CREATE OR REPLACE FUNCTION public.admin_provider_atividade_decidir(
  p_user_id uuid, p_acao text, p_motivo text DEFAULT NULL, p_avisar boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row    public.provider_atividade;
  v_antes  text;
  v_depois text;
  v_motivo text := NULLIF(trim(COALESCE(p_motivo, '')), '');
  v_aviso  jsonb := NULL;
  v_titulo text;
  v_corpo  text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_obrigatorio'; END IF;
  IF COALESCE(array_length(public._provider_atividade_papeis(p_user_id), 1), 0) = 0
     AND NOT EXISTS (SELECT 1 FROM public.provider_atividade WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'nao_e_prestador';
  END IF;
  v_row := public._provider_atividade_garantir(p_user_id);
  v_antes := v_row.atividade_status;
  v_depois := CASE p_acao
                WHEN 'aprovar'       THEN 'aprovada'
                WHEN 'recusar'       THEN 'recusada'
                WHEN 'em_analise'    THEN 'em_analise'
                WHEN 'pedir_de_novo' THEN 'por_enviar'
                ELSE NULL END;
  IF v_depois IS NULL THEN RAISE EXCEPTION 'acao_invalida: %', p_acao; END IF;
  IF p_acao = 'aprovar' AND v_row.documento_path IS NULL THEN RAISE EXCEPTION 'sem_documento'; END IF;
  IF p_acao IN ('recusar', 'pedir_de_novo') AND v_motivo IS NULL THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;

  UPDATE public.provider_atividade
     SET atividade_status = v_depois,
         decidido_em  = CASE WHEN p_acao IN ('aprovar', 'recusar') THEN now() ELSE NULL END,
         decidido_por = CASE WHEN p_acao IN ('aprovar', 'recusar') THEN auth.uid() ELSE NULL END,
         motivo       = v_motivo,
         updated_at   = now()
   WHERE user_id = p_user_id
  RETURNING * INTO v_row;

  PERFORM public._provider_atividade_evento(p_user_id, 'decisao_' || p_acao, v_antes, v_depois, v_motivo,
    auth.uid(), 'admin', jsonb_build_object('via', COALESCE(current_setting('bora.agente', true), 'painel')));
  PERFORM public.log_admin_action('provider_atividade_' || p_acao, 'provider_atividade'::text, p_user_id::text,
    jsonb_build_object('antes', v_antes, 'depois', v_depois, 'motivo', v_motivo,
                       'via', COALESCE(current_setting('bora.agente', true), 'painel')));

  -- Avisos: só recusar, pedir de novo e aprovar falam com a pessoa. 'em_analise' é silencioso.
  IF COALESCE(p_avisar, true) AND p_acao IN ('aprovar', 'recusar', 'pedir_de_novo') THEN
    IF p_acao = 'aprovar' THEN
      v_titulo := 'Comprovativo de atividade aprovado';
      v_corpo  := 'Obrigado! O teu comprovativo de atividade nas Finanças está aprovado.';
    ELSIF p_acao = 'recusar' THEN
      SELECT t.titulo, t.corpo INTO v_titulo, v_corpo FROM public._provider_atividade_texto_lembrete(v_row) t;
    ELSE
      v_titulo := 'Envia de novo o comprovativo de atividade';
      v_corpo  := v_motivo || '. Toca aqui para enviar o comprovativo pela app.';
    END IF;
    v_aviso := public._provider_atividade_avisar(p_user_id, v_titulo, v_corpo);
  END IF;

  RETURN jsonb_build_object('ok', true, 'antes', v_antes, 'depois', v_depois, 'aviso', v_aviso);
END $$;

-- Lembrete a UMA pessoa ("Falta o comprovativo de atividade").
CREATE OR REPLACE FUNCTION public.admin_provider_atividade_lembrar(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row   public.provider_atividade;
  v_txt   record;
  v_aviso jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF COALESCE(array_length(public._provider_atividade_papeis(p_user_id), 1), 0) = 0 THEN
    RAISE EXCEPTION 'nao_e_prestador';
  END IF;
  v_row := public._provider_atividade_garantir(p_user_id);
  IF v_row.atividade_status = 'aprovada'
     OR (v_row.atividade_status = 'em_analise' AND v_row.documento_path IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nada_a_pedir', 'estado', v_row.atividade_status);
  END IF;
  SELECT * INTO v_txt FROM public._provider_atividade_texto_lembrete(v_row);
  v_aviso := public._provider_atividade_avisar(p_user_id, v_txt.titulo, v_txt.corpo);
  UPDATE public.provider_atividade
     SET lembrete_enviado_em = now(), lembretes_enviados = lembretes_enviados + 1, updated_at = now()
   WHERE user_id = p_user_id;
  PERFORM public._provider_atividade_evento(p_user_id, 'lembrete', v_row.atividade_status, v_row.atividade_status,
    NULL, auth.uid(), 'admin', jsonb_build_object('aviso', v_aviso));
  PERFORM public.log_admin_action('provider_atividade_lembrete'::text, 'provider_atividade'::text, p_user_id::text,
    jsonb_build_object('aviso', v_aviso));
  RETURN jsonb_build_object('ok', true, 'titulo', v_txt.titulo, 'corpo', v_txt.corpo, 'aviso', v_aviso);
END $$;

-- Lembrete a TODOS os que ainda não têm o comprovativo (sem demo; nunca duas vezes em 20 h).
-- p_confirmar=false só conta (o painel mostra o número e pede confirmação).
CREATE OR REPLACE FUNCTION public.admin_provider_atividade_lembrar_todos(p_confirmar boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_alvos uuid[];
  v_uid   uuid;
  v_n     integer := 0;
  v_r     jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  SELECT COALESCE(array_agg(a.user_id ORDER BY a.user_id), '{}'::uuid[]) INTO v_alvos
    FROM public.provider_atividade a
   WHERE (a.atividade_status IN ('por_enviar', 'recusada')
          OR (a.atividade_status = 'em_analise' AND a.documento_path IS NULL))
     AND NOT public.is_demo_user(a.user_id)
     AND (a.lembrete_enviado_em IS NULL OR a.lembrete_enviado_em < now() - interval '20 hours')
     AND COALESCE(array_length(public._provider_atividade_papeis(a.user_id), 1), 0) > 0;
  IF NOT COALESCE(p_confirmar, false) THEN
    RETURN jsonb_build_object('ok', true, 'confirmado', false, 'alvos', COALESCE(array_length(v_alvos, 1), 0));
  END IF;
  FOREACH v_uid IN ARRAY v_alvos LOOP
    v_r := public.admin_provider_atividade_lembrar(v_uid);
    IF COALESCE((v_r ->> 'ok')::boolean, false) THEN v_n := v_n + 1; END IF;
  END LOOP;
  PERFORM public.log_admin_action('provider_atividade_lembrete_todos'::text, 'provider_atividade'::text, NULL::text,
    jsonb_build_object('alvos', COALESCE(array_length(v_alvos, 1), 0), 'enviados', v_n));
  RETURN jsonb_build_object('ok', true, 'confirmado', true,
                            'alvos', COALESCE(array_length(v_alvos, 1), 0), 'enviados', v_n);
END $$;

CREATE OR REPLACE FUNCTION public.admin_provider_atividade_historico(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'quando', e.created_at, 'evento', e.evento, 'antes', e.estado_antes, 'depois', e.estado_depois,
             'motivo', e.motivo, 'autor_tipo', e.autor_tipo,
             'autor_email', (SELECT x.email FROM auth.users x WHERE x.id = e.autor)) ORDER BY e.created_at DESC)
      FROM public.provider_atividade_eventos e WHERE e.user_id = p_user_id), '[]'::jsonb);
END $$;

-- ─────────────────────────────────────────────── 7) a aprovação do papel espera pelo comprovativo
-- Mesmo molde do gatilho de conformidade que já existe nestas tabelas: só corre quando a
-- candidatura passa a 'approved'; só trava candidaturas criadas depois do corte, com o
-- interruptor ligado; desligar o interruptor solta tudo.
CREATE OR REPLACE FUNCTION public.fn_atividade_antes_de_ativar()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg record;
  v_st  text;
BEGIN
  IF NEW.user_id IS NULL OR NEW.created_at IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_cfg FROM public._provider_atividade_config();
  IF NOT COALESCE(v_cfg.ligado, false) OR v_cfg.corte IS NULL OR NEW.created_at < v_cfg.corte THEN
    RETURN NEW;
  END IF;
  SELECT a.atividade_status INTO v_st FROM public.provider_atividade a WHERE a.user_id = NEW.user_id;
  IF COALESCE(v_st, 'por_enviar') <> 'aprovada' THEN
    RAISE EXCEPTION 'atividade_por_aprovar'
      USING HINT = 'Aprova primeiro o comprovativo de atividade (painel: Comprovativo de atividade) ou desliga provider_atividade_obrigatoria.';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER trg_atividade_antes_de_ativar
  BEFORE UPDATE OF approval_status ON public.cleaners
  FOR EACH ROW WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public.fn_atividade_antes_de_ativar();
CREATE OR REPLACE TRIGGER trg_atividade_antes_de_ativar
  BEFORE UPDATE OF approval_status ON public.washers
  FOR EACH ROW WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public.fn_atividade_antes_de_ativar();
CREATE OR REPLACE TRIGGER trg_atividade_antes_de_ativar
  BEFORE UPDATE OF approval_status ON public.service_providers
  FOR EACH ROW WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public.fn_atividade_antes_de_ativar();
CREATE OR REPLACE TRIGGER trg_atividade_antes_de_ativar
  BEFORE UPDATE OF approval_status ON public.drivers
  FOR EACH ROW WHEN (NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public.fn_atividade_antes_de_ativar();

-- ─────────────────────────────────────────────── 8) quem já trabalha: linha 'por_enviar', não obrigatória
INSERT INTO public.provider_atividade (user_id, obrigatoria)
SELECT DISTINCT x.u, false
  FROM (
    SELECT d.user_id AS u FROM public.drivers d
     WHERE d.user_id IS NOT NULL AND d.deleted_at IS NULL AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION SELECT c.user_id FROM public.cleaners c WHERE c.approval_status <> 'rejected'
    UNION SELECT w.user_id FROM public.washers w WHERE w.approval_status <> 'rejected'
    UNION SELECT s.user_id FROM public.service_providers s WHERE s.user_id IS NOT NULL AND s.approval_status <> 'rejected'
  ) x
 WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = x.u)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.provider_atividade_eventos (user_id, evento, estado_antes, estado_depois, autor_tipo, detalhe)
SELECT a.user_id, 'criado', NULL, a.atividade_status, 'sistema', jsonb_build_object('obrigatoria', false, 'origem', 'corte')
  FROM public.provider_atividade a
 WHERE NOT EXISTS (SELECT 1 FROM public.provider_atividade_eventos e WHERE e.user_id = a.user_id);

-- ─────────────────────────────────────────────── 9) permissões: tudo nasce fechado
REVOKE ALL ON FUNCTION public._provider_atividade_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_papeis(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_ultima_candidatura(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_nif_conhecido(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_evento(uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_garantir(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_avisar(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._provider_atividade_texto_lembrete(public.provider_atividade) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_atividade_antes_de_ativar() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.provider_atividade_get() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.provider_atividade_enviar(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_listar(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_documento(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_decidir(uuid, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_lembrar(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_lembrar_todos(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_provider_atividade_historico(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.provider_atividade_get() TO authenticated;
GRANT EXECUTE ON FUNCTION public.provider_atividade_enviar(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_listar(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_documento(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_decidir(uuid, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_lembrar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_lembrar_todos(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provider_atividade_historico(uuid) TO authenticated;
