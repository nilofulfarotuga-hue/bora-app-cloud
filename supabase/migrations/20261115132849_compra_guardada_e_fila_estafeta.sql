-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115132849); antes estava no repo como 20261114190000_compra_guardada_e_fila_estafeta.sql
-- No servidor, statements guardou um carregador (copiado abaixo, comentado): leu a cópia deste ficheiro
-- descarregada do GitHub (net._http_response 157471) e só a executou depois de conferir o sha256
-- 554b7a54bad7eb4fe9e82d088edb115004134d35bea6d007ebcd6484e0dc16ab. O texto depois do carregador é
-- byte a byte o que correu (mesmo sha256, versão do commit 3451e519).
--
-- >>> carregador gravado em schema_migrations.statements (versão 20261115132849):
-- -- Caixa 39: ficheiro do commit 26faca7d (lido inteiro pela Claude.ai), executado a partir da copia
-- -- byte a byte descarregada, so se o sha256 for o conferido.
-- do $aplicar$
-- declare
--   v_sql text;
-- begin
--   select content into v_sql from net._http_response where id = 157471 and status_code = 200;
--   if v_sql is null then raise exception 'caixa 39: copia do ficheiro nao encontrada'; end if;
--   if encode(sha256(convert_to(v_sql,'UTF8')),'hex') <> '554b7a54bad7eb4fe9e82d088edb115004134d35bea6d007ebcd6484e0dc16ab' then
--     raise exception 'caixa 39: sha256 diferente do conferido, nada aplicado';
--   end if;
--   execute v_sql;
-- end
-- $aplicar$;
-- <<< fim do carregador; a seguir, o que ele executou.

