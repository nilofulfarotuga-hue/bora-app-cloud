-- ============================================================================
-- Missão pendencias-2026-11-09 — Bloco C3 (robô do talão: EXTRA mais caro vira linha PENDENTE)
--
-- Porquê: no talão do Burger King de 08/11 (a244493e) o "EXTRA BACON 2 FATIAS" custou 2,50 € ao
-- balcão e na app a opção "EXTRA Bacon" vale 0,91 €. O robô (catalog_price_update_from_receipt)
-- já dava o aviso "catalogo_extra_mais_caro" em admin_notifications, mas não deixava nada no ecrã
-- de correções de preço do painel (catalog_price_updates). Agora deixa UMA linha "pending" por
-- talão e por opção (product_option_items), além do aviso. NUNCA aplica o preço do extra sozinho.
--
-- O que muda (mudança mínima, por âncora, idempotente — pode correr duas vezes):
--   1. catalog_price_updates.option_item_id (text, nulo = linha de produto como até hoje).
--   2. Cópia das definições antes do remendo em bkp_fn_robo_extras_20261109 (para reverter).
--   3. catalog_price_update_from_receipt: dentro do bloco que já detetava extras mais caros,
--      casa cada linha EXTRA paga do talão com o extra escolhido na app (nome parecido, >= 0,4),
--      e grava a linha pendente (old_base = price_add da opção, new_base = preço ao balcão).
--      A resposta ganha 'extras_pendentes'. Produtos normais: tudo igual.
--   4. admin_approve_catalog_price_update: uma linha de EXTRA não se aprova por aqui (senão o preço
--      do MENU passava a ser o do extra). Devolve ok=false 'extra_corrige_se_nas_opcoes'; o extra
--      corrige-se nas opções do produto (painel) com o teto Glovo. Rejeitar continua a funcionar.
--
-- Âncoras escolhidas para NÃO colidir com o remendo da missão volta-deposito-kfc-2026-11-09
-- (20261109220000_volta_catalogo_e_talao.sql, âncoras v_segunda / v_new_base <= 0 / saco /
-- 'sem_match'...): as duas migrações aplicam-se em qualquer ordem.
--
-- Reverter: CREATE OR REPLACE com a definição guardada em bkp_fn_robo_extras_20261109
--   (SELECT definicao FROM public.bkp_fn_robo_extras_20261109 WHERE nome = '...';  → EXECUTE).
--   A coluna option_item_id pode ficar (nula não muda nada).
--
-- Prova (produção, DO ... RAISE EXCEPTION, nada gravado): ver
--   .claude/.ai/missoes/pendencias-2026-11-09/C3-prova.md
-- ============================================================================

DO $mig$
DECLARE
  v_def  text;
  v_new  text;
  v_anc  text[];
  v_rep  text[];
  v_n    int;
  i      int;
