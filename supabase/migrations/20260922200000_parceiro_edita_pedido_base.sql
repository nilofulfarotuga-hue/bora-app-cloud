-- ============================================================================
-- Parceiro edita pedido — BASE (zona verde, aplicada)       run: parceiro-edita-pedido-2026-09-22
-- ----------------------------------------------------------------------------
-- O que ESTA migration faz (nada aqui mexe em dinheiro):
--   1. Tabela public.order_edits — o registo de cada alteração que o dono de uma
--      loja PARCEIRA faz a um pedido já feito (acrescentar / tirar / mais unidades).
--   2. RLS: o parceiro vê as da loja dele; o cliente vê as do pedido dele; o
--      estafeta atribuído vê as do pedido que leva; o admin vê tudo.
--      NINGUÉM insere/actualiza directo — só pelas funções (SECURITY DEFINER),
--      para os valores nunca virem da app.
--   3. Tempo real (publicação supabase_realtime) — PADRAO 2.4.
--   4. Interruptor platform_settings.order_edit_enabled = false. As telas só
--      mostram os botões quando está ligado.
--   5. Admin (PT-BR): lista geral com filtro por loja/estado e cancelar uma
--      edição pendente (não move dinheiro — só fecha a proposta).
--
-- O que fica FORA (dinheiro, espera o "vai" do Danilo):
--   20260922200100_PROPOSTA_parceiro_edita_pedido_dinheiro.sql
--   supabase/functions/order-edit-settle/  (reembolso parcial / cobrança Stripe)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.order_edits (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  grupo_id         uuid        NOT NULL,
  order_id         text        NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  restaurant_id    text        NOT NULL,
  editado_por      uuid,
  tipo             text        NOT NULL CHECK (tipo IN ('add','remove','qty')),
  linha_idx        integer,
  product_id       text,
  nome             text        NOT NULL,
  opcoes           jsonb       NOT NULL DEFAULT '[]'::jsonb,
  quantidade       integer     NOT NULL CHECK (quantidade > 0),
  preco_unitario   numeric(10,2) NOT NULL CHECK (preco_unitario >= 0),
  subtotal_antes   numeric(10,2) NOT NULL,
  subtotal_depois  numeric(10,2) NOT NULL,
  total_antes      numeric(10,2) NOT NULL,
  total_depois     numeric(10,2) NOT NULL,
  estado           text        NOT NULL DEFAULT 'pendente_cliente'
                   CHECK (estado IN ('pendente_cliente','aceite','recusado','aplicado','cancelado')),
  motivo           text,
  liquidacao       jsonb       NOT NULL DEFAULT '{}'::jsonb,
  respondido_em    timestamptz,
  aplicado_em      timestamptz,
  criado_em        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.order_edits IS
  'Alterações do dono da loja parceira a um pedido já feito (acrescentar/tirar). '
  'Uma proposta = um grupo_id (várias linhas). Escrita só por RPC. '
  'liquidacao = o que se moveu de dinheiro (reembolso/cobrança/dinheiro na entrega).';

CREATE INDEX IF NOT EXISTS order_edits_order_idx      ON public.order_edits (order_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS order_edits_grupo_idx      ON public.order_edits (grupo_id);
CREATE INDEX IF NOT EXISTS order_edits_restaurant_idx ON public.order_edits (restaurant_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS order_edits_pendente_idx   ON public.order_edits (estado) WHERE estado IN ('pendente_cliente','aceite');

ALTER TABLE public.order_edits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_edits_parceiro_select ON public.order_edits;
CREATE POLICY order_edits_parceiro_select ON public.order_edits
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.restaurants r
                  WHERE r.id = order_edits.restaurant_id AND r.user_id = auth.uid()));

DROP POLICY IF EXISTS order_edits_cliente_select ON public.order_edits;
CREATE POLICY order_edits_cliente_select ON public.order_edits
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.orders o
                  WHERE o.id = order_edits.order_id AND o.user_id = auth.uid()));

