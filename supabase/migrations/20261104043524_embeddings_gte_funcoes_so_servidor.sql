-- embeddings-supabase-2026-11-03 — parte 4: as funções novas de preenchimento e da prova só para o servidor.
-- Aviso do Supabase (03/11 22:34): "can be executed by the authenticated role as a SECURITY DEFINER".
-- knowledge_chunks_without_gte devolvia o texto do manual interno a qualquer conta com sessão.
-- Quem as usa é a função embeddings-gte com a chave do servidor (service_role) — fica só esse.
revoke execute on function public.assistant_products_without_embedding_gte(integer, text, text) from public, anon, authenticated;
revoke execute on function public.assistant_set_embeddings_gte(jsonb) from public, anon, authenticated;
revoke execute on function public.knowledge_chunks_without_gte(integer) from public, anon, authenticated;
revoke execute on function public.knowledge_set_embeddings_gte(jsonb) from public, anon, authenticated;
revoke execute on function public.assistant_products_without_embedding_recent(integer, integer) from public, anon, authenticated;
revoke execute on function public.eval_emb_pool_sem_gemini_20261103(integer) from public, anon, authenticated;
revoke execute on function public.eval_emb_vizinhos_20261103(extensions.vector, integer) from public, anon, authenticated;

grant execute on function public.assistant_products_without_embedding_gte(integer, text, text) to service_role;
grant execute on function public.assistant_set_embeddings_gte(jsonb) to service_role;
grant execute on function public.knowledge_chunks_without_gte(integer) to service_role;
grant execute on function public.knowledge_set_embeddings_gte(jsonb) to service_role;
grant execute on function public.assistant_products_without_embedding_recent(integer, integer) to service_role;
grant execute on function public.eval_emb_pool_sem_gemini_20261103(integer) to service_role;
grant execute on function public.eval_emb_vizinhos_20261103(extensions.vector, integer) to service_role;
