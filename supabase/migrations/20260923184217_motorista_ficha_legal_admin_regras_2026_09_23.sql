-- motorista-ficha-legal-2026-09-23 · painel admin nas regras da casa
-- (skill painel-admin-limpo): _admin_op_guard no início, auditoria pela
-- sobrecarga log_admin_action(..., uuid, ...) — a de texto escreve numa
-- tabela que não existe e engole o erro —, demo fora da lista, e uma RPC
-- leve para a app perguntar ANTES de ligar o "online".

create or replace function public.admin_guardar_ficha_legal(p_user uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._admin_op_guard();
  if not exists (select 1 from public.drivers where user_id = p_user) then
    raise exception 'motorista_nao_encontrado';
  end if;
  perform public._mfl_aplicar(p_user, p, auth.uid());
  perform public.log_admin_action('motorista_ficha_legal_editar', 'driver', p_user, p);
  return jsonb_build_object('ok', true, 'documentos', public._motorista_docs_estado(p_user));
end $$;
revoke all on function public.admin_guardar_ficha_legal(uuid, jsonb) from public, anon;
grant execute on function public.admin_guardar_ficha_legal(uuid, jsonb) to authenticated, service_role;

create or replace function public.admin_motoristas_documentos()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._admin_op_guard();
  return coalesce((select jsonb_agg(x order by x->>'pior' desc, x->>'nome') from (
    select jsonb_build_object(
      'user_id', d.user_id, 'nome', coalesce(nullif(trim(d.legal_name), ''), d.name),
      'telefone', d.phone, 'email', d.email, 'aprovacao', d.approval_status, 'online', d.is_online,
      'matricula', d.license_plate, 'marca_modelo', d.vehicle_make_model, 'cor', d.vehicle_color,
      'ficha', to_jsonb(f), 'documentos', docs,
      'pior', case
        when docs @> '[{"estado":"expirado"}]' then '3_expirado'
        when docs @> '[{"estado":"a_expirar"}]' then '2_a_expirar'
        when docs @> '[{"estado":"em_falta"}]' then '1_em_falta'
        else '0_valido' end) x
      from public.drivers d
      left join public.motorista_ficha_legal f on f.user_id = d.user_id
      cross join lateral (select public._motorista_docs_estado(d.user_id) docs) s
     where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null
       and (public.admin_demo_visible() or not coalesce(public.is_demo_user(d.user_id), false))) q), '[]'::jsonb);
end $$;
revoke all on function public.admin_motoristas_documentos() from public, anon;
grant execute on function public.admin_motoristas_documentos() to authenticated, service_role;

-- A app pergunta antes de ligar; o gatilho em drivers continua a ser o travão.
create or replace function public.motorista_pode_ficar_online()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_tipo text; v_exp jsonb;
begin
  if v_uid is null then return jsonb_build_object('ok', true); end if;
  select vehicle_type into v_tipo from public.drivers where user_id = v_uid and deleted_at is null limit 1;
  if v_tipo is distinct from 'carro_passageiros'
     or not coalesce((public.get_setting('motorista_bloqueio_doc_expirado') #>> '{}')::boolean, true) then
    return jsonb_build_object('ok', true);
  end if;
  select coalesce(jsonb_agg(e->>'rotulo'), '[]'::jsonb) into v_exp
    from jsonb_array_elements(public._motorista_docs_estado(v_uid)) e where e->>'estado' = 'expirado';
  return jsonb_build_object('ok', jsonb_array_length(v_exp) = 0, 'expirados', v_exp);
end $$;
revoke all on function public.motorista_pode_ficar_online() from public, anon;
grant execute on function public.motorista_pode_ficar_online() to authenticated, service_role;