-- ════════════════════════════════════════════════════════════════════════════
-- compra-guardada-2026-11-14 (+ adenda 1 do Danilo, 16:45: fila de pedidos)
--
-- Cicatriz (14/11/2026 16:32, pedido b2b746d7 · Auchan): o estafeta já tinha
-- comprado tudo, trocado as pizzas e marcado o queijo em falta; entrou um Favor
-- (09ee41da) e a app trocou de pedido. TUDO o que ele marcou desapareceu: o
-- progresso da compra só vivia na memória do telemóvel (orders.items ficou com
-- purchaseStatus 'pending' em todos os itens).
--
-- 1) order_purchase_drafts — o rascunho da compra, gravado a cada toque.
--    Só se escreve pela RPC estafeta_guardar_progresso_compra (estafeta
--    atribuído). NÃO mexe em preços, comissões, ganhos nem no fecho:
--    finalizar_talao_nao_parceiro / finalize_storeshopping_purchase_v2 ficam
--    iguais. _rascunho_compra_itens_fecho monta o p_items que o fecho já
--    recebe, para fechar por MCP/painel sem refazer a compra.
-- 2) fila_do_estafeta — a fila de cada estafeta (adenda 1): o pedido EM CURSO
--    (guardado em estafeta_pedido_em_curso: o que ele aceitou quando estava
--    livre) fica ativo, com os da mesma loja e os já recolhidos; os outros
--    ficam em espera até ele entregar. Ao entregar, passa a em curso o já
--    recolhido, senão o da mesma loja, senão: Favor URGENTE (express) →
--    entregas → Favor normal, e a hora de aceitação. A app tem a mesma regra em
--    lib/services/fila_estafeta.dart (gémeos: mudar um = mudar o outro).
--    Prova: supabase/tests/compra_guardada_fila_prova.mjs (PGlite, 45 casos).
-- 3) Aviso ao cliente de uma ENTREGA que fica em espera ("o estafeta está
--    noutro pedido perto de si"). Favor nunca avisa (o cliente escolheu a janela
--    de até 3 h). Um aviso por pedido (fila_avisos_cliente).
-- Não altera quem recebe ofertas (dispatch_candidatos_entrega fica igual).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Rascunho da compra ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_purchase_drafts (
  order_id            text PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  driver_uid          uuid NOT NULL,
  -- chave "<productId>#<n>" (n = 0 na 1.ª vez que o produto aparece em
  -- orders.items) → {"s": "bought"|"unavailable"|"pending", "q": quantidade}
  itens               jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- produtos acrescentados pelo estafeta (troca ou extra):
  -- [{"id":"extra_…","nome":"…","preco_cents":123,"qtd":1,"s":"bought"}]
  extras              jsonb NOT NULL DEFAULT '[]'::jsonb,
  bag_count           integer,
  receipt_total_cents integer,
  receipt_photo_path  text,
  -- número crescente do telemóvel: uma gravação atrasada nunca apaga uma mais nova
  client_seq          bigint NOT NULL DEFAULT 0,
  marcados            integer NOT NULL DEFAULT 0,
  gravacoes           integer NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.order_purchase_drafts IS
  'Rascunho da compra do estafeta (compra-guardada-2026-11-14): cada toque na lista '
  'de compras grava aqui. Escrita só por estafeta_guardar_progresso_compra.';

ALTER TABLE public.order_purchase_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_purchase_drafts FROM anon, authenticated;
GRANT ALL ON public.order_purchase_drafts TO service_role;

-- O estafeta atribuído (a mesma identidade que finalizar_talao_nao_parceiro
-- aceita: user_id em texto, ou drivers.id do próprio).
CREATE OR REPLACE FUNCTION public._estafeta_atribuido(p_assigned text, p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p_uid IS NOT NULL AND p_assigned IS NOT NULL AND (
    p_assigned = p_uid::text
    OR EXISTS (SELECT 1 FROM public.drivers d
                WHERE d.user_id = p_uid AND d.id::text = p_assigned));
$$;
REVOKE ALL ON FUNCTION public._estafeta_atribuido(text, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.estafeta_guardar_progresso_compra(
  p_order_id          text,
  p_itens             jsonb,
  p_extras            jsonb   DEFAULT NULL,
  p_sacos             integer DEFAULT NULL,
  p_total_talao_cents integer DEFAULT NULL,
  p_foto_url          text    DEFAULT NULL,
  p_seq               bigint  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_o    record;
  v_seq  bigint := COALESCE(p_seq, (extract(epoch FROM clock_timestamp()) * 1000)::bigint);
  v_k    text;
  v_v    jsonb;
  v_row  public.order_purchase_drafts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  END IF;

  SELECT id, assigned_driver_id, status, is_purchase_finalized
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND');
  END IF;
  IF NOT public._estafeta_atribuido(v_o.assigned_driver_id, v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_ASSIGNED_DRIVER');
  END IF;
  IF v_o.status IN ('delivered', 'cancelled', 'rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ORDER_CLOSED', 'status', v_o.status);
  END IF;
  IF COALESCE(v_o.is_purchase_finalized, false) THEN
    -- A compra já fechou: nada a guardar (a app larga a fila local).
    RETURN jsonb_build_object('ok', true, 'applied', false, 'finalized', true);
  END IF;

  -- Validação defensiva (toque duplo, valor nulo, payload estragado).
  IF p_itens IS NOT NULL AND jsonb_typeof(p_itens) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'campo', 'itens');
  END IF;
  IF p_extras IS NOT NULL AND jsonb_typeof(p_extras) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'campo', 'extras');
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(COALESCE(p_itens, '{}'::jsonb))) > 400
     OR jsonb_array_length(COALESCE(p_extras, '[]'::jsonb)) > 60 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'campo', 'tamanho');
  END IF;
  FOR v_k, v_v IN SELECT key, value FROM jsonb_each(COALESCE(p_itens, '{}'::jsonb)) LOOP
    IF jsonb_typeof(v_v) <> 'object'
       OR COALESCE(v_v->>'s', '') NOT IN ('bought', 'unavailable', 'pending') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'campo', v_k);
    END IF;
  END LOOP;
  IF p_sacos IS NOT NULL AND (p_sacos < 0 OR p_sacos > 99) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_BAG_COUNT');
  END IF;
  IF p_total_talao_cents IS NOT NULL
     AND (p_total_talao_cents < 0 OR p_total_talao_cents > 2000000) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_TOTAL');
  END IF;
  IF p_foto_url IS NOT NULL AND length(p_foto_url) > 500 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'campo', 'foto');
  END IF;

  INSERT INTO public.order_purchase_drafts AS d (
    order_id, driver_uid, itens, extras, bag_count, receipt_total_cents,
    receipt_photo_path, client_seq, marcados, gravacoes, updated_at
  ) VALUES (
    p_order_id, v_uid, COALESCE(p_itens, '{}'::jsonb), COALESCE(p_extras, '[]'::jsonb),
    p_sacos, p_total_talao_cents, NULLIF(trim(p_foto_url), ''), v_seq,
    (SELECT count(*) FROM jsonb_each(COALESCE(p_itens, '{}'::jsonb)) e
      WHERE e.value->>'s' IN ('bought', 'unavailable')),
    1, now()
  )
  ON CONFLICT (order_id) DO UPDATE SET
    driver_uid          = v_uid,
    itens               = COALESCE(p_itens, d.itens),
    extras              = COALESCE(p_extras, d.extras),
    bag_count           = COALESCE(p_sacos, d.bag_count),
    receipt_total_cents = COALESCE(p_total_talao_cents, d.receipt_total_cents),
    receipt_photo_path  = COALESCE(NULLIF(trim(p_foto_url), ''), d.receipt_photo_path),
    client_seq          = v_seq,
    marcados            = (SELECT count(*) FROM jsonb_each(COALESCE(p_itens, d.itens)) e
                            WHERE e.value->>'s' IN ('bought', 'unavailable')),
    gravacoes           = d.gravacoes + 1,
    updated_at          = now()
  -- Igual = repetição da mesma gravação (idempotente); menor = atrasada, ignora.
  WHERE d.client_seq <= v_seq
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    SELECT * INTO v_row FROM public.order_purchase_drafts WHERE order_id = p_order_id;
    RETURN jsonb_build_object('ok', true, 'applied', false, 'stale', true,
      'seq', v_row.client_seq, 'updated_at', v_row.updated_at);
  END IF;

  RETURN jsonb_build_object('ok', true, 'applied', true, 'seq', v_row.client_seq,
    'updated_at', v_row.updated_at, 'marcados', v_row.marcados);
