-- Missão zerar-2026-11-02, B4: robot_apply_suggestion escondia uma loja sem motivo. Agora o tipo
-- hide_store passa pelo admin_suspender_prestador (motivo de 10 letras escrito por uma pessoa,
-- prestador_suspensoes, painel Revisões). robot_apply_suggestion(uuid) fica (sem DROP) e chama a
-- nova sem motivo: esconder loja por ela recusa com SUSPENSAO_SEM_MOTIVO. Os outros tipos não mudam.
-- Aplicada em produção pelo MCP a 02/11/2026 (schema_migrations 20261102161305); prova em rollback
-- no e2e_log (fluxo zerar-2026-11-02, passo B4-robot-motivo).
create or replace function public.robot_apply_suggestion_motivo(p_suggestion_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_s public.robot_suggestions%rowtype;
  v_type text; v_rows integer := 0; v_result jsonb; v_ids text[];
  v_key text; v_val jsonb; v_admin_email text; v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  perform public._admin_op_guard();
  select email into v_admin_email from auth.users where id = auth.uid();
  select * into v_s from public.robot_suggestions where id = p_suggestion_id for update;
  if not found then raise exception 'sugestao_nao_encontrada'; end if;
  if v_s.status not in ('nova','aprovada') then
    raise exception 'sugestao_nao_esta_aberta: %', v_s.status;
  end if;
  if v_s.nivel >= 3 then
    raise exception 'nivel_3_nao_executavel: usar robot_mark_suggestion_done apos implementar';
  end if;
  if v_s.payload_execucao is null then
    raise exception 'sugestao_sem_payload_execucao';
  end if;
  v_type := v_s.payload_execucao->>'type';
  if v_type = 'update_setting' then
    v_key := v_s.payload_execucao->>'key';
    v_val := v_s.payload_execucao->'value';
    if v_key is null or v_val is null then raise exception 'payload_update_setting_invalido'; end if;
    -- espelha a whitelist editável do admin (M5) + chaves do robô; NUNCA financeiras
    if not (
      v_key like 'robot\_b\_%'
      or v_key like 'dispatch\_%'
      or (v_key like 'reservation\_%'
          and v_key not like '%cents%' and v_key not like '%payout%'
          and v_key not like '%prepayment%' and v_key not like '%bora_service%'
          and v_key not like '%credit%')
    ) then
      raise exception 'setting_fora_da_whitelist_robot: %', v_key;
    end if;
    perform public.admin_update_setting(v_key, v_val);
    v_rows := 1;
  elsif v_type = 'hide_store' then
    -- 02/11/2026 (zerar B4): esconder uma loja é suspender um parceiro: passa pelo
    -- admin_suspender_prestador (motivo de 10 letras escrito por uma pessoa, registo em
    -- prestador_suspensoes, painel Revisões). Sem motivo recusa com SUSPENSAO_SEM_MOTIVO.
    perform public.admin_suspender_prestador('restaurants', v_s.payload_execucao->>'restaurant_id',
      'suspensao', v_motivo, null, null,
      jsonb_build_object('origem', 'robot_suggestion', 'sugestao_id', p_suggestion_id, 'titulo', v_s.titulo));
    v_rows := 1;
  elsif v_type = 'disable_products' then
    v_ids := array(select jsonb_array_elements_text(coalesce(v_s.payload_execucao->'product_ids','[]'::jsonb)) limit 100);
    update public.products set is_available = false
     where id = any(v_ids) and is_available = true;
    get diagnostics v_rows = row_count;
  elsif v_type = 'flag_products_review' then
    v_ids := array(select jsonb_array_elements_text(coalesce(v_s.payload_execucao->'product_ids','[]'::jsonb)) limit 100);
    update public.products set needs_review = true
     where id = any(v_ids) and coalesce(needs_review,false) = false;
    get diagnostics v_rows = row_count;
  else
    raise exception 'payload_type_fora_da_whitelist: %', coalesce(v_type,'(null)');
  end if;
  v_result := jsonb_build_object('type', v_type, 'rows_affected', v_rows);
  if v_motivo is not null then v_result := v_result || jsonb_build_object('motivo', v_motivo); end if;
  update public.robot_suggestions
     set status = 'aplicada', reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_suggestion_id;
  insert into public.robot_audit_log (suggestion_id, run_id, operation, params, result, executed_by)
  values (p_suggestion_id, v_s.ciclo, 'apply_suggestion:' || v_type,
          v_s.payload_execucao, v_result, coalesce(v_admin_email, auth.uid()::text));
  perform public.log_admin_action('robot_apply_suggestion', 'robot_suggestion',
          p_suggestion_id, v_result);
  return v_result;
end
$function$;

create or replace function public.robot_apply_suggestion(p_suggestion_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  -- 02/11/2026 (zerar B4): sem motivo. Esconder loja (hide_store) recusa aqui;
  -- o painel usa robot_apply_suggestion_motivo.
  return public.robot_apply_suggestion_motivo(p_suggestion_id, null);
end
$function$;

grant execute on function public.robot_apply_suggestion_motivo(uuid, text) to authenticated;
