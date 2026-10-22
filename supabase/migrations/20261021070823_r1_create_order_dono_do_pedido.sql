-- ⚠️ MEXE EM PAGAMENTO/DINHEIRO (função que cria os pedidos).
-- R1 · create_order: o pedido fica sempre no nome de quem tem a sessão de cliente. Só o servidor
-- (service_role ou sem sessão, ex.: a Edge finalize-order-from-intent) e o admin criam pedidos em nome
-- de outra pessoa. "Vai" do Danilo a 21/10/2026 06:15Z (e2e_log 4087) + SIM do revisor (e2e_log 4100).
-- Mesma assinatura create_order(p_input jsonb). Troca 1 linha (a linha 70), contada: aparece 1 vez.
-- md5 ANTES (21/10/2026): md5(pg_get_functiondef('public.create_order(jsonb)'::regprocedure)) = 8688fcf8b22429246079ec873d076fd8
-- Se a função mudou desde então, o bloco pára e não muda nada.
-- Copia de seguranca da funcao antiga em bkp_fn_create_order_20261021 (RLS ligada, so o servidor le).
CREATE TABLE IF NOT EXISTS public.bkp_fn_create_order_20261021 (
  guardado_em timestamptz NOT NULL DEFAULT now(),
  md5         text NOT NULL,
  def         text NOT NULL);
ALTER TABLE public.bkp_fn_create_order_20261021 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_fn_create_order_20261021 FROM PUBLIC, anon, authenticated;

DO $r1$
DECLARE
  v_def    text := pg_get_functiondef('public.create_order(jsonb)'::regprocedure);
  v_ancora text := $a$  v_user_id := COALESCE((p_input->>'user_id')::UUID, auth.uid());$a$;
  v_nova   text := $n$  -- R1 (21/10/2026, "Vai" do Danilo): com sessao de cliente, o pedido e sempre de quem esta ligado.
  -- So o servidor (service_role, sem sessao) e o admin criam pedidos em nome de outra pessoa.
  v_user_id := CASE
                 WHEN auth.uid() IS NULL
                   OR public.is_admin()
                   OR COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
                 THEN COALESCE((p_input->>'user_id')::UUID, auth.uid())
                 ELSE auth.uid()
               END;$n$;
  v_depois text;
BEGIN
  IF md5(v_def) <> '8688fcf8b22429246079ec873d076fd8' THEN
    RAISE EXCEPTION 'R1: create_order mudou desde 21/10 (md5 agora %); rever antes de aplicar', md5(v_def);
  END IF;
  IF (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora) <> 1 THEN
    RAISE EXCEPTION 'R1: a linha-ancora tem de aparecer exatamente 1 vez';
  END IF;
  INSERT INTO public.bkp_fn_create_order_20261021 (md5, def) VALUES (md5(v_def), v_def);
  EXECUTE replace(v_def, v_ancora, v_nova);
  v_depois := pg_get_functiondef('public.create_order(jsonb)'::regprocedure);
  IF replace(v_depois, v_nova, v_ancora) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION 'R1: fora da linha trocada, a funcao nova nao ficou igual a antiga';
  END IF;
  IF has_function_privilege('anon', 'public.create_order(jsonb)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'R1: create_order ficou aberta a quem nao tem sessao';
  END IF;
  RAISE NOTICE 'R1 aplicado. md5 novo: %', md5(v_depois);
END $r1$;