END;
$$;
REVOKE ALL ON FUNCTION public.estafeta_guardar_progresso_compra(text, jsonb, jsonb, integer, integer, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_guardar_progresso_compra(text, jsonb, jsonb, integer, integer, text, bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.estafeta_ler_progresso_compra(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_o   record;
  v_d   jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  END IF;
  SELECT id, assigned_driver_id, status, is_purchase_finalized
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND');
  END IF;
  IF NOT (public._estafeta_atribuido(v_o.assigned_driver_id, v_uid) OR public.is_admin()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_ASSIGNED_DRIVER');
  END IF;
  SELECT to_jsonb(d) - 'driver_uid' INTO v_d
    FROM public.order_purchase_drafts d WHERE d.order_id = p_order_id;
  RETURN jsonb_build_object('ok', true, 'status', v_o.status,
    'finalized', COALESCE(v_o.is_purchase_finalized, false), 'rascunho', v_d);
END;
$$;
REVOKE ALL ON FUNCTION public.estafeta_ler_progresso_compra(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_ler_progresso_compra(text) TO authenticated;

-- O p_items que finalizar_talao_nao_parceiro já recebe, montado a partir do
-- rascunho — o mesmo formato de TalaoNaoParceiroService.montarItens (app).
-- Só monta: não fecha nada e não calcula dinheiro.
CREATE OR REPLACE FUNCTION public._rascunho_compra_itens_fecho(p_order_id text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH it AS (
    SELECT e.value AS v, e.ordinality AS n,
           COALESCE(NULLIF(e.value->>'productId', ''), NULLIF(e.value->>'product_id', ''),
                    e.value->>'name', '') AS pid
      FROM public.orders o,
           jsonb_array_elements(COALESCE(o.items, '[]'::jsonb)) WITH ORDINALITY e
     WHERE o.id = p_order_id
  ), k AS (
    SELECT v, n, pid,
           pid || '#' || (row_number() OVER (PARTITION BY pid ORDER BY n) - 1) AS chave
      FROM it
  ), d AS (
    SELECT itens, extras FROM public.order_purchase_drafts WHERE order_id = p_order_id
  )
  SELECT COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'original_item_id', k.pid,
               'original_name', COALESCE(k.v->>'name', ''),
               'original_price_cents', round(COALESCE((k.v->>'price')::numeric, 0) * 100)::int,
               'original_qty', COALESCE((k.v->>'quantity')::int, 1),
               'status', CASE WHEN (SELECT d.itens->k.chave->>'s' FROM d) = 'unavailable'
                              THEN 'unavailable' ELSE 'purchased' END)
             ORDER BY k.n)
        FROM k), '[]'::jsonb)
    || COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'original_name', COALESCE(x->>'nome', ''),
               'original_price_cents', 0,
               'original_qty', COALESCE((x->>'qtd')::int, 1),
               'status', 'added',
               'actual_name', COALESCE(x->>'nome', ''),
               'actual_price_cents', COALESCE((x->>'preco_cents')::int, 0),
               'actual_qty', COALESCE((x->>'qtd')::int, 1)))
        FROM d, jsonb_array_elements(COALESCE(d.extras, '[]'::jsonb)) x
       -- só os acrescentados marcados como comprados (um desmarcado não conta)
       WHERE COALESCE(x->>'s', 'bought') = 'bought'), '[]'::jsonb);
