-- Painel admin do PORTEIRO DO TELEGRAM (missão fecho-pendentes-2026-10-31, Bloco 4).
-- A tabela porteiro_entrada não tem políticas (só service_role). O painel lê e reenvia por duas funções fechadas a
-- quem não é admin (is_admin()). Reenviar = pôr uma cópia nova na fila (o original fica como estava, para histórico);
-- o porteiro da VPS trata a cópia nos 10 s seguintes. Não toca em dinheiro, pedidos nem RLS de outras tabelas.

CREATE OR REPLACE FUNCTION public.admin_porteiro_listar(p_limit integer DEFAULT 100, p_so_por_tratar boolean DEFAULT false)
RETURNS TABLE (
  id bigint, created_at timestamptz, origem text, nivel text, texto text,
  tratado_em timestamptz, resultado jsonb, destino text, estado text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $f$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: só admin';
  END IF;
  RETURN QUERY
    SELECT e.id, e.created_at, e.origem, e.nivel, e.texto, e.tratado_em, e.resultado,
           NULLIF(e.resultado->>'destino', ''),
           CASE WHEN e.tratado_em IS NULL THEN 'por tratar'
                WHEN COALESCE((e.resultado->>'ok')::boolean, true) = false THEN 'falhou'
                ELSE 'tratado' END
      FROM public.porteiro_entrada e
     WHERE (NOT COALESCE(p_so_por_tratar, false) OR e.tratado_em IS NULL)
     ORDER BY e.id DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
END;
$f$;

CREATE OR REPLACE FUNCTION public.admin_porteiro_reenviar(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $f$
DECLARE
  v_row  public.porteiro_entrada%ROWTYPE;
  v_novo bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: só admin';
  END IF;
  SELECT * INTO v_row FROM public.porteiro_entrada WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_existe');
  END IF;
  INSERT INTO public.porteiro_entrada (origem, nivel, texto)
  VALUES (left('admin-reenvio:' || v_row.origem, 60), v_row.nivel, v_row.texto)
  RETURNING id INTO v_novo;
  BEGIN
    PERFORM public.log_admin_action('porteiro_reenviar'::text, 'porteiro_entrada'::text, p_id::text,
                                    jsonb_build_object('novo_id', v_novo, 'nivel', v_row.nivel));
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'log_admin_action falhou: %', SQLERRM;
  END;
  RETURN jsonb_build_object('ok', true, 'novo_id', v_novo);
END;
$f$;

REVOKE ALL ON FUNCTION public.admin_porteiro_listar(integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_porteiro_reenviar(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_porteiro_listar(integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_porteiro_reenviar(bigint) TO authenticated;
