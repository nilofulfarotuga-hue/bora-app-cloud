-- Item 80 do goal paridade-admin-360 (P0 compliance, auditoria 360°):
-- Revisão admin de documentos TVDE (IMT / DL 45/2018). Não existia NENHUM
-- armazenamento de docs TVDE — motoristas TVDE são drivers normais com docs
-- genéricos em drivers.*_url, sem doc de certificado TVDE nem estado por documento.
--
-- Esta migration cria a fundação + a superfície admin. O upload no lado do
-- motorista (app) é follow-up sinalizado na Central — o admin pode desde já
-- registar e rever documentos recebidos por outros canais.

CREATE TABLE IF NOT EXISTS public.tvde_driver_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  doc_type text NOT NULL CHECK (doc_type IN (
    'carta_conducao',           -- carta de condução válida
    'certificado_tvde_imt',     -- certificado de motorista TVDE (IMT)
    'dut',                      -- documento único de transporte / DUA do veículo
    'seguro',                   -- seguro (responsabilidade civil + acidentes pessoais)
    'inspecao',                 -- inspeção periódica do veículo
    'registo_criminal'          -- certificado de registo criminal
  )),
  file_path text NOT NULL,      -- path no bucket privado driver-documents
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  review_note text,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid,
  decided_at timestamptz,
  UNIQUE (driver_id, doc_type, uploaded_at)
);

CREATE INDEX IF NOT EXISTS idx_tvde_docs_status ON public.tvde_driver_documents (status, uploaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_tvde_docs_driver ON public.tvde_driver_documents (driver_id);

ALTER TABLE public.tvde_driver_documents ENABLE ROW LEVEL SECURITY;

-- Motorista vê e submete os próprios documentos (upload UI = follow-up)
CREATE POLICY tvde_docs_driver_select ON public.tvde_driver_documents
  FOR SELECT USING (driver_id = auth.uid());
CREATE POLICY tvde_docs_driver_insert ON public.tvde_driver_documents
  FOR INSERT WITH CHECK (driver_id = auth.uid() AND status = 'pending');

-- Admin vê tudo (decisão é via RPC SECURITY DEFINER, não UPDATE direto)
CREATE POLICY tvde_docs_admin_select ON public.tvde_driver_documents
  FOR SELECT USING (is_admin());

-- Lista para o ecrã admin (join com nome/telefone do motorista)
CREATE OR REPLACE FUNCTION public.admin_list_tvde_documents(
  p_status text DEFAULT NULL, p_limit int DEFAULT 200)
RETURNS TABLE (
  id uuid, driver_id uuid, driver_name text, driver_phone text,
  doc_type text, file_path text, status text, review_note text,
  uploaded_at timestamptz, decided_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT d.id, d.driver_id, dr.name, dr.phone, d.doc_type, d.file_path,
         d.status, d.review_note, d.uploaded_at, d.decided_at
  FROM tvde_driver_documents d
  JOIN drivers dr ON dr.id = d.driver_id
  WHERE is_admin()
    AND (p_status IS NULL OR d.status = p_status)
  ORDER BY d.uploaded_at DESC
  LIMIT LEAST(COALESCE(p_limit, 200), 500);
$$;

-- Decisão (aprovar/rejeitar) com auditoria
CREATE OR REPLACE FUNCTION public.admin_review_tvde_document(
  p_doc_id uuid, p_decision text, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_doc tvde_driver_documents;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'admin_only';
  END IF;
  IF p_decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'decisao_invalida (approved|rejected)';
  END IF;
  IF p_decision = 'rejected' AND (p_note IS NULL OR length(trim(p_note)) < 5) THEN
    RAISE EXCEPTION 'rejeicao_exige_nota';
  END IF;

  UPDATE tvde_driver_documents
     SET status = p_decision, review_note = p_note,
         decided_by = auth.uid(), decided_at = now()
   WHERE id = p_doc_id AND status = 'pending'
   RETURNING * INTO v_doc;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'doc_nao_encontrado_ou_ja_decidido';
  END IF;

  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'tvde_doc_' || p_decision, 'tvde_driver_document', v_doc.id::text,
          jsonb_build_object('driver_id', v_doc.driver_id, 'doc_type', v_doc.doc_type, 'note', p_note));

  RETURN jsonb_build_object('ok', true, 'id', v_doc.id, 'status', v_doc.status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_tvde_documents(text, int) FROM anon;
REVOKE ALL ON FUNCTION public.admin_review_tvde_document(uuid, text, text) FROM anon;
