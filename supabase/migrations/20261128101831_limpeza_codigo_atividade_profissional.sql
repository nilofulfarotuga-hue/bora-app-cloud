-- Missão limpeza-planos-empresas-2026-11-28, Bloco E (código de atividade da profissional).
-- JÁ APLICADA no servidor (versão 20261128101831). Cópia fiel de supabase_migrations.schema_migrations.
CREATE TABLE IF NOT EXISTS public.cleaner_activity_codes (
  code        text PRIMARY KEY,
  kind        text NOT NULL CHECK (kind IN ('cae','cirs')),
  label_pt    text NOT NULL,
  accepted    boolean NOT NULL DEFAULT true,
  preferred   boolean NOT NULL DEFAULT false,
  note_pt     text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid
);

COMMENT ON TABLE public.cleaner_activity_codes IS
  'Limpeza: códigos de atividade (CAE e tabela do art. 151.º do CIRS) aceites para as profissionais de limpeza. Editável no painel (admin_set_cleaner_activity_code).';

INSERT INTO public.cleaner_activity_codes (code, kind, label_pt, accepted, preferred, note_pt) VALUES
  ('81210', 'cae',  'Atividades de limpeza geral em edifícios', true, true,
   'O código certo para limpezas de casas, lojas e escritórios. CAE-Rev.3; a equivalência na CAE-Rev.4 (DL 9/2025, em vigor desde 01/01/2025) está POR CONFIRMAR na tabela do INE (SMI, Correspondência de versões).'),
  ('81220', 'cae',  'Outras atividades de limpeza em edifícios e em equipamentos industriais', true, false,
   'Aceite: limpeza especializada (vidros altos, pós-obra, equipamentos).'),
  ('81290', 'cae',  'Outras atividades de limpeza', true, false,
   'Aceite como secundário.'),
  ('1519',  'cirs', 'Outros prestadores de serviços', true, false,
   'Aceite só para quem já o tem: a Autoridade Tributária diz que o 1519 é residual (só quando nenhum CAE serve). A app pede para acrescentar o 81210.')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.cleaner_activity_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY cleaner_activity_codes_read ON public.cleaner_activity_codes
  FOR SELECT TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION public.admin_set_cleaner_activity_code(
  p_code text, p_kind text, p_label text, p_accepted boolean, p_preferred boolean, p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_antes jsonb; v_depois jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  IF p_kind NOT IN ('cae','cirs') THEN RAISE EXCEPTION 'invalid_kind'; END IF;
  IF COALESCE(btrim(p_code), '') !~ '^[0-9]{4,5}$' THEN RAISE EXCEPTION 'invalid_code'; END IF;
  SELECT to_jsonb(c) INTO v_antes FROM cleaner_activity_codes c WHERE code = btrim(p_code);
  INSERT INTO cleaner_activity_codes (code, kind, label_pt, accepted, preferred, note_pt, updated_at, updated_by)
  VALUES (btrim(p_code), p_kind, p_label, p_accepted, p_preferred, p_note, now(), auth.uid())
  ON CONFLICT (code) DO UPDATE SET kind = EXCLUDED.kind, label_pt = EXCLUDED.label_pt,
    accepted = EXCLUDED.accepted, preferred = EXCLUDED.preferred, note_pt = EXCLUDED.note_pt,
    updated_at = now(), updated_by = auth.uid()
  RETURNING to_jsonb(cleaner_activity_codes.*) INTO v_depois;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), 'cleaner_activity_code_set', 'cleaner_activity_codes', btrim(p_code),
          jsonb_build_object('antes', v_antes, 'depois', v_depois));
  RETURN v_depois;
END $$;

CREATE OR REPLACE FUNCTION public.admin_cleaners_activity_status()
RETURNS TABLE (
  cleaner_id uuid, name text, approval_status text, tem_comprovativo boolean,
  codigos text[], codigo_certo boolean, sem_atividade_aberta boolean, estado text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT c.id, c.name, c.approval_status,
         (c.docs ? 'comprovativo_atividade') AS tem_comprovativo,
         COALESCE(ARRAY(SELECT jsonb_array_elements_text(
                    CASE WHEN jsonb_typeof(c.docs -> 'atividade_codigos') = 'array'
                         THEN c.docs -> 'atividade_codigos' ELSE '[]'::jsonb END)), '{}') AS codigos,
         EXISTS (SELECT 1 FROM cleaner_activity_codes a
                  WHERE a.accepted
                    AND a.code = ANY (COALESCE(ARRAY(SELECT jsonb_array_elements_text(
                          CASE WHEN jsonb_typeof(c.docs -> 'atividade_codigos') = 'array'
                               THEN c.docs -> 'atividade_codigos' ELSE '[]'::jsonb END)), '{}'))) AS codigo_certo,
         COALESCE((c.docs ->> 'sem_atividade_aberta')::boolean, false),
         CASE
           WHEN NOT (c.docs ? 'comprovativo_atividade') THEN 'falta o comprovativo'
           WHEN EXISTS (SELECT 1 FROM cleaner_activity_codes a
                         WHERE a.accepted AND a.preferred
                           AND a.code = ANY (COALESCE(ARRAY(SELECT jsonb_array_elements_text(
                                 CASE WHEN jsonb_typeof(c.docs -> 'atividade_codigos') = 'array'
                                      THEN c.docs -> 'atividade_codigos' ELSE '[]'::jsonb END)), '{}')))
             THEN 'código certo'
           WHEN EXISTS (SELECT 1 FROM cleaner_activity_codes a
                         WHERE a.accepted
                           AND a.code = ANY (COALESCE(ARRAY(SELECT jsonb_array_elements_text(
                                 CASE WHEN jsonb_typeof(c.docs -> 'atividade_codigos') = 'array'
                                      THEN c.docs -> 'atividade_codigos' ELSE '[]'::jsonb END)), '{}')))
             THEN 'aceite, falta o 81210'
           ELSE 'código errado ou não lido'
         END
  FROM cleaners c
  ORDER BY (c.approval_status = 'approved') DESC, c.name;
END $$;

REVOKE ALL ON FUNCTION public.admin_set_cleaner_activity_code(text, text, text, boolean, boolean, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_cleaners_activity_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_cleaner_activity_code(text, text, text, boolean, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cleaners_activity_status() TO authenticated;