BEGIN
  -- 1) coluna nova (nula = linha de produto, como até hoje) --------------------------------------
  ALTER TABLE public.catalog_price_updates ADD COLUMN IF NOT EXISTS option_item_id text;
  COMMENT ON COLUMN public.catalog_price_updates.option_item_id IS
    '09/11/2026: id da opção (product_option_items) quando a linha é um EXTRA do talão mais caro do que na app. Nulo = produto.';

  -- 2) cópia das definições antes do remendo (só a primeira vez) ---------------------------------
  CREATE TABLE IF NOT EXISTS public.bkp_fn_robo_extras_20261109 (
    nome        text PRIMARY KEY,
    definicao   text NOT NULL,
    guardado_em timestamptz NOT NULL DEFAULT now()
  );
  ALTER TABLE public.bkp_fn_robo_extras_20261109 ENABLE ROW LEVEL SECURITY;
  INSERT INTO public.bkp_fn_robo_extras_20261109 (nome, definicao)
  SELECT p.proname, pg_get_functiondef(p.oid)
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('catalog_price_update_from_receipt', 'admin_approve_catalog_price_update')
  ON CONFLICT (nome) DO NOTHING;

  -- 3) robô do talão ------------------------------------------------------------------------------
  v_def := pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure);
  IF position('extras_pendentes' IN v_def) = 0 THEN
    v_anc := ARRAY[
$a$  v_extras     jsonb := '[]'::jsonb;$a$,
$a$'extras_app_cents', ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100)::int);$a$,
$a$'extras_mais_caros', v_extras);$a$
    ];
    v_rep := ARRAY[
$b$  v_extras     jsonb := '[]'::jsonb;
  v_extras_pend int := 0;     -- 09/11/2026 (pendencias C3)
  v_xl         jsonb;
  v_xn         text;
  v_oi         record;$b$,
$b$'extras_app_cents', ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100)::int);
      -- 09/11/2026 (pendencias C3): cada EXTRA pago do talão mais caro do que o extra escolhido na
      -- app vira também uma linha PENDENTE em catalog_price_updates (option_item_id = a opção do
      -- menu). Nunca se aplica sozinho: o extra corrige-se nas opções, com o teto Glovo.
      FOR v_xl IN
        SELECT DISTINCT ON (public._talao_norm(l.value->>'name')) l.value
          FROM jsonb_array_elements(v_lines) l
         WHERE (l.value->>'name') IN (SELECT jsonb_array_elements_text(COALESCE(v_m->'grupo', '[]'::jsonb)))
           AND public._talao_e_modificador(l.value->>'name')
           AND COALESCE((l.value->>'unit_price_cents')::int, 0) > 0
         ORDER BY public._talao_norm(l.value->>'name'), (l.value->>'unit_price_cents')::int DESC
      LOOP
        v_xn := btrim(regexp_replace(public._talao_norm(v_xl->>'name'), '^(extra|com|mais|adicional) ', ''));
        SELECT oi.id, oi.name, oi.price_add,
               GREATEST(extensions.similarity(x.n, v_xn), extensions.word_similarity(x.n, v_xn)) AS sim
          INTO v_oi
          FROM (SELECT g.value->>'group' AS grp, gi.value->>'name' AS nome,
                       btrim(regexp_replace(public._talao_norm(gi.value->>'name'), '^(extra|com|mais|adicional) ', '')) AS n
                  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_items->((v_m->>'idx')::int)->'selected_options_priced') = 'array'
                                                 THEN v_items->((v_m->>'idx')::int)->'selected_options_priced'
                                                 ELSE '[]'::jsonb END) g,
                       jsonb_array_elements(CASE WHEN jsonb_typeof(g.value->'items') = 'array'
                                                 THEN g.value->'items' ELSE '[]'::jsonb END) gi
                 WHERE public._talao_e_modificador(gi.value->>'name')) x
          JOIN product_option_groups og ON og.product_id = v_prod.id AND og.name = x.grp
          JOIN product_option_items oi ON oi.group_id = og.id AND oi.name = x.nome
         ORDER BY 4 DESC, oi.price_add DESC
         LIMIT 1;
        CONTINUE WHEN v_oi.id IS NULL OR v_oi.sim < 0.4;
        CONTINUE WHEN (v_xl->>'unit_price_cents')::int <= ROUND(v_oi.price_add * 100) + 1;
        CONTINUE WHEN EXISTS (SELECT 1 FROM catalog_price_updates c
                               WHERE c.receipt_id = p_receipt_id AND c.option_item_id = v_oi.id);
        INSERT INTO catalog_price_updates
          (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao,
           status, option_item_id)
        VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
                ROUND(v_oi.price_add::numeric, 2), ROUND((v_xl->>'unit_price_cents')::numeric / 100.0, 2),
                ROUND(v_oi.sim::numeric, 3),
                'EXTRA: ' || (v_xl->>'name') || ' (na app: ' || v_oi.name || ')', 'pending', v_oi.id);
        v_extras_pend := v_extras_pend + 1;
      END LOOP;$b$,
$b$'extras_mais_caros', v_extras, 'extras_pendentes', v_extras_pend);$b$
    ];
    v_new := v_def;
    FOR i IN 1 .. array_length(v_anc, 1) LOOP
      v_n := (length(v_new) - length(replace(v_new, v_anc[i], ''))) / length(v_anc[i]);
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'C3_ANCORA % de catalog_price_update_from_receipt aparece % vezes (esperado 1)', i, v_n;
      END IF;
      v_new := replace(v_new, v_anc[i], v_rep[i]);
    END LOOP;
    EXECUTE v_new;
  END IF;

  -- 4) aprovar no painel: linha de EXTRA não mexe no preço do produto ----------------------------
  v_def := pg_get_functiondef('public.admin_approve_catalog_price_update(uuid)'::regprocedure);
  IF position('extra_corrige_se_nas_opcoes' IN v_def) = 0 THEN
    v_anc := ARRAY[$a$UPDATE products SET price = v_u.new_base WHERE id = v_u.product_id;$a$];
    v_rep := ARRAY[$b$-- 09/11/2026 (pendencias C3): linha de EXTRA (opção do menu) nunca mexe no preço do produto.
  IF v_u.option_item_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'extra_corrige_se_nas_opcoes',
      'option_item_id', v_u.option_item_id, 'preco_balcao', v_u.new_base);
  END IF;
  UPDATE products SET price = v_u.new_base WHERE id = v_u.product_id;$b$];
    v_n := (length(v_def) - length(replace(v_def, v_anc[1], ''))) / length(v_anc[1]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'C3_ANCORA 1 de admin_approve_catalog_price_update aparece % vezes (esperado 1)', v_n;
    END IF;
    EXECUTE replace(v_def, v_anc[1], v_rep[1]);
  END IF;
END $mig$;

NOTIFY pgrst, 'reload schema';
