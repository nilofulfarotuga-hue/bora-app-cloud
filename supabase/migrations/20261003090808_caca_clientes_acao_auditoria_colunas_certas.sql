-- Correcao: admin_audit_log usa entity_type / entity_id_text (nao target_type / target_id).
create or replace function public.admin_caca_acao(p_prospect bigint, p_acao text, p_assunto text default null, p_texto text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.prospects_presenca; v_prop bigint;
begin
  if not public.is_admin() then raise exception 'so_admin'; end if;
  select * into p from public.prospects_presenca where id = p_prospect;
  if p.id is null then raise exception 'prospect_inexistente'; end if;
  select id into v_prop from public.prospect_propostas where prospect_id = p_prospect order by id desc limit 1;
  if p_acao = 'enviar_agora' then
    if not p.email_verificado or coalesce(p.email,'') = '' then raise exception 'sem_email_verificado'; end if;
    if v_prop is null then raise exception 'sem_proposta'; end if;
    update public.prospect_propostas set estado = 'pronta', enviar_agora = true, canal = 'email', destinatario = p.email, atualizado_em = now()
     where id = v_prop and estado in ('rascunho','pronta','pausada','aprovado_danilo');
    update public.prospects_presenca set estado = 'pronta', atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'pausar' then
    update public.prospect_propostas set estado = 'pausada', enviar_agora = false, atualizado_em = now() where id = v_prop and estado in ('pronta','rascunho');
    update public.prospects_presenca set estado = 'pausado', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'retomar' then
    update public.prospect_propostas set estado = 'pronta', atualizado_em = now() where id = v_prop and estado = 'pausada';
    update public.prospects_presenca set estado = 'pronta', atualizado_em = now() where id = p_prospect and estado = 'pausado';
  elsif p_acao = 'recusou' then
    update public.prospect_propostas set estado = 'recusou', enviar_agora = false, atualizado_em = now() where prospect_id = p_prospect and estado <> 'recusou';
    update public.prospects_presenca set estado = 'recusou', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'cliente' then
    update public.prospects_presenca set estado = 'cliente', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'editar' then
    if v_prop is null then raise exception 'sem_proposta'; end if;
    update public.prospect_propostas set assunto = coalesce(p_assunto, assunto), texto = coalesce(p_texto, texto), atualizado_em = now()
     where id = v_prop and estado in ('rascunho','pronta','pausada');
  elsif p_acao = 'apagar' then
    delete from public.prospects_presenca where id = p_prospect;
  else raise exception 'acao_desconhecida';
  end if;
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'caca_clientes_' || p_acao, 'prospect', p_prospect::text, jsonb_build_object('nome', p.nome));
  return jsonb_build_object('ok', true, 'acao', p_acao, 'prospect', p_prospect);
end $$;
