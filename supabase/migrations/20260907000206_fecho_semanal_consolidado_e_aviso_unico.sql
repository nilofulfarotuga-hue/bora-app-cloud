-- BLOCO 6.2 + 1.2 — 2026-09-07
-- Antes: quatro tarefas agendadas corriam a mesma hora (00:05 de segunda) sem
-- ordem garantida, e DUAS notificacoes chegavam ao Danilo por cada fecho: uma
-- as 00:05 sem valores e a apontar para um ecra antigo, outra as 00:20 com os
-- valores. Agora ha um so ponto de entrada e um so aviso.
--
-- Esta funcao NAO calcula dinheiro: chama as funcoes compute_* que ja existem
-- (zona protegida, ficam intactas) e junta o resultado.

CREATE OR REPLACE FUNCTION public.run_weekly_closeout()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_drivers   int := 0;
  v_partners  int := 0;
  v_cleaners  int := 0;
  v_providers int := 0;
  v_washers   int := 0;
  v_summary text;
BEGIN
  -- 1) Estafetas e parceiros (ja era feito aqui).
  v_drivers  := public.close_previous_week_settlements();
  v_partners := public.close_partner_week_settlements();

  -- 2) Limpeza, servicos e lavagem — vinham de tarefas agendadas soltas.
  --    Cada uma protegida: uma falhar nao pode deixar as outras por fazer.
  BEGIN v_cleaners := public.compute_all_cleaner_weekly_settlements();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fecho semanal: limpeza falhou: %', SQLERRM;
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('weekly_closeout_parte_falhou','settlement','cleaner',
            jsonb_build_object('erro', SQLERRM));
  END;

  BEGIN v_providers := public.compute_all_provider_weekly_payouts();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fecho semanal: servicos falhou: %', SQLERRM;
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('weekly_closeout_parte_falhou','settlement','provider',
            jsonb_build_object('erro', SQLERRM));
  END;

  BEGIN v_washers := public.compute_all_washer_weekly_settlements();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fecho semanal: lavagem falhou: %', SQLERRM;
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('weekly_closeout_parte_falhou','settlement','washer',
            jsonb_build_object('erro', SQLERRM));
  END;

  v_summary := format(
    'Fecho da semana pronto — %s estafeta(s) · %s parceiro(s) · %s limpeza · %s servicos · %s lavagem. Abrir "Acertos da semana" para rever e pagar.',
    v_drivers, v_partners, v_cleaners, v_providers, v_washers);

  -- Caixa de entrada do painel: passa a apontar para o ecra certo.
  INSERT INTO public.admin_notifications (event_type, severity, entity_type, summary, deep_link, payload)
  VALUES ('weekly_closeout', 'medium', 'settlement', v_summary, '/admin/acertos-semana',
          jsonb_build_object('drivers', v_drivers, 'partners', v_partners,
                             'cleaners', v_cleaners, 'providers', v_providers,
                             'washers', v_washers, 'ran_at', now()));

  -- SEM push aqui (mudanca de 2026-09-07): quem avisa o Danilo e o digest das
  -- 00:20, que ja leva os valores ("A PAGAR / A RECEBER") e a rota certa. Dois
  -- avisos por fecho, um deles sem valores, so ensinavam a ignorar o aviso.

  RETURN jsonb_build_object('drivers', v_drivers, 'partners', v_partners,
                            'cleaners', v_cleaners, 'providers', v_providers,
                            'washers', v_washers);
END;
$function$;;
