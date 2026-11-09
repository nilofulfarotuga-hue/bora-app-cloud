-- NÃO CORREU: a trava recusou-a ("DO com EXECUTE em producao: nao da para ler o que corre").
-- A prova foi feita em PGlite (C3-pglite/, ver C3-prova.md). Fica aqui só como registo.
-- Prova do C3 (pendencias-2026-11-09) — corre em PRODUÇÃO e desfaz-se toda (RAISE no fim).
-- A migração 20261109214000 vai embebida tal e qual (EXECUTE do bloco DO $mig$).
-- A antes (função de hoje) · B antes com o menu a 12,00 (produto normal sobe) · C migração 2x
-- D depois (função nova) + aprovar no painel + segunda corrida · E depois com o menu a 12,00.
DO $prova$
DECLARE
  c_rec   uuid := 'a244493e-5a85-4e20-ae01-ed6e20ebab62';
  c_menu  text := 'bk-078771af-f4cb-451a-b645-3738400175df';
  c_bacon text := 'bk-078771af-f4cb-451a-b645-3738400175df-g4-i7';
  v_out   jsonb := '{}'::jsonb;
  v_r     jsonb;
  v_r2    jsonb;
  v_rows  jsonb;
  v_md5_ini text;
  v_md5     text;
  v_fn1   text;
  v_fn2   text;
  v_ap    jsonb;
  v_id    uuid;
  v_mig   text;
