-- =============================================================================
-- ronda-fecho-2026-09-22 · A9 — Robot B: dial de confiança ligado + sugestões
-- de catálogo. Corrido por execute_sql (dados, não schema); fica aqui o texto
-- exato para o repo dizer o que se fez em produção a 23/09.
--
-- 1) platform_settings.robot_b_auto_level1_enabled = true (ordem do Danilo:
--    nível 1 = ações reversíveis — flag_products_review,
--    disable_unpriced_market_products, clean_test_notifications,
--    expire_stale_suggestions), com rasto em admin_audit_log.
-- 2) Um ciclo manual do robô (robot_start_run 'cycle' — robot_runs.mode só aceita
--    cycle/digest/crosstalk; a 1.ª tentativa com um modo próprio foi rejeitada):
--    · sugestão nível 1 "produtos sem foto" (83 disponíveis sem imagem) com
--      payload flag_products_review e execução imediata (robot_auto_execute);
--    · sugestão nível 1 "preços suspeitos" (10 não-parceiros >500 € ou <0,05 €
--      ainda sem needs_review) com execução imediata;
--    · sugestão nível 3 "categorização em massa" (5 689 produtos de mercado
--      disponíveis sem taxonomy_section) — só proposta, para a skill
--      taxonomy-mapper correr com aprovação;
--    · robot_finish_run com as contagens.
-- =============================================================================

UPDATE public.platform_settings
   SET value = 'true'::jsonb, updated_at = now()
 WHERE key = 'robot_b_auto_level1_enabled' AND value <> 'true'::jsonb;

INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
VALUES ('platform_setting_updated', 'platform_setting', 'robot_b_auto_level1_enabled',
        'agente:ronda-fecho-2026-09-22',
        jsonb_build_object('key', 'robot_b_auto_level1_enabled', 'old', false, 'new', true,
                           'motivo', 'ordem do Danilo (ronda-fecho A9): nível 1 = ações reversíveis'));

DO $$
DECLARE
  v_run uuid;
  v_ids_foto jsonb; v_ids_preco jsonb; v_n_foto int; v_n_preco int; v_n_cat int;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_r1 jsonb; v_r1b jsonb; v_r2 jsonb; v_exec int := 0; v_sug int := 0;
  v_por_loja jsonb;
