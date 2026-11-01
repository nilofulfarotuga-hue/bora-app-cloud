-- PROPOSTA — NÃO APLICADA (o classificador recusou a 01/11/2026; ver docs/TRANCAS.md).
-- Missão app-fechar-2026-11-01 · B8 (revisão independente, 01/11/2026).
-- 1) prestador_suspensoes_manutencao: a suspensão TEMPORÁRIA de um estafeta marcava o registo como
--    expirada e avisava "já podes voltar a ficar online", mas deixava drivers.is_banned=true: o
--    prestador_pode_ficar_online e o gatilho trg_online_so_aprovado recusavam para sempre
--    (CONTA_BLOQUEADA). Agora a manutenção também levanta o is_banned do estafeta cuja data passou.
-- 2) admin_suspender_prestador: a guarda "pedido em curso" só procurava orders.assigned_driver_id =
--    drivers.id; muitos pedidos guardam o user_id. Passa a procurar os dois.
-- Só estas duas linhas mudam (resto igual à versão no ar). Não mexe em valores nem em dinheiro.

CREATE OR REPLACE FUNCTION public.admin_suspender_prestador(p_entidade_tabela text, p_entidade_id text, p_tipo text, p_motivo text, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_motivo_codigo text DEFAULT NULL::text, p_factos jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_row jsonb;
  v_user_id uuid;
  v_id bigint;
  v_tipo_conta text;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_tipo NOT IN ('suspensao_temporaria','suspensao','encerramento','restricao') THEN
    RAISE EXCEPTION 'tipo_invalido: %', p_tipo;
  END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 10 THEN
    RAISE EXCEPTION 'SUSPENSAO_SEM_MOTIVO: escreve o motivo (mínimo 10 letras)';
  END IF;
  IF p_tipo = 'suspensao_temporaria' AND (p_ate IS NULL OR p_ate <= now()) THEN
    RAISE EXCEPTION 'suspensao_temporaria_precisa_de_data_futura';
  END IF;
  IF p_entidade_tabela NOT IN ('drivers','cleaners','washers','casa_profissionais','restaurants','service_providers') THEN
    RAISE EXCEPTION 'tabela_invalida: %', p_entidade_tabela;
  END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id::text = $1', p_entidade_tabela)
    INTO v_row USING p_entidade_id;
  IF v_row IS NULL THEN RAISE EXCEPTION 'prestador_nao_encontrado: % %', p_entidade_tabela, p_entidade_id; END IF;

  v_user_id := CASE WHEN p_entidade_tabela = 'restaurants'
                    THEN COALESCE((v_row->>'user_id')::uuid, (v_row->>'user_')::uuid)
                    ELSE (v_row->>'user_id')::uuid END;
  v_tipo_conta := public._prestador_tipo_conta(p_entidade_tabela, v_row);

  IF p_entidade_tabela = 'drivers' AND EXISTS (
       SELECT 1 FROM public.orders o WHERE o.assigned_driver_id IN (p_entidade_id, v_user_id::text)
          AND o.status IN ('preparing','callingDriver','driverAccepted','pickedUp','onTheWay')) THEN
    RAISE EXCEPTION 'prestador_com_pedido_em_curso: espera que termine ou passa o pedido com ops_reassign_order';
  END IF;

  INSERT INTO public.prestador_suspensoes
    (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo,
     factos, origem, decidido_por, decidido_por_email, ate, comunicado_em)
  VALUES
    (v_user_id, v_tipo_conta, p_entidade_tabela, p_entidade_id, p_tipo, 'ativa', trim(p_motivo), p_motivo_codigo,
     COALESCE(p_factos,'{}'::jsonb), 'admin', v_admin.admin_id, v_admin.admin_email, p_ate, now())
  RETURNING id INTO v_id;

  PERFORM set_config('bora.motivo_suspensao', trim(p_motivo), true);
  PERFORM set_config('bora.motivo_codigo', COALESCE(p_motivo_codigo,''), true);
  IF p_tipo <> 'restricao' THEN
    CASE p_entidade_tabela
      WHEN 'drivers' THEN
        IF p_tipo = 'encerramento' THEN
          UPDATE public.drivers SET deleted_at = now(), deleted_by = v_admin.admin_id,
                 deletion_reason = trim(p_motivo), is_online = false WHERE id::text = p_entidade_id;
        ELSE
          UPDATE public.drivers SET is_banned = true, banned_at = now(), banned_by = v_admin.admin_id,
                 banned_until = p_ate,
                 ban_reason_code = CASE WHEN p_motivo_codigo IN ('fraud','misconduct','documents_invalid','inactivity','safety')
                                        THEN p_motivo_codigo::public.ban_reason_code ELSE 'other'::public.ban_reason_code END,
                 ban_reason = trim(p_motivo), is_online = false WHERE id::text = p_entidade_id;
        END IF;
      WHEN 'cleaners' THEN
        UPDATE public.cleaners SET approval_status = 'suspended', rejection_reason = trim(p_motivo),
               is_active = false WHERE id::text = p_entidade_id;
      WHEN 'casa_profissionais' THEN
        UPDATE public.casa_profissionais SET approval_status = CASE WHEN p_tipo='encerramento' THEN 'banned' ELSE 'suspended' END,
               rejection_reason = trim(p_motivo), is_active = false WHERE id::text = p_entidade_id;
      WHEN 'washers' THEN
        UPDATE public.washers SET is_banned = true, ban_reason = trim(p_motivo), banned_at = now(),
               is_active = false WHERE id::text = p_entidade_id;
      WHEN 'restaurants' THEN
        UPDATE public.restaurants SET is_active_admin = false WHERE id::text = p_entidade_id;
      WHEN 'service_providers' THEN
        UPDATE public.service_providers SET is_active_admin = false, is_online = false WHERE id::text = p_entidade_id;
    END CASE;
  END IF;

  BEGIN
    PERFORM public.log_admin_action('prestador_' || p_tipo, p_entidade_tabela, p_entidade_id,
      jsonb_build_object('suspensao_id', v_id, 'motivo', trim(p_motivo), 'codigo', p_motivo_codigo, 'ate', p_ate));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admin_suspender_prestador: audit falhou: %', SQLERRM; END;

  IF v_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(v_user_id, 'conta_suspensa',
        CASE p_tipo WHEN 'encerramento' THEN 'A tua conta foi encerrada'
                    WHEN 'restricao' THEN 'Restrição na tua conta'
                    ELSE 'A tua conta foi suspensa' END,
        'Motivo: ' || trim(p_motivo)
          || CASE WHEN p_ate IS NOT NULL THEN ' Até ' || to_char(p_ate AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '.' ELSE '' END
          || ' Podes pedir revisão na app (A minha conta) ou pelo WhatsApp da Bora. Uma pessoa responde em 7 dias.',
        NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'suspensao_id', v_id, 'tipo', p_tipo, 'ate', p_ate, 'tipo_conta', v_tipo_conta);
END $function$;

CREATE OR REPLACE FUNCTION public.prestador_suspensoes_manutencao()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_exp int := 0; v_av int := 0; r RECORD;
BEGIN
  FOR r IN SELECT * FROM public.prestador_suspensoes
            WHERE estado IN ('ativa','mantida','reduzida') AND tipo = 'suspensao_temporaria'
              AND ate IS NOT NULL AND ate <= now() LOOP
    CASE r.entidade_tabela
      WHEN 'cleaners' THEN UPDATE public.cleaners SET approval_status='approved', rejection_reason=NULL, is_active=true WHERE id::text = r.entidade_id AND approval_status='suspended';
      WHEN 'casa_profissionais' THEN UPDATE public.casa_profissionais SET approval_status='approved', rejection_reason=NULL, is_active=true WHERE id::text = r.entidade_id AND approval_status='suspended';
      WHEN 'washers' THEN UPDATE public.washers SET is_banned=false, ban_reason=NULL, banned_at=NULL, is_active=true WHERE id::text = r.entidade_id;
      WHEN 'restaurants' THEN UPDATE public.restaurants SET is_active_admin=true WHERE id::text = r.entidade_id;
      WHEN 'service_providers' THEN UPDATE public.service_providers SET is_active_admin=true WHERE id::text = r.entidade_id;
      WHEN 'drivers' THEN UPDATE public.drivers SET is_banned=false, banned_at=NULL, banned_by=NULL, banned_until=NULL, ban_reason=NULL, ban_reason_code=NULL WHERE id::text = r.entidade_id AND is_banned AND banned_until IS NOT NULL AND banned_until <= now();
      ELSE NULL;
    END CASE;
    UPDATE public.prestador_suspensoes SET estado='expirada', reativado_em=now(), reativacao_nota='Suspensão temporária terminou na data marcada' WHERE id = r.id;
    v_exp := v_exp + 1;
    IF r.user_id IS NOT NULL THEN
      BEGIN
        PERFORM public._push_in_app_notification(r.user_id, 'conta_reativada', 'A tua suspensão terminou', 'Já podes voltar a ficar online.', NULL);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  FOR r IN SELECT * FROM public.prestador_suspensoes
            WHERE estado = 'em_revisao' AND revisao_prazo IS NOT NULL
              AND revisao_prazo - now() < interval '2 days'
              AND (revisao_aviso_em IS NULL OR revisao_aviso_em < now() - interval '1 day') LOOP
    BEGIN
      PERFORM public._cleaning_notify_admin(
        CASE WHEN r.revisao_prazo < now() THEN 'REVISÃO ATRASADA (lei: resposta por escrito)' ELSE 'Revisão a vencer em menos de 2 dias' END,
        r.tipo_conta || ' (' || left(r.entidade_id, 8) || ') — prazo ' || to_char(r.revisao_prazo AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '. Painel > Revisões.');
    EXCEPTION WHEN OTHERS THEN NULL; END;
    UPDATE public.prestador_suspensoes SET revisao_aviso_em = now() WHERE id = r.id;
    v_av := v_av + 1;
  END LOOP;
  RETURN jsonb_build_object('expiradas', v_exp, 'avisos', v_av);
END $function$;
