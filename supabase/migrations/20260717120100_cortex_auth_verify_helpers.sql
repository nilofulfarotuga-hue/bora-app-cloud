-- PARTE B (2026-07-17): helpers read-only para o carteiro RESPEITAR uma
-- autorização humana já verificável na base (aprovada na Central com JWT admin),
-- em vez de re-gatilhar zona_vermelha() num loop infinito.
-- Aplicada em produção via MCP (migration cortex_auth_verify_helpers_partB).
--
-- Estes helpers são INERTES: nada os chama até o sync/carteiro serem instalados
-- no VPS. NÃO alteram zona_vermelha(), o classificador, a Lista Vermelha, o Juiz
-- nem o zonas_diff.py. Só permitem VERIFICAR autorização contra a base.
--
-- BARREIRA: a única rotina com permissão de ESCREVER autorizado_por_admin/audit_id
-- no frontmatter é o passo 2 do sync, a partir de uma linha aprovada_danilo. O
-- carteiro apenas LÊ o ficheiro e RE-VERIFICA o audit_id aqui contra
-- admin_audit_log (nunca confia no texto do ficheiro).

-- Helper 1: o carteiro chama isto para confirmar que um audit_id do frontmatter
-- existe MESMO como aprovação de proposta vermelha. Devolve só boolean.
CREATE OR REPLACE FUNCTION public.cortex_verify_audit_id(p_audit_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_audit_log
    WHERE id = p_audit_id
      AND action = 'cortex_proposal_approve'
  );
$$;

-- Helper 2: o sync chama isto (chave anon) para obter os campos de autorização
-- AUTORITATIVOS de uma proposta aprovada — nunca do texto/ficheiro. Devolve NULL
-- se a proposta não estiver aprovada_danilo ou não tiver trilho de auditoria real.
CREATE OR REPLACE FUNCTION public.cortex_get_auth_for_pid(p_pid text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid   uuid;
  v_em    timestamptz;
  v_audit uuid;
BEGIN
  SELECT revisada_por, revisada_em INTO v_uid, v_em
  FROM public.cortex_red_proposals
  WHERE pid = p_pid AND status = 'aprovada_danilo'
  LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_audit
  FROM public.admin_audit_log
  WHERE action = 'cortex_proposal_approve'
    AND details->>'pid' = p_pid
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_audit IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'autorizado_por_admin', v_uid,
    'autorizado_em',        v_em,
    'audit_id',             v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cortex_verify_audit_id(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cortex_get_auth_for_pid(text) TO anon, authenticated;