BEGIN
  v_run := public.robot_start_run('cycle', false);

  SELECT jsonb_agg(p.id ORDER BY p.id), count(*) INTO v_ids_foto, v_n_foto
    FROM public.products p WHERE p.is_available AND (p.photo_url IS NULL OR p.photo_url = '');
  SELECT jsonb_object_agg(r.name, x.c) INTO v_por_loja
    FROM (SELECT p.restaurant_id, count(*) c FROM public.products p
           WHERE p.is_available AND (p.photo_url IS NULL OR p.photo_url = '') GROUP BY 1) x
    JOIN public.restaurants r ON r.id = x.restaurant_id;
  SELECT jsonb_agg(p.id), count(*) INTO v_ids_preco, v_n_preco
    FROM public.products p JOIN public.restaurants r ON r.id = p.restaurant_id
   WHERE NOT COALESCE(r.is_partner, false) AND p.is_available AND COALESCE(p.needs_review, false) = false
     AND (p.price > 500 OR (p.price > 0 AND p.price < 0.05));
  SELECT count(*) INTO v_n_cat
    FROM public.products p JOIN public.restaurants r ON r.id = p.restaurant_id
   WHERE p.is_available AND NOT COALESCE(r.is_partner, false)
     AND (p.taxonomy_section IS NULL OR p.taxonomy_section = '');

  v_s1 := public.robot_create_suggestion(v_run, 1::smallint, 3::smallint, 'catalogo',
    format('%s produtos disponíveis sem foto → marcar para revisão', v_n_foto),
    jsonb_build_object('total', v_n_foto, 'por_loja', v_por_loja, 'product_ids', v_ids_foto),
    'Marcar needs_review=true nos produtos disponíveis sem photo_url (reversível) e correr sync-market-photos (loja dadora) para os de mercado; os de parceiro (Mr Kebab, KFC, Sabores de Casa, Wells) precisam de foto real do parceiro. Risco nulo: só sinaliza.',
    jsonb_build_object('type', 'flag_products_review', 'product_ids', v_ids_foto),
    'Glovo/Uber Eats: produto sem foto não vai à montra e vende 30-40% menos.',
    'catalogo:produtos-sem-foto');
  IF v_s1 IS NOT NULL THEN v_sug := v_sug + 1; END IF;

  v_s2 := public.robot_create_suggestion(v_run, 1::smallint, 4::smallint, 'catalogo',
    format('%s preços suspeitos em mercados (>500 € ou <0,05 €) → marcar para revisão', v_n_preco),
    jsonb_build_object('total', v_n_preco, 'product_ids', v_ids_preco),
    'Marcar needs_review=true (reversível). Confirmar depois no site oficial: Continente tem whiskies/vinhos >1 000 € reais; Mercadona tem guardanapos/toalhitas a 0,01 € que são erro de importação.',
    jsonb_build_object('type', 'flag_products_review', 'product_ids', v_ids_preco),
    'Glovo/Uber Eats bloqueiam preço fora do intervalo da categoria antes de publicar.',
    'catalogo:preco-suspeito');
  IF v_s2 IS NOT NULL THEN v_sug := v_sug + 1; END IF;

  v_s3 := public.robot_create_suggestion(v_run, 3::smallint, 3::smallint, 'catalogo',
    format('Categorização em massa: %s produtos de mercado disponíveis sem secção', v_n_cat),
    jsonb_build_object('total_sem_taxonomy_section', v_n_cat),
    'Correr a skill taxonomy-mapper (18 secções canónicas) em dry-run por loja, aprovar e aplicar; conf <0,85 fica com needs_review. Só proposta (nível 3): mexe em 5 689 linhas.',
    NULL,
    'Glovo/Uber Eats: todo o produto tem secção; sem secção não aparece na navegação por categorias.',
    'catalogo:produtos-sem-categoria');
  IF v_s3 IS NOT NULL THEN v_sug := v_sug + 1; END IF;

  -- execução nível 1 (whitelist; máx 50 ids por chamada; máx 10 por ciclo)
  v_r1 := public.robot_auto_execute(v_run, 'flag_products_review',
            jsonb_build_object('product_ids', (SELECT jsonb_agg(x) FROM (SELECT jsonb_array_elements(v_ids_foto) x LIMIT 50) s)));
  v_exec := v_exec + 1;
  IF v_n_foto > 50 THEN
    v_r1b := public.robot_auto_execute(v_run, 'flag_products_review',
            jsonb_build_object('product_ids', (SELECT jsonb_agg(x) FROM (SELECT jsonb_array_elements(v_ids_foto) x OFFSET 50 LIMIT 50) s)));
    v_exec := v_exec + 1;
  END IF;
  v_r2 := public.robot_auto_execute(v_run, 'flag_products_review',
            jsonb_build_object('product_ids', v_ids_preco));
  v_exec := v_exec + 1;

  -- NOTA: robot_create_suggestion devolve NULL quando faz dedup de uma sugestão
  -- viva (actualiza a existente); por isso o fecho é feito por dedup_key, abaixo.
  UPDATE public.robot_suggestions SET status = 'aplicada', reviewed_at = now()
   WHERE id IN (v_s1, v_s2) AND status IN ('nova', 'aprovada');

  PERFORM public.robot_finish_run(v_run, 'ok',
    jsonb_build_object('origem', 'ronda-fecho-2026-09-22 A9', 'sem_foto', v_n_foto, 'preco_suspeito', v_n_preco,
                       'sem_categoria', v_n_cat, 'exec', jsonb_build_array(v_r1, v_r1b, v_r2)),
    v_exec, v_sug);
END $$;

-- 3) Fecho das duas sugestões de nível 1 (por dedup_key — ver nota acima) + rasto.
UPDATE public.robot_suggestions
   SET status = 'aplicada', reviewed_at = now()
 WHERE dedup_key IN ('catalogo:preco-suspeito', 'catalogo:produtos-sem-foto')
   AND status = 'nova';
INSERT INTO public.robot_audit_log (run_id, operation, params, result, executed_by)
SELECT r.id, 'fechar_sugestoes_catalogo',
       jsonb_build_object('dedup_keys', jsonb_build_array('catalogo:preco-suspeito','catalogo:produtos-sem-foto'),
                          'motivo', 'ronda-fecho-2026-09-22 A9: needs_review aplicado a 83 sem foto (6 novos) e 10 precos suspeitos; categorizacao em massa fica como proposta nivel 3'),
       jsonb_build_object('status', 'aplicada'), 'ronda-fecho-2026-09-22'
  FROM public.robot_runs r WHERE r.observations->>'origem' = 'ronda-fecho-2026-09-22 A9' ORDER BY r.started_at DESC LIMIT 1;
