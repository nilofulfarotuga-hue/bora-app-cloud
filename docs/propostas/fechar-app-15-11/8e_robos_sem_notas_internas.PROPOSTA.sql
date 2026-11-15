-- PROPOSTA (não é migração aplicada nem está em supabase/migrations): a bora-tranca recusou a
-- escrita deste ficheiro em supabase/migrations a 14/11/2026 ~23:20 ("migration que toca
-- tokens/wallet/pagamentos/ledger") por causa de palavras nos comentários. Não se contornou.
-- Quem aplica é a Claude.ai, com o nome 20261115024000_robos_sem_notas_internas.
--
-- Missão fechar-app-15-11, Bloco 8 (parte E da missão conversas-ao-vivo de 12/11).
-- REFEITA a 15/11/2026 04:40 depois da revisão do Juiz e Refinador (achado 8).
--
-- CAUSA-RAIZ de os robôs responderem a clientes com notas internas ("Resumo por Esforço",
-- "Próxima sessão → Firebase push"): o robô do suporte (support-chatbot) e o Amigo Bora
-- (client-assistant) pesquisam TODOS os trechos de support_knowledge_chunks pela função
-- match_knowledge. Medido por SELECT a 14/11/2026:
--   obsidian        471 trechos de 61 ficheiros  — notas de programação (bugs, auditorias, TODOs)
--   knowledge        97 trechos de 51 ficheiros  — o cérebro interno do repo (mapas do servidor,
--                                                  lições, preferências do dono, credenciais-teste.md)
--   business_rules   37 trechos                  — as regras do negócio
-- Entre os internos há um trecho de uma auditoria antiga (auditoria-estafeta-completa.md, secção
-- BUGS CRÍTICOS) com a palavra-passe de uma conta de demonstração escrita (não se copia para
-- aqui; essa palavra-passe tem de ser trocada) e dois trechos com uma chave pública de pagamentos.
--
-- O QUE A PRIMEIRA VERSÃO TINHA MAL (revisão de 15/11): tratava os 37 trechos de business_rules
-- como "para clientes". Não são. O business_rules.md é um documento de quem programa. Lido de
-- novo a 15/11 (37 trechos, por título e por palavras, sem abrir os dois que falam de senha):
--   * 4 trechos falam do markup escondido, 4 de comissão, 1 de lucro, 2 de senha;
--   * há secções só técnicas ("§28 — Wallet com Saldo Negativo (Sessão 3B-NOVA)", "§29.
--     Housekeeping financeiro e DB conventions", "19. STORAGE", "21. RLS", "25. CONFIGURAÇÕES
--     TÉCNICAS", "26. CHECKLIST DE LANÇAMENTO"...);
--   * a secção 1 diz quem é o administrador pelo nome (o atendimento não pode dizer quem é o dono);
--   * há regras DESATUALIZADAS face ao livro (regras-do-danilo, §8): a secção 4 diz que o cliente
--     desconta em tokens até 50 % do valor do pedido (a regra em vigor é metade do valor dos tokens
--     que tem), a secção 12 diz que a reserva se cancela sem custo até 4 horas antes (a regra em
--     vigor são 2 horas) e a secção 8 ainda traz taxas de cancelamento de antes da regra de 29/10.
--
-- O QUE MUDA: match_knowledge passa a devolver só o que está numa LISTA FECHADA. Tudo o que não
-- está na lista fica de fora, incluindo o que vier a ser indexado no futuro:
--   * os tipos escritos de propósito para quem usa a app: manual, faq, ajuda (hoje: 0 trechos);
--   * de business_rules, só duas secções que não têm nada interno nem desatualizado:
--     "20. GDPR E PROTEÇÃO DE DADOS" e "23. CHAT";
--   * do mapa dos ecrãs (mapa-ecras.md), as secções do Cliente, do Driver, do Parceiro e de
--     Entrada, que o robô usa para dizer "onde fica" (a do Cliente foi revista de propósito a
--     11/11). "Ecrãs Admin" e "Ecrãs em Falta" ficam de fora.
-- Medido em produção a 15/11 04:40 com esta regra (só leitura): de 605 trechos, 6 ficam ao alcance
-- dos robôs (2 + 4); as duas contas da prova do fim deste ficheiro dão 0 internos e 0 sensíveis.
--
-- CONSEQUÊNCIA, PARA DECIDIR ANTES DE APLICAR (POR CONFIRMAR com o Danilo ou a Claude.ai): com
-- esta lista os robôs deixam de ter, pela pesquisa, as regras de preços, tokens, cancelamentos e
-- reservas. Hoje têm-nas, mas misturadas com margens e, em três pontos, erradas. O remédio certo
-- não é abrir mais secções deste documento: é escrever uma ajuda para clientes com as regras em
-- vigor (as do livro) e indexá-la com o tipo "ajuda" ou "faq", que esta regra já deixa passar.
-- Para acrescentar uma secção à lista: nova migração, com o texto da secção lido antes.
--
-- Nada é apagado: os trechos internos continuam na tabela e o robô interno continua a vê-los
-- pela outra função (match_cortex_knowledge), que NÃO é tocada.
--
-- A pesquisa passa a ser exata sobre os trechos permitidos (são poucos): com um índice
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
  select coalesce(p_source_type, '') in ('manual', 'faq', 'ajuda')
      or (coalesce(p_source_type, '') = 'business_rules'
          and coalesce(p_section_title, '') in (
            '20. GDPR E PROTEÇÃO DE DADOS', '23. CHAT'))
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

-- Prova dentro da própria migração, feita sobre os dados que lá estiverem no momento de aplicar.
-- Se falhar, nada muda. Duas perguntas que NÃO são verdade por construção:
--   1) passou algum trecho de notas de programação ou do cérebro interno fora do mapa dos ecrãs?
--   2) algum trecho que passa na lista traz, NO TEXTO, margens, comissão, uma senha escrita, uma
--      chave ou o nome do dono? (apanha o caso de uma secção permitida ter sido reescrita ou
--      reindexada com outro conteúdo; "senha" sozinha não conta, para o ecrã "Esqueci a senha")
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
    raise exception 'robos_sem_notas_internas: % trechos permitidos têm texto sensível (margens, comissão, senha, chave ou o nome do dono) — não aplicado', v_sensiveis;
  end if;
  if v_publicos = 0 then
    raise exception 'robos_sem_notas_internas: os robôs ficavam sem conhecimento nenhum — não aplicado';
  end if;
  raise notice 'robos_sem_notas_internas: % trechos ao alcance dos robôs', v_publicos;
end
$$;
