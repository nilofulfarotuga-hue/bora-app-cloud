-- Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4).
-- Funções SECURITY DEFINER que escrevem dados sem olhar para quem chama (sem auth.uid()/is_admin())
-- e que qualquer conta com sessão podia chamar pela API. Nenhuma é usada pela app com a sessão do
-- utilizador: os chamadores são o servidor (Edge com chave de serviço, cron como postgres, MCP como
-- postgres) ou outras funções SECURITY DEFINER do dono postgres — por isso fechar não parte nada.
--   agent_propose_action        — só a Edge support-chatbot (adminClient); direto deixava um cliente
--                                 pôr na fila do admin uma "ação" (ex.: ACCOUNT_UPDATE) para outra pessoa.
--   cortex_proposal_sync_upsert,
--   cortex_mark_ordem_criada    — fila de propostas vermelhas do Córtex; um cliente podia forjar propostas.
--   maestro_*                   — ciclo do Maestro/Juiz (MCP execute_sql); um cliente podia marcar itens
--                                 como aprovados ou gravar notas do Juiz.
--   _appointment_cron_expire_pending_payment, assinaturas_avisar_renovacoes — só cron (postgres).
--   _reservas_pro_autosetup     — só o gatilho _trg_reservas_autosetup_fn (definer); direto criava sala
--                                 e mesas na loja de outra pessoa.
--   encomenda_telefone_resumo   — só outras funções definer; direto devolvia nome do cliente, notas e
--                                 itens de qualquer pedido.
-- Fecha-se de PUBLIC, anon e authenticated (os dois caminhos — ver memória
-- revoke-de-public-nao-chega-anon-tem-grant-direto) e fica só service_role (e o dono postgres).
-- ACL antes de todas: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.agent_propose_action(uuid,uuid,text,text,jsonb,text,text)',
    'public.cortex_proposal_sync_upsert(text,text,text,text,text,text,timestamp with time zone)',
    'public.cortex_mark_ordem_criada(text,text)',
    'public.maestro_link_suggestion(uuid,uuid,text,jsonb,text)',
    'public.maestro_mark_preexisting(uuid,jsonb,text)',
    'public.maestro_next_backlog_item(text)',
    'public.maestro_record_juiz_evaluation(uuid,numeric,jsonb,boolean,jsonb)',
    'public.maestro_set_benchmark(uuid,jsonb)',
    'public._appointment_cron_expire_pending_payment()',
    'public.assinaturas_avisar_renovacoes()',
    'public._reservas_pro_autosetup(text)',
    'public.encomenda_telefone_resumo(text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;