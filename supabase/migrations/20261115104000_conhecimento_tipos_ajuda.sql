-- app-15-11 bloco A1 (15/11/2026): a base dos robôs passa a aceitar os tipos de
-- texto público ('ajuda', 'faq', 'manual') — os mesmos da lista fechada da
-- proposta 8e (docs/propostas/fechar-app-15-11/8e_robos_sem_notas_internas.PROPOSTA.sql).
-- Até aqui só aceitava 'obsidian', 'knowledge' e 'business_rules' (notas internas),
-- por isso a ajuda para clientes nem se podia gravar.
-- Só alarga a regra: nenhuma linha muda nem se apaga.
alter table public.support_knowledge_chunks
  drop constraint if exists support_knowledge_chunks_source_type_check;
alter table public.support_knowledge_chunks
  add constraint support_knowledge_chunks_source_type_check
  check (source_type = any (array['obsidian', 'knowledge', 'business_rules', 'ajuda', 'faq', 'manual']));
