-- 26/11/2026 (arquivo-tvde-total): o Bora Motorista está fechado
-- (platform_settings.tvde_app_visivel = false). Os motoristas com
-- vehicle_type = 'carro_passageiros' trabalham como estafetas de carro
-- normais, por isso a porta de "ficar online" só lhes aplica as regras TVDE
-- (tvde_driver_pode_ficar_online) quando o interruptor estiver aberto.
-- Cópia da função anterior: public.bkp_arquivo_tvde_20261126
-- (tipo 'funcao', ref 'prestador_pode_ficar_online').
-- Não mexe em dinheiro, dispatch nem dados.

CREATE OR REPLACE FUNCTION public.prestador_pode_ficar_online()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  d record;
  v_tvde jsonb;
begin
  if v_uid is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select approval_status, is_banned, deleted_at, vehicle_type into d
    from public.drivers where user_id = v_uid or id = v_uid
   order by (user_id = v_uid) desc, created_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA', 'mensagem', 'Não encontrámos a tua conta de prestador.');
  end if;
  if d.deleted_at is not null then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_APAGADA', 'mensagem', 'Esta conta já não está ativa.');
  end if;
  if coalesce(d.is_banned, false) then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_BLOQUEADA', 'mensagem', 'A tua conta está bloqueada. Fala com o suporte da Bora.');
  end if;
  if coalesce(d.approval_status, '') = 'rejected' then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_RECUSADA', 'mensagem', 'A tua candidatura não foi aprovada. Fala com o suporte da Bora.');
  end if;
  if coalesce(d.approval_status, '') <> 'approved' then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_NAO_APROVADA',
      'mensagem', 'A tua conta ainda não está aprovada. Quando for aprovada recebes um aviso e podes ficar online.',
      'faltas', to_jsonb(public._robo_documentos_faltas(v_uid)));
  end if;
  -- 26/11/2026: regras TVDE só com o Bora Motorista aberto.
  if d.vehicle_type = 'carro_passageiros'
     and coalesce((public.get_setting('tvde_app_visivel') #>> '{}')::boolean, false) then
    v_tvde := public.tvde_driver_pode_ficar_online();
    if not coalesce((v_tvde ->> 'ok')::boolean, true) then
      return jsonb_build_object('ok', false, 'codigo', 'TVDE_BLOQUEADO',
        'mensagem', 'Não podes ficar online: ' || coalesce((select string_agg(e ->> 'rotulo', '; ') from jsonb_array_elements(v_tvde -> 'motivos') e), ''),
        'motivos', v_tvde -> 'motivos');
    end if;
  end if;
  return jsonb_build_object('ok', true, 'codigo', 'OK', 'mensagem', null);
end
$function$;
