-- Missão checkin-escada-premios-2026-11-04, bloco D: o calendário do mês mostra TODOS os prémios com foto.
-- _checkin_estado_marcos passa a devolver, em cada marco, a foto do produto-prémio e a loja, e no topo os
-- tokens de cada dia (para os dias sem prémio novo). Só leitura; não mexe em tokens nem preços.
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public._checkin_estado_marcos(uuid)'::regprocedure);
  v_novo text := v_def;
BEGIN
  IF position('foto_url' in v_def) = 0 THEN
    v_novo := replace(v_novo, '''faltam'', v_falta));',
      '''faltam'', v_falta,' || chr(10) ||
      '      ''foto_url'', (SELECT p.photo_url FROM public.products p WHERE p.id = m ->> ''produto_id''),' || chr(10) ||
      '      ''loja_id'', m ->> ''loja_id'',' || chr(10) ||
      '      ''loja_nome'', (SELECT r.name FROM public.restaurants r WHERE r.id = m ->> ''loja_id'')));');
  END IF;
  IF position('tokens_por_dia' in v_def) = 0 THEN
    v_novo := replace(v_novo, '''marcos'', v_marcos,', '''marcos'', v_marcos,' || chr(10) ||
      '    ''tokens_por_dia'', to_jsonb(v_premios),');
  END IF;
  IF v_novo = v_def THEN
    RETURN; -- já aplicado
  END IF;
  IF position('foto_url' in v_novo) = 0 OR position('tokens_por_dia' in v_novo) = 0 THEN
    RAISE EXCEPTION 'ancora_nao_encontrada em _checkin_estado_marcos';
  END IF;
  EXECUTE v_novo;
END
$patch$;
