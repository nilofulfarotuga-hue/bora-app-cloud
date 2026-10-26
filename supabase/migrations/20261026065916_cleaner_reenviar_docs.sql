-- 26/10/2026 (geral-sabado-24-10, bloco 3): a profissional de limpeza PENDENTE reenvia o
-- documento de identificação e confirma os materiais pela app, sem refazer o cadastro.
-- cleaners.docs só a cleaner_apply escrevia e ela recusa candidaturas pendentes; a tabela não
-- deixa a própria pessoa escrever (provado em rollback pelo agente do bloco 3: 0 linhas).
-- Só a linha da própria pessoa, só enquanto está pendente, só estas chaves; junta ao que já
-- lá está (nunca apaga outros documentos). Fechada a anon.
create or replace function public.cleaner_reenviar_docs(p_novos jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $$
declare
  v_uid  uuid := auth.uid();
  v_docs jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_novos is null or jsonb_typeof(p_novos) <> 'object' or p_novos = '{}'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if exists (select 1 from jsonb_object_keys(p_novos) k
              where k not in ('id_doc', 'materials_ok', 'materials_list')) then
    return jsonb_build_object('ok', false, 'error', 'chave_nao_permitida');
  end if;
  if p_novos ? 'id_doc' and (jsonb_typeof(p_novos->'id_doc') <> 'string'
       or (p_novos->>'id_doc') not like v_uid::text || '/%') then
    -- o caminho tem de ser da pasta da própria pessoa no balde cleaner-documents
    return jsonb_build_object('ok', false, 'error', 'caminho_invalido');
  end if;
  update public.cleaners
     set docs = coalesce(docs, '{}'::jsonb) || p_novos
   where user_id = v_uid and approval_status = 'pending'
  returning docs into v_docs;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;
  return jsonb_build_object('ok', true, 'docs', v_docs);
end;
$$;
revoke all on function public.cleaner_reenviar_docs(jsonb) from public, anon;
grant execute on function public.cleaner_reenviar_docs(jsonb) to authenticated;
