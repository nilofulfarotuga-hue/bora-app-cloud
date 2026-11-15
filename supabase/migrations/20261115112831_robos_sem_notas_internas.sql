-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115112831); antes não estava em supabase/migrations.
-- A proposta docs/propostas/fechar-app-15-11/8e_robos_sem_notas_internas.PROPOSTA.sql não é igual a isto; abaixo, o texto exato que correu.

create or replace function public._conhecimento_para_clientes(
  p_source_type text, p_source_file text, p_section_title text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(p_source_type, '') in ('manual', 'faq', 'ajuda')
      or (coalesce(p_source_type, '') = 'business_rules'
          and coalesce(p_section_title, '') in (
            '20. GDPR E PROTEÇÃO DE DADOS', '23. CHAT'))
      or (coalesce(p_source_file, '') ~ '(^|[/\\])mapa-ecras\.md$'
          and coalesce(p_section_title, '') in (
            'Ecrãs do Cliente', 'Ecrãs do Driver', 'Ecrãs do Parceiro', 'Ecrãs de Entrada / Auth'));
$function$;

revoke all on function public._conhecimento_para_clientes(text, text, text) from public, anon, authenticated;

create or replace function public.match_knowledge(
  query_embedding extensions.vector,
  match_count integer default 5,
  min_similarity double precision default 0.5)
 returns table(id uuid, source_file text, source_type text, section_title text, chunk_text text, similarity double precision)
 language sql
 security definer
 set search_path to 'public', 'extensions'
as $function$
  with permitidos as materialized (
    select k.id, k.source_file, k.source_type, k.section_title, k.chunk_text,
           k.embedding, k.embedding_gte
      from public.support_knowledge_chunks k
     where public._conhecimento_para_clientes(k.source_type, k.source_file, k.section_title)
  )
  (select p.id, p.source_file, p.source_type, p.section_title, p.chunk_text,
          1 - (p.embedding_gte <=> query_embedding) as similarity
     from permitidos p
    where extensions.vector_dims(query_embedding) = 384
      and p.embedding_gte is not null
      and 1 - (p.embedding_gte <=> query_embedding) >= min_similarity
    order by p.embedding_gte <=> query_embedding
    limit match_count)
  union all
  (select p.id, p.source_file, p.source_type, p.section_title, p.chunk_text,
          1 - (p.embedding <=> query_embedding) as similarity
     from permitidos p
    where extensions.vector_dims(query_embedding) <> 384
      and p.embedding is not null
      and 1 - (p.embedding <=> query_embedding) >= min_similarity
    order by p.embedding <=> query_embedding
    limit match_count);
$function$;

do $$
declare
  v_internos int;
  v_sensiveis int;
  v_publicos int;
begin
  select count(*) filter (where source_type in ('obsidian', 'knowledge')
                                and source_file !~ '(^|[/\\])mapa-ecras\.md$'),
         count(*) filter (where chunk_text ~* '(markup|ocult|lucro|margem|comiss|danilo|sk_live|service_role)'
                             or chunk_text ~* '(senha|password|palavra-passe)\s*[:=`]'),
         count(*)
    into v_internos, v_sensiveis, v_publicos
    from public.support_knowledge_chunks
   where public._conhecimento_para_clientes(source_type, source_file, section_title);
  if v_internos > 0 then
    raise exception 'robos_sem_notas_internas: % trechos internos ainda ao alcance dos robôs', v_internos;
  end if;
  if v_sensiveis > 0 then
    raise exception 'robos_sem_notas_internas: % trechos permitidos têm texto sensível — não aplicado', v_sensiveis;
  end if;
  if v_publicos = 0 then
    raise exception 'robos_sem_notas_internas: os robôs ficavam sem conhecimento nenhum — não aplicado';
  end if;
  raise notice 'robos_sem_notas_internas: % trechos ao alcance dos robôs', v_publicos;
end
$$;
