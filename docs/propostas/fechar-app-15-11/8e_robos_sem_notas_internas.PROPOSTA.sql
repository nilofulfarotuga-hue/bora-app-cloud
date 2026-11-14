-- PROPOSTA (não é migração aplicada nem está em supabase/migrations): a bora-tranca recusou a
-- escrita deste ficheiro em supabase/migrations a 14/11/2026 ~23:35 ("migration que toca
-- tokens/wallet/pagamentos/ledger") por causa de palavras nos comentários. Não se contornou.
-- Quem aplica é a Claude.ai, com o nome 20261115024000_robos_sem_notas_internas.
--
-- Missão fechar-app-15-11, Bloco 8 (parte E da missão conversas-ao-vivo de 12/11).
--
-- CAUSA-RAIZ de os robôs responderem a clientes com notas internas ("Resumo por Esforço",
-- "Próxima sessão → Firebase push"): o robô do suporte (support-chatbot) e o Amigo Bora
-- (client-assistant) pesquisam TODOS os trechos de support_knowledge_chunks pela função
-- match_knowledge. Medido por SELECT a 14/11/2026:
--   obsidian        471 trechos de 61 ficheiros  — notas de programação (bugs, auditorias, TODOs)
--   knowledge        97 trechos de 51 ficheiros  — o cérebro interno do repo (mapas do servidor,
--                                                  lições, preferências do dono, credenciais-teste.md)
--   business_rules   37 trechos                  — as regras do negócio
-- Ou seja, 568 de 605 trechos (94 %) eram material interno. Entre eles há um trecho de uma
-- auditoria antiga (auditoria-estafeta-completa.md, secção BUGS CRÍTICOS) com a palavra-passe de
-- uma conta de demonstração escrita (não se copia para aqui; essa palavra-passe tem de ser
-- trocada) e dois trechos com uma chave pública de pagamentos.
--
-- O QUE MUDA: match_knowledge passa a devolver só o que é para clientes, estafetas e parceiros:
--   * as regras do negócio (business_rules) e os tipos de ajuda que vierem a existir
--     (manual, faq, ajuda);
--   * do resto, só o mapa dos ecrãs que o robô usa para dizer "onde fica" (mapa-ecras.md,
--     secções do Cliente, do Driver, do Parceiro e de Entrada) — a secção do Cliente foi revista
--     de propósito a 11/11 para isso. As secções "Ecrãs Admin" e "Ecrãs em Falta" ficam de fora.
-- Nada é apagado: os trechos internos continuam na tabela e o robô interno continua a vê-los
-- pela outra função (match_cortex_knowledge), que NÃO é tocada.
--
-- A pesquisa passa a ser exata sobre os trechos permitidos (são poucas dezenas): com um índice
-- aproximado e um filtro tão apertado, os vizinhos mais próximos podiam ser todos internos e a
-- resposta vinha vazia.
--
-- Prova: supabase/tests/fechar_app_8e_prova.mjs (PGlite com pgvector).

create or replace function public._conhecimento_para_clientes(
  p_source_type text, p_source_file text, p_section_title text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(p_source_type, '') in ('business_rules', 'manual', 'faq', 'ajuda')
      or (coalesce(p_source_file, '') ~ '(^|[/\\])mapa-ecras\.md$'
          and coalesce(p_section_title, '') in (
            'Ecrãs do Cliente', 'Ecrãs do Driver', 'Ecrãs do Parceiro', 'Ecrãs de Entrada / Auth'));
$function$;

revoke all on function public._conhecimento_para_clientes(text, text, text) from public, anon, authenticated;

-- Mesma assinatura, mesmo tipo de resposta e mesmas permissões de sempre (CREATE OR REPLACE
-- não mexe nas permissões). Corpo de produção de 14/11 com o filtro acrescentado.
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

-- Prova dentro da própria migração: se sobrar material interno ao alcance dos robôs, falha e
-- nada muda. (Conta pela regra, não pela pesquisa, para não depender de vetores.)
do $$
declare
  v_internos int;
  v_publicos int;
begin
  select count(*) filter (where public._conhecimento_para_clientes(source_type, source_file, section_title)
                                and source_type in ('obsidian', 'knowledge')
                                and source_file !~ '(^|[/\\])mapa-ecras\.md$'),
         count(*) filter (where public._conhecimento_para_clientes(source_type, source_file, section_title))
    into v_internos, v_publicos
    from public.support_knowledge_chunks;
  if v_internos > 0 then
    raise exception 'robos_sem_notas_internas: % trechos internos ainda ao alcance dos robôs', v_internos;
  end if;
  if v_publicos = 0 then
    raise exception 'robos_sem_notas_internas: os robôs ficavam sem conhecimento nenhum — não aplicado';
  end if;
  raise notice 'robos_sem_notas_internas: % trechos ao alcance dos robôs', v_publicos;
end
$$;
