-- Bloco C · ronda 1 do revisor (20/10/2026): o próprio só escreve o comprovativo quando ele
-- falta — estado 'por_enviar', 'recusada', ou 'em_analise' ainda sem documento (quem disse que
-- já tem atividade aberta, como a Mayra). Depois de enviado (em análise com documento) ou de
-- aprovado, o ficheiro fica como está; para trocar, o admin usa "Pedir de novo".
--
-- Só mexe em objetos criados hoje pela migração c_provider_atividade (nenhuma versão publicada
-- da app os usa ainda): a política de substituição sai, a de envio ganha a condição do estado,
-- e a RPC de envio passa a recusar com 'ja_enviado' o mesmo caso.

-- 1) substituir ficheiros deixa de existir (a app envia sempre com nome novo)
DROP POLICY IF EXISTS provider_atividade_proprio_substituir ON storage.objects;

-- 2) enviar só quando o comprovativo falta
ALTER POLICY provider_atividade_proprio_enviar ON storage.objects
  WITH CHECK (
    bucket_id = 'provider-atividade'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1 FROM public.provider_atividade a
       WHERE a.user_id = (SELECT auth.uid())
         AND (a.atividade_status IN ('por_enviar', 'recusada')
              OR (a.atividade_status = 'em_analise' AND a.documento_path IS NULL))
    )
  );

-- 3) a RPC de envio diz o mesmo que o bucket
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

  v_row := public._provider_atividade_garantir(v_uid);
  IF v_row.atividade_status = 'aprovada' THEN RAISE EXCEPTION 'ja_aprovada'; END IF;
  IF v_row.atividade_status = 'em_analise' AND v_row.documento_path IS NOT NULL THEN
    RAISE EXCEPTION 'ja_enviado';
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

REVOKE ALL ON FUNCTION public.provider_atividade_enviar(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provider_atividade_enviar(text, text) TO authenticated;