$$;
REVOKE ALL ON FUNCTION public._rascunho_compra_itens_fecho(text) FROM PUBLIC, anon, authenticated;

-- Painel (PT-BR): o rascunho de um pedido, item a item, com o que é preciso para
-- fechar sem refazer a compra.
CREATE OR REPLACE FUNCTION public.admin_rascunho_compra(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_o   record;
  v_d   public.order_purchase_drafts%ROWTYPE;
  v_itens jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT id, status, service_type, vendor_name, customer_name, assigned_driver_id,
         is_partner_store, is_purchase_finalized, payment_method, items
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'ORDER_NOT_FOUND'); END IF;
  SELECT * INTO v_d FROM public.order_purchase_drafts WHERE order_id = p_order_id;

  WITH it AS (
    SELECT e.value AS v, e.ordinality AS n,
           COALESCE(NULLIF(e.value->>'productId', ''), NULLIF(e.value->>'product_id', ''),
                    e.value->>'name', '') AS pid
      FROM jsonb_array_elements(COALESCE(v_o.items, '[]'::jsonb)) WITH ORDINALITY e
  ), k AS (
    SELECT v, n, pid, pid || '#' || (row_number() OVER (PARTITION BY pid ORDER BY n) - 1) AS chave
      FROM it
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'nome', COALESCE(k.v->>'name', ''),
           'quantidade', COALESCE((k.v->>'quantity')::int, 1),
           'preco', (k.v->>'price')::numeric,
           'estado', COALESCE(v_d.itens->k.chave->>'s', 'pending')) ORDER BY k.n), '[]'::jsonb)
    INTO v_itens FROM k;

  RETURN jsonb_build_object(
    'ok', true,
    'pedido', jsonb_build_object(
      'id', v_o.id, 'status', v_o.status, 'service_type', v_o.service_type,
      'loja', v_o.vendor_name, 'cliente', v_o.customer_name,
      'estafeta', (SELECT d.name FROM public.drivers d
                    WHERE d.user_id::text = v_o.assigned_driver_id
                       OR d.id::text = v_o.assigned_driver_id LIMIT 1),
      'parceiro', COALESCE(v_o.is_partner_store, false),
      'compra_fechada', COALESCE(v_o.is_purchase_finalized, false),
      'pagamento', v_o.payment_method),
    'tem_rascunho', v_d.order_id IS NOT NULL,
    'itens', v_itens,
    'extras', COALESCE(v_d.extras, '[]'::jsonb),
    'sacos', v_d.bag_count,
    'total_talao_cents', v_d.receipt_total_cents,
    'foto_talao', v_d.receipt_photo_path,
    'marcados', COALESCE(v_d.marcados, 0),
    'gravacoes', COALESCE(v_d.gravacoes, 0),
    'ultima_marcacao', v_d.updated_at,
    'itens_para_fecho', public._rascunho_compra_itens_fecho(p_order_id));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_rascunho_compra(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_rascunho_compra(text) TO authenticated;

-- ── 2. Fila do estafeta (adenda 1) ──────────────────────────────────────────
-- O pedido EM CURSO de cada estafeta fica guardado (não se adivinha): é o que
-- ele aceitou quando estava livre; quando o entrega (ou é cancelado/passa a
-- outro), o seguinte da fila passa a em curso. Sem isto, uma entrega aceite
-- por cima de um Favor já começado passaria-lhe à frente.
CREATE TABLE IF NOT EXISTS public.estafeta_pedido_em_curso (
  driver_uid uuid PRIMARY KEY,
  order_id   text NOT NULL,
  desde      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.estafeta_pedido_em_curso ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.estafeta_pedido_em_curso FROM anon, authenticated;
GRANT ALL ON public.estafeta_pedido_em_curso TO service_role;

-- O utilizador (auth) do estafeta a partir de assigned_driver_id (user_id em
-- texto, ou drivers.id).
CREATE OR REPLACE FUNCTION public._estafeta_uid_de(p_assigned text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT d.user_id FROM public.drivers d
   WHERE p_assigned IS NOT NULL
     AND (d.user_id::text = p_assigned OR d.id::text = p_assigned)
   ORDER BY (d.user_id::text = p_assigned) DESC
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._estafeta_uid_de(text) FROM PUBLIC, anon, authenticated;

-- Os pedidos ativos do estafeta, com a classe da fila.
CREATE OR REPLACE FUNCTION public._fila_pedidos_ativos(p_driver_uid uuid)
RETURNS TABLE (id text, status text, service_type text, errand_speed text,
               restaurant_id text, vendor_name text, customer_name text,
               aceite timestamptz, classe integer, recolhido boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT o.id, o.status, o.service_type, o.errand_speed, o.restaurant_id,
         o.vendor_name, o.customer_name,
         COALESCE(o.driver_assigned_at, o.created_at),
         CASE
           WHEN o.service_type = 'errand' AND COALESCE(o.errand_speed, 'normal') = 'express' THEN 1
           WHEN o.service_type = 'errand' THEN 3
           ELSE 2
         END,
         o.status IN ('pickedUp', 'onTheWay')
    FROM public.orders o
   WHERE o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
     AND (o.assigned_driver_id = p_driver_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d
                                       WHERE d.user_id = p_driver_uid));
$$;
REVOKE ALL ON FUNCTION public._fila_pedidos_ativos(uuid) FROM PUBLIC, anon, authenticated;

-- O próximo em curso: o que já está recolhido; senão um com a compra já
-- começada (rascunho com marcações); senão o da mesma loja do que acabou (a
-- volta continua); senão a ordem da fila (urgente → entrega → Favor normal, e
-- a hora de aceitação). A app faz o mesmo (FilaEstafeta).
-- (COALESCE: um pedido sem loja daria NULL, e NULL vem primeiro num DESC.)
CREATE OR REPLACE FUNCTION public._fila_proximo_em_curso(
  p_driver_uid uuid, p_excluir text, p_loja_anterior text DEFAULT NULL)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p.id
    FROM public._fila_pedidos_ativos(p_driver_uid) p
   WHERE p.id IS DISTINCT FROM p_excluir
   ORDER BY p.recolhido DESC,
            EXISTS (SELECT 1 FROM public.order_purchase_drafts d
                     WHERE d.order_id = p.id AND d.marcados > 0) DESC,
            COALESCE(p.service_type <> 'errand' AND p_loja_anterior IS NOT NULL
                     AND p.restaurant_id = p_loja_anterior, false) DESC,
            p.classe, p.aceite, p.id
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._fila_proximo_em_curso(uuid, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_fila_em_curso()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ativo_novo  boolean := NEW.status IN ('driverAccepted', 'pickedUp', 'onTheWay');
  v_saiu        boolean := false;
  v_uid  uuid;
  v_old  uuid;
  v_cur  text;
  v_prox text;
BEGIN
  -- Nunca trava a mudança do pedido: no pior caso a fila usa a regra de recurso.
  BEGIN
    IF TG_OP = 'UPDATE' THEN
      IF OLD.status IN ('driverAccepted', 'pickedUp', 'onTheWay') THEN
        -- Compara a PESSOA (drivers.id → user_id), não o texto: reescrever o
        -- mesmo estafeta de drivers.id para user_id não é "sair".
        v_saiu := NOT v_ativo_novo
                  OR (NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id
                      AND public._estafeta_uid_de(NEW.assigned_driver_id)
                          IS DISTINCT FROM public._estafeta_uid_de(OLD.assigned_driver_id));
      END IF;
    END IF;
    -- Saiu do estafeta (entregue, cancelado, recusado ou passado a outro).
    IF v_saiu THEN
      v_old := public._estafeta_uid_de(OLD.assigned_driver_id);
      IF v_old IS NOT NULL THEN
        -- dois pedidos do mesmo estafeta a mudar ao mesmo tempo: um de cada vez
        PERFORM pg_advisory_xact_lock(hashtext('fila_em_curso:' || v_old::text));
        SELECT order_id INTO v_cur FROM public.estafeta_pedido_em_curso WHERE driver_uid = v_old;
        IF v_cur = NEW.id THEN
          v_prox := public._fila_proximo_em_curso(v_old, NEW.id,
                      CASE WHEN NEW.service_type <> 'errand' THEN NEW.restaurant_id END);
          IF v_prox IS NULL THEN
            DELETE FROM public.estafeta_pedido_em_curso WHERE driver_uid = v_old;
          ELSE
            UPDATE public.estafeta_pedido_em_curso
               SET order_id = v_prox, desde = now()
             WHERE driver_uid = v_old;
          END IF;
        END IF;
      END IF;
    END IF;

    -- Aceite (ou ativo) com estafeta: se ele estava livre, este é o em curso;
    -- se já tinha um em curso ativo, este fica na fila (nada muda aqui).
    IF v_ativo_novo AND NEW.assigned_driver_id IS NOT NULL THEN
      v_uid := public._estafeta_uid_de(NEW.assigned_driver_id);
      IF v_uid IS NOT NULL THEN
        -- dois pedidos aceites ao mesmo tempo com o estafeta livre: o primeiro
        -- a chegar aqui fica em curso, o outro vê-o e vai para a fila
        PERFORM pg_advisory_xact_lock(hashtext('fila_em_curso:' || v_uid::text));
        SELECT e.order_id INTO v_cur FROM public.estafeta_pedido_em_curso e WHERE e.driver_uid = v_uid;
        IF v_cur IS NULL OR NOT EXISTS (
             SELECT 1 FROM public._fila_pedidos_ativos(v_uid) p WHERE p.id = v_cur) THEN
          INSERT INTO public.estafeta_pedido_em_curso (driver_uid, order_id, desde)
          VALUES (v_uid, NEW.id, now())
          ON CONFLICT (driver_uid) DO UPDATE SET order_id = EXCLUDED.order_id, desde = now();
        END IF;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'fn_fila_em_curso: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_fila_em_curso() FROM PUBLIC, anon, authenticated;

-- "trg_fila_0_…" corre antes de "trg_fila_avisar_cliente" (ordem alfabética):
-- o aviso ao cliente já vê o em curso certo.
DROP TRIGGER IF EXISTS trg_fila_0_em_curso ON public.orders;
CREATE TRIGGER trg_fila_0_em_curso
  AFTER INSERT OR UPDATE OF status, assigned_driver_id ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_fila_em_curso();

-- Pedidos que já estavam ativos quando isto entrou: o em curso de cada
-- estafeta é o que ele já recolheu; senão o da compra começada; senão o
-- PRIMEIRO que aceitou (não a classe — quem está a meio de uma compra com um
-- Favor urgente aceite por cima continua na compra).
INSERT INTO public.estafeta_pedido_em_curso (driver_uid, order_id)
SELECT e.uid,
       (SELECT p.id FROM public._fila_pedidos_ativos(e.uid) p
         ORDER BY p.recolhido DESC,
                  EXISTS (SELECT 1 FROM public.order_purchase_drafts d
                           WHERE d.order_id = p.id AND d.marcados > 0) DESC,
                  p.aceite, p.id
         LIMIT 1)
  FROM (SELECT DISTINCT public._estafeta_uid_de(o.assigned_driver_id) AS uid
          FROM public.orders o
         WHERE o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
           AND o.assigned_driver_id IS NOT NULL) e
 WHERE e.uid IS NOT NULL
ON CONFLICT (driver_uid) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fila_do_estafeta(p_driver_uid uuid)
RETURNS TABLE (
  order_id      text,
  posicao       integer,
  estado        text,     -- 'ativo' | 'em_espera'
  classe        integer,  -- 1 Favor urgente · 2 entrega · 3 Favor normal
  service_type  text,
  errand_speed  text,
  status        text,
  aceite_em     timestamptz,
  vendor_name   text,
  customer_name text,
  em_curso      boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH meus AS (
    SELECT * FROM public._fila_pedidos_ativos(p_driver_uid)
  ), ancora AS (
    -- O em curso guardado; sem ele (ou já não ativo), a regra de recurso.
    SELECT m.id, m.restaurant_id, m.service_type
      FROM meus m
     WHERE m.id = COALESCE(
             (SELECT e.order_id FROM public.estafeta_pedido_em_curso e
               WHERE e.driver_uid = p_driver_uid
                 AND e.order_id IN (SELECT id FROM meus)),
             public._fila_proximo_em_curso(p_driver_uid, NULL))
  ), cls AS (
    SELECT m.*,
           (m.id = a.id) AS e_ancora,
           CASE
             WHEN m.id = a.id THEN 'ativo'
             -- já está na mochila: nunca se esconde
             WHEN m.recolhido THEN 'ativo'
             -- mesma loja = mesma volta (o agrupamento que já existia)
             WHEN m.service_type <> 'errand' AND a.service_type <> 'errand'
                  AND m.restaurant_id IS NOT NULL
                  AND m.restaurant_id = a.restaurant_id THEN 'ativo'
             ELSE 'em_espera'
           END AS estado
      FROM meus m CROSS JOIN ancora a
  )
  SELECT c.id,
         (row_number() OVER (ORDER BY (c.estado = 'ativo') DESC, c.e_ancora DESC,
                                      CASE WHEN c.estado = 'ativo' THEN 0 ELSE c.classe END,
                                      c.aceite, c.id))::int,
         c.estado, c.classe, c.service_type, c.errand_speed, c.status, c.aceite,
         c.vendor_name, c.customer_name, c.e_ancora
    FROM cls c
   ORDER BY 2;
$$;
REVOKE ALL ON FUNCTION public.fila_do_estafeta(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.estafeta_minha_fila()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(f) ORDER BY f.posicao), '[]'::jsonb)
    FROM public.fila_do_estafeta(auth.uid()) f
   WHERE auth.uid() IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.estafeta_minha_fila() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_minha_fila() TO authenticated;

-- Painel: a fila de cada estafeta com pedidos ativos, e o rascunho de cada um.
CREATE OR REPLACE FUNCTION public.admin_filas_estafetas()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  WITH estafetas AS (
    SELECT DISTINCT COALESCE(d.user_id, NULLIF(o.assigned_driver_id, '')::uuid) AS uid
      FROM public.orders o
      LEFT JOIN public.drivers d
        ON d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id
     WHERE o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
       AND o.assigned_driver_id ~* '^[0-9a-f-]{36}$'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'estafeta_uid', e.uid,
           'estafeta', (SELECT d.name FROM public.drivers d WHERE d.user_id = e.uid LIMIT 1),
           'fila', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                      'order_id', f.order_id, 'posicao', f.posicao, 'estado', f.estado,
                      'classe', f.classe, 'service_type', f.service_type,
                      'errand_speed', f.errand_speed, 'status', f.status,
                      'aceite_em', f.aceite_em, 'loja', f.vendor_name,
                      'cliente', f.customer_name,
                      'rascunho_marcados', dr.marcados,
                      'rascunho_atualizado', dr.updated_at) ORDER BY f.posicao), '[]'::jsonb)
                      FROM public.fila_do_estafeta(e.uid) f
                      LEFT JOIN public.order_purchase_drafts dr ON dr.order_id = f.order_id)
         )), '[]'::jsonb)
    INTO v_out
    FROM estafetas e
   WHERE e.uid IS NOT NULL;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_filas_estafetas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_filas_estafetas() TO authenticated;