BEGIN
  v_mig := $migsql$
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
$migsql$;

  SELECT md5(string_agg(i.id || ':' || i.price_add::text, ',' ORDER BY i.id)) INTO v_md5_ini
    FROM product_option_items i JOIN product_option_groups g ON g.id = i.group_id
    JOIN products p ON p.id = g.product_id WHERE p.restaurant_id = 'burgerking-guarda';
  v_out := v_out || jsonb_build_object('inicio', jsonb_build_object(
    'preco_menu', (SELECT price FROM products WHERE id = c_menu),
    'bacon', (SELECT price_add FROM product_option_items WHERE id = c_bacon),
    'fn_md5', md5(pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure))));

  -- A) ANTES: função de hoje no talão do BK (desfeito)
  BEGIN
    v_r := public.catalog_price_update_from_receipt(c_rec);
    SELECT jsonb_agg(jsonb_build_object('produto', product_id, 'old', old_base, 'new', new_base,
                                        'status', status, 'linha', linha_talao))
      INTO v_rows FROM catalog_price_updates WHERE receipt_id = c_rec;
    v_out := v_out || jsonb_build_object('A_antes', jsonb_build_object(
      'res', v_r - 'extras_mais_caros', 'n_extras_aviso', jsonb_array_length(v_r->'extras_mais_caros'),
      'linhas', v_rows,
      'linhas_extra', (SELECT count(*) FROM catalog_price_updates WHERE receipt_id = c_rec AND linha_talao LIKE 'EXTRA:%')));
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'desfaz_A';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
  END;

  -- B) ANTES com o menu a 12,00 (o talão fica mais caro → produto normal sobe sozinho) (desfeito)
  BEGIN
    UPDATE products SET price = 12.00 WHERE id = c_menu;
    v_r := public.catalog_price_update_from_receipt(c_rec);
    SELECT jsonb_agg(jsonb_build_object('produto', product_id, 'old', old_base, 'new', new_base, 'status', status))
      INTO v_rows FROM catalog_price_updates WHERE receipt_id = c_rec;
    v_out := v_out || jsonb_build_object('B_antes_menu12', jsonb_build_object(
      'res', v_r - 'extras_mais_caros', 'linhas', v_rows,
      'preco_menu_depois', (SELECT price FROM products WHERE id = c_menu),
      'bacon', (SELECT price_add FROM product_option_items WHERE id = c_bacon)));
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'desfaz_B';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
  END;

  -- C) a migração, duas vezes (idempotente)
  EXECUTE v_mig;
  v_fn1 := md5(pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure))
        || '/' || md5(pg_get_functiondef('public.admin_approve_catalog_price_update(uuid)'::regprocedure));
  EXECUTE v_mig;
  v_fn2 := md5(pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure))
        || '/' || md5(pg_get_functiondef('public.admin_approve_catalog_price_update(uuid)'::regprocedure));
  v_out := v_out || jsonb_build_object('C_migracao', jsonb_build_object(
    'md5_1', v_fn1, 'md5_2', v_fn2, 'idempotente', v_fn1 = v_fn2,
    'coluna', (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public'
                 AND table_name = 'catalog_price_updates' AND column_name = 'option_item_id'),
    'bkp_linhas', (SELECT count(*) FROM public.bkp_fn_robo_extras_20261109),
    'bkp_md5_robo', (SELECT md5(definicao) FROM public.bkp_fn_robo_extras_20261109 WHERE nome = 'catalog_price_update_from_receipt')));

  -- D) DEPOIS: função nova no mesmo talão + aprovar no painel + segunda corrida (desfeito)
  BEGIN
    v_r := public.catalog_price_update_from_receipt(c_rec);
    SELECT jsonb_agg(jsonb_build_object('produto', product_id, 'old', old_base, 'new', new_base, 'status', status,
                                        'linha', linha_talao, 'opcao', option_item_id, 'conf', confianca))
      INTO v_rows FROM catalog_price_updates WHERE receipt_id = c_rec;
    SELECT id INTO v_id FROM catalog_price_updates WHERE receipt_id = c_rec AND option_item_id IS NOT NULL LIMIT 1;
    PERFORM set_config('request.jwt.claims',
      '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated","app_metadata":{"role":"admin"}}', true);
    v_ap := public.admin_approve_catalog_price_update(v_id);
    v_r2 := public.catalog_price_update_from_receipt(c_rec);
    v_out := v_out || jsonb_build_object('D_depois', jsonb_build_object(
      'res', v_r - 'extras_mais_caros', 'n_extras_aviso', jsonb_array_length(v_r->'extras_mais_caros'),
      'linhas', v_rows,
      'linhas_extra', (SELECT count(*) FROM catalog_price_updates WHERE receipt_id = c_rec AND option_item_id IS NOT NULL),
      'aprovar_extra', v_ap,
      'estado_extra_apos_aprovar', (SELECT status FROM catalog_price_updates WHERE id = v_id),
      'segunda_corrida_extras_pendentes', v_r2->'extras_pendentes',
      'linhas_extra_apos_2a', (SELECT count(*) FROM catalog_price_updates WHERE receipt_id = c_rec AND option_item_id IS NOT NULL),
      'preco_menu', (SELECT price FROM products WHERE id = c_menu),
      'bacon', (SELECT price_add FROM product_option_items WHERE id = c_bacon),
      'aviso_extra', (SELECT count(*) FROM admin_notifications WHERE event_type = 'catalogo_extra_mais_caro'
                        AND entity_id = '56fa8623-dd4d-4ae6-86b0-96679f20fbf8')));
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'desfaz_D';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
  END;

  -- E) DEPOIS com o menu a 12,00: produto normal sobe como antes; extra só pendente (desfeito)
  BEGIN
    UPDATE products SET price = 12.00 WHERE id = c_menu;
    v_r := public.catalog_price_update_from_receipt(c_rec);
    SELECT jsonb_agg(jsonb_build_object('produto', product_id, 'old', old_base, 'new', new_base, 'status', status,
                                        'opcao', option_item_id))
      INTO v_rows FROM catalog_price_updates WHERE receipt_id = c_rec;
    v_out := v_out || jsonb_build_object('E_depois_menu12', jsonb_build_object(
      'res', v_r - 'extras_mais_caros', 'linhas', v_rows,
      'preco_menu_depois', (SELECT price FROM products WHERE id = c_menu),
      'bacon', (SELECT price_add FROM product_option_items WHERE id = c_bacon)));
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'desfaz_E';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
  END;

  SELECT md5(string_agg(i.id || ':' || i.price_add::text, ',' ORDER BY i.id)) INTO v_md5
    FROM product_option_items i JOIN product_option_groups g ON g.id = i.group_id
    JOIN products p ON p.id = g.product_id WHERE p.restaurant_id = 'burgerking-guarda';
  v_out := v_out || jsonb_build_object('fim', jsonb_build_object(
    'opcoes_bk_iguais_ao_inicio', v_md5 = v_md5_ini,
    'preco_menu', (SELECT price FROM products WHERE id = c_menu)));

  RAISE EXCEPTION 'RESULT %', v_out::text;
END $prova$;