DROP POLICY IF EXISTS order_edits_estafeta_select ON public.order_edits;
CREATE POLICY order_edits_estafeta_select ON public.order_edits
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.orders o
                  WHERE o.id = order_edits.order_id AND o.assigned_driver_id = auth.uid()::text));

DROP POLICY IF EXISTS order_edits_admin_select ON public.order_edits;
CREATE POLICY order_edits_admin_select ON public.order_edits
  FOR SELECT TO authenticated
  USING (public.is_admin());

REVOKE ALL ON public.order_edits FROM PUBLIC, anon;
GRANT SELECT ON public.order_edits TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'order_edits') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.order_edits;
  END IF;
END $$;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('order_edit_enabled', 'false'::jsonb,
        'Parceiro pode acrescentar/tirar produtos num pedido já feito (liga só depois de aplicada a parte do dinheiro).',
        'features')
ON CONFLICT (key) DO NOTHING;

-- ── Admin: lista geral (PT-BR no ecrã) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_order_edits(
  p_restaurant_id text DEFAULT NULL,
  p_estado        text DEFAULT NULL,
  p_order_id      text DEFAULT NULL,
  p_limit         integer DEFAULT 300
)
RETURNS TABLE (
  id uuid, grupo_id uuid, order_id text, restaurant_id text, loja text,
  editado_por uuid, editado_por_email text, tipo text, linha_idx integer,
  product_id text, nome text, opcoes jsonb, quantidade integer, preco_unitario numeric,
  subtotal_antes numeric, subtotal_depois numeric, total_antes numeric, total_depois numeric,
  estado text, motivo text, liquidacao jsonb, respondido_em timestamptz,
  aplicado_em timestamptz, criado_em timestamptz, payment_method text, order_status text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT e.id, e.grupo_id, e.order_id, e.restaurant_id, r.name,
         e.editado_por, u.email::text, e.tipo, e.linha_idx,
         e.product_id, e.nome, e.opcoes, e.quantidade, e.preco_unitario,
         e.subtotal_antes, e.subtotal_depois, e.total_antes, e.total_depois,
         e.estado, e.motivo, e.liquidacao, e.respondido_em,
         e.aplicado_em, e.criado_em, o.payment_method, o.status
    FROM public.order_edits e
    LEFT JOIN public.restaurants r ON r.id = e.restaurant_id
    LEFT JOIN public.orders o      ON o.id = e.order_id
    LEFT JOIN auth.users u         ON u.id = e.editado_por
   WHERE (p_restaurant_id IS NULL OR e.restaurant_id = p_restaurant_id)
     AND (p_estado IS NULL OR e.estado = p_estado)
     AND (p_order_id IS NULL OR e.order_id = p_order_id)
   ORDER BY e.criado_em DESC, e.id
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 300), 2000));
END $$;

REVOKE ALL ON FUNCTION public.admin_list_order_edits(text, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_order_edits(text, text, text, integer) TO authenticated;

-- ── Admin: cancelar uma proposta pendente (não move dinheiro) ───────────────
CREATE OR REPLACE FUNCTION public.admin_cancel_order_edit(p_grupo_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_n integer; v_order text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = '42501'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN RAISE EXCEPTION 'MOTIVO_OBRIGATORIO'; END IF;

  SELECT order_id INTO v_order FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  UPDATE public.order_edits
     SET estado = 'cancelado', motivo = 'admin: ' || trim(p_motivo), respondido_em = now()
   WHERE grupo_id = p_grupo_id AND estado = 'pendente_cliente';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'NAO_HA_PENDENTE');
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt() ->> 'email', 'order_edit_cancel', 'order', v_order,
          jsonb_build_object('grupo_id', p_grupo_id, 'motivo', p_motivo, 'linhas', v_n));

  RETURN jsonb_build_object('ok', true, 'linhas', v_n);
END $$;

REVOKE ALL ON FUNCTION public.admin_cancel_order_edit(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_order_edit(uuid, text) TO authenticated;