-- O cliente vê se o pedido dele está em espera (só entregas; Favor nunca).
CREATE OR REPLACE FUNCTION public.cliente_fila_do_meu_pedido(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_o   record;
  v_uid uuid;
  v_f   record;
BEGIN
  SELECT id, user_id, assigned_driver_id, service_type, status
    INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR v_o.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('em_espera', false);
  END IF;
  IF v_o.service_type = 'errand' OR v_o.status <> 'driverAccepted' THEN
    RETURN jsonb_build_object('em_espera', false);
  END IF;
  SELECT d.user_id INTO v_uid FROM public.drivers d
   WHERE d.user_id::text = v_o.assigned_driver_id OR d.id::text = v_o.assigned_driver_id
   LIMIT 1;
  IF v_uid IS NULL THEN RETURN jsonb_build_object('em_espera', false); END IF;
  SELECT f.estado, f.posicao INTO v_f
    FROM public.fila_do_estafeta(v_uid) f WHERE f.order_id = p_order_id;
  RETURN jsonb_build_object('em_espera', COALESCE(v_f.estado = 'em_espera', false));
END;
$$;
REVOKE ALL ON FUNCTION public.cliente_fila_do_meu_pedido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cliente_fila_do_meu_pedido(text) TO authenticated;

-- ── 3. Aviso ao cliente quando a entrega dele fica em espera ────────────────
CREATE TABLE IF NOT EXISTS public.fila_avisos_cliente (
  order_id    text PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  driver_uid  uuid,
  posicao     integer,
  avisado_em  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.fila_avisos_cliente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fila_avisos_cliente FROM anon, authenticated;
GRANT ALL ON public.fila_avisos_cliente TO service_role;

CREATE OR REPLACE FUNCTION public.fn_fila_avisar_cliente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid    uuid;
  v_f      record;
  v_rows   integer;
  v_key    text;
  v_url    text;
  v_titulo constant text := 'O seu pedido já tem estafeta';
  v_corpo  constant text := 'O estafeta está noutro pedido perto de si. '
                            'Assim que o terminar, segue para o seu.';
BEGIN
  IF NEW.status IS DISTINCT FROM 'driverAccepted'
     OR OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  -- Favor: o cliente escolheu a janela (até 3 h) — não se avisa.
  IF NEW.service_type = 'errand' OR NEW.user_id IS NULL OR NEW.assigned_driver_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- Um aviso nunca pode travar a aceitação do pedido.
  BEGIN
    SELECT d.user_id INTO v_uid FROM public.drivers d
     WHERE d.user_id::text = NEW.assigned_driver_id OR d.id::text = NEW.assigned_driver_id
     LIMIT 1;
    IF v_uid IS NULL THEN RETURN NEW; END IF;
    SELECT f.estado, f.posicao INTO v_f
      FROM public.fila_do_estafeta(v_uid) f WHERE f.order_id = NEW.id;
    IF v_f.estado IS DISTINCT FROM 'em_espera' THEN RETURN NEW; END IF;

    INSERT INTO public.fila_avisos_cliente (order_id, driver_uid, posicao)
    VALUES (NEW.id, v_uid, v_f.posicao)
    ON CONFLICT (order_id) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN RETURN NEW; END IF;

    PERFORM public._push_in_app_notification(NEW.user_id, 'order_queue', v_titulo, v_corpo, NEW.id);

    IF COALESCE(public.is_demo_user(NEW.user_id), false) THEN RETURN NEW; END IF;
    v_key := nullif(public._service_role_key(), '');
    v_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1);
    IF v_key IS NULL OR v_url IS NULL THEN RETURN NEW; END IF;
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/notify-client',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || v_key),
      body    := jsonb_build_object(
        'clientId', NEW.user_id::text,
        'orderId',  NEW.id::text,
        'type',     'order_status',
        'title',    v_titulo,
        'body',     v_corpo,
        'kind',     'order_queue'));
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'fn_fila_avisar_cliente: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_fila_avisar_cliente() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_fila_avisar_cliente ON public.orders;
CREATE TRIGGER trg_fila_avisar_cliente
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_fila_avisar_cliente();
