-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) — version 20260921064931 · contas_claras_b9_fecho_grita_linha_travada_2026_09_21.
-- Espelho exacto de supabase_migrations.schema_migrations, puxado por REST a 21/09/2026 (Claude Code, missão contas-claras-20260921).
-- CONTAS CLARAS B9 (21/09/2026) — O FECHO DEIXA DE FALHAR EM SILENCIO.
--
-- A CICATRIZ: na noite de 20 para 21/09 o fecho correu, percorreu os tres
-- motoristas, e a linha do Danilo NAO foi reescrita porque estava 'paid' desde
-- as 23:52:06 de 19/09 (um clique de teste, sem pagamento nenhum por tras). A
-- trava 'ON CONFLICT ... WHERE status NOT IN (paid, received)' fez o que devia
-- — nao se reescreve uma semana ja paga — mas nao disse nada a ninguem. O
-- recibo saiu na mesma, com 6,52 EUR em vez de 43,52 EUR, e as 16 corridas
-- desapareceram sem deixar rasto. So se descobriu porque o Danilo leu o email
-- e reparou que faltavam as corridas.
--
-- REGRA QUE FICA: quando o fecho nao consegue reescrever uma linha E o valor
-- recalculado e diferente do que la esta, isso fica escrito no
-- admin_audit_log e vai um aviso ao Danilo com nome, valor velho e valor novo.
-- Nunca corrige sozinho — a linha paga continua intocada, como deve ser. So
-- aponta, para a diferenca nunca mais ficar escondida.

CREATE OR REPLACE FUNCTION public.close_previous_week_settlements()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';  -- domingo passado
  v_drv RECORD;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_calc JSONB;
  v_novo NUMERIC;
  v_velho NUMERIC;
  v_status TEXT;
  v_nome TEXT;
  v_travadas JSONB := '[]'::JSONB;
  v_texto TEXT;
BEGIN
  SELECT b.week_start, b.week_end INTO v_ws, v_we
  FROM public.driver_settlement_week_bounds(v_anchor) b;

  -- CONTAS CLARAS 2026-09-20: o fecho so percorria quem fez ENTREGAS, por isso
  -- quem trabalhou apenas em TVDE ficava de fora do acerto e nunca era pago.
  -- Passa a percorrer as duas origens.
  FOR v_drv IN
    SELECT DISTINCT id FROM (
      SELECT o.assigned_driver_id::uuid AS id
      FROM public.orders o, public.driver_settlement_week_bounds(v_anchor) b
      WHERE o.status = 'delivered'
        AND o.delivered_at >= b.week_start
        AND o.delivered_at <= b.week_end
        AND o.assigned_driver_id ~ '^[0-9a-f]{8}-'
      UNION
      SELECT r.driver_id AS id
      FROM public.tvde_rides r, public.driver_settlement_week_bounds(v_anchor) b
      WHERE r.status = 'finalizada'
        AND r.driver_id IS NOT NULL
        AND r.created_at >= b.week_start
        AND r.created_at <= b.week_end
    ) todos
  LOOP
    -- 1) a verdade, sem gravar nada
    v_calc := public.compute_driver_settlement(v_drv.id, v_anchor, false);
    v_novo := (v_calc ->> 'net_balance')::NUMERIC;

    -- 2) o que la esta, e se a trava vai impedir a reescrita
    SELECT s.status, s.net_balance INTO v_status, v_velho
    FROM public.driver_weekly_settlements s
    WHERE s.driver_id = v_drv.id AND s.week_start_at = v_ws;

    IF v_status IN ('paid','received')
       AND round(COALESCE(v_velho,0) * 100) <> round(COALESCE(v_novo,0) * 100) THEN
      SELECT COALESCE(u.name, v_drv.id::text) INTO v_nome
      FROM public.users u WHERE u.id = v_drv.id;

      v_travadas := v_travadas || jsonb_build_object(
        'driver_id', v_drv.id, 'nome', COALESCE(v_nome, v_drv.id::text),
        'estado', v_status, 'valor_na_linha', v_velho, 'valor_recalculado', v_novo,
        'diferenca', round(v_novo - COALESCE(v_velho,0), 2));

      INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
      VALUES ('fecho_linha_travada_valor_diferente', 'driver', v_drv.id::text,
              jsonb_build_object(
                'week_start', v_ws, 'week_end', v_we,
                'nome', COALESCE(v_nome, v_drv.id::text),
                'estado_da_linha', v_status,
                'valor_na_linha', v_velho,
                'valor_recalculado', v_novo,
                'diferenca', round(v_novo - COALESCE(v_velho,0), 2),
                'nota', 'A linha nao foi reescrita por estar paga. O recibo desta semana '
                     || 'leva o valor antigo. Verificar se o pagamento foi mesmo feito; '
                     || 'se nao foi, reabrir a linha e recalcular.'));
    END IF;

    -- 3) grava (nao faz nada se a linha estiver paga — e assim que deve ser)
    PERFORM public.compute_driver_settlement(v_drv.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;

  -- 4) se alguma ficou travada com valor diferente, avisa. Nunca corrige.
  IF jsonb_array_length(v_travadas) > 0 THEN
    SELECT string_agg('• ' || (x ->> 'nome') || ': na linha ' || (x ->> 'valor_na_linha')
                      || ' EUR, recalculado ' || (x ->> 'valor_recalculado')
                      || ' EUR (' || (x ->> 'estado') || ')', chr(10))
      INTO v_texto
    FROM jsonb_array_elements(v_travadas) x;

    BEGIN
      PERFORM net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')
               || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
          'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'kind', 'generic',
          'title', 'Fecho: ' || jsonb_array_length(v_travadas) || ' linha(s) por rever',
          'body', 'Estas linhas ja estavam pagas e por isso o fecho nao lhes pode tocar, '
                  || 'mas o valor recalculado e outro. O recibo saiu com o valor antigo:'
                  || chr(10) || v_texto,
          'route', '/admin/acertos-semana',
          'ref', 'fecho_travado_' || v_ws::date));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
      VALUES ('fecho_aviso_linha_travada_falhou', 'driver', NULL,
              jsonb_build_object('erro', SQLERRM, 'week_start', v_ws, 'travadas', v_travadas));
    END;
  END IF;

  RETURN v_count;
END;
$function$;
