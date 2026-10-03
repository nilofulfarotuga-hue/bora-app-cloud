-- motorista-ficha-legal-2026-09-23 · segurança: o Supabase dá EXECUTE por
-- omissão a anon/authenticated/service_role em cada função nova do schema
-- public (default privileges). O "revoke ... from public" da migration
-- anterior não os tirava: has_function_privilege('anon', _mfl_aplicar) = true.
-- Fecha-se nome a nome e volta-se a abrir só o que é para abrir.
revoke execute on function public._mfl_aplicar(uuid, jsonb, uuid) from anon, authenticated;
revoke execute on function public._motorista_docs_estado(uuid) from anon, authenticated;
revoke execute on function public._fiscalizacao_dados(uuid, boolean) from anon, authenticated;
revoke execute on function public._fiscalizacao_viagem(uuid, boolean) from anon, authenticated;
revoke execute on function public._tvde_recibo(uuid) from anon, authenticated;
revoke execute on function public.motorista_docs_alerta_diario() from anon, authenticated;
revoke execute on function public.fn_motorista_doc_expirado_online() from anon, authenticated;
revoke execute on function public.fn_tvde_recibo_email_ao_finalizar() from anon, authenticated;
-- Só utilizadores com sessão (a própria função valida quem é):
revoke execute on function public.admin_guardar_ficha_legal(uuid, jsonb) from anon;
revoke execute on function public.admin_motoristas_documentos() from anon;
revoke execute on function public.motorista_guardar_ficha_legal(jsonb) from anon;
revoke execute on function public.motorista_minha_ficha_legal() from anon;
revoke execute on function public.motorista_ficha_fiscalizacao() from anon;
revoke execute on function public.tvde_recibo_viagem(uuid) from anon;
-- verificar_ficha_publica fica aberta a anon DE PROPÓSITO (página pública).
-- Tabelas novas: nada de escrita directa por PostgREST.
revoke insert, update, delete on public.motorista_ficha_legal from anon, authenticated;
revoke insert, update, delete on public.fiscalizacao_tokens from anon, authenticated;
revoke insert, update, delete on public.motorista_docs_alertas from anon, authenticated;
revoke insert, update, delete on public.tvde_recibos_email from anon, authenticated;
