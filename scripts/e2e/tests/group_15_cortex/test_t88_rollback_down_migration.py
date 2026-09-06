"""T88 â€” rollback/down migration (somente em DB de teste).

A migraÃ§ao tem bloco DOWN documental (sem comandos literais para evitar
hook). Este teste valida que os comandos manuais de reversao, quando
executados por sessao com MCP Supabase, removem tabela e 6 RPCs.
NAO rodado automaticamente.

Para executar manualmente (apenas em DB de teste/staging):
1. Aplicar migration F2 (apply_migration)
2. Verificar cortex_tasks existe
3. Executar manualmente (via sessao separada, com permissao destrutiva):
   alter publication supabase_realtime drop table public.cortex_tasks;
   drop function public.cortex_queue_stats() cascade;
   drop function public.cortex_list_tasks(text,int,int) cascade;
   drop function public.cortex_archive(uuid,text) cascade;
   drop function public.cortex_finish(uuid,boolean,jsonb,text,numeric,text) cascade;
   drop function public.cortex_claim_next(text) cascade;
   drop function public.cortex_enqueue(text,text,text,text,text,uuid,jsonb,int,int,boolean,text) cascade;
   drop table public.cortex_tasks cascade;
4. Verificar que tudo desapareceu.
"""
import pytest

from helpers.cortex_tasks import (
    cleanup_all_tasks,
    skip_if_no_cortex_tasks,
)


def test_t88_rollback_down_migration_manual_skip(admin_client):
    """Skip automatico. Documenta o procedimento manual.

    O rollback verdadeiro quebra a Trava do protege-banco.sh (DROP TABLE
    cortex_tasks e bloqueado em contexto SQL), e so pode ser feito por
    uma sessao MCP Supabase que sabota o hook (nao recomendado) ou pelo
    Danilo fora do agente (psql direto, sem hook).
    """
    skip_if_no_cortex_tasks(admin_client)
    pytest.skip(
        "rollback/down requires manual execution by Danilo via psql/MCP "
        "with explicit destructive permission â€” protege-banco.sh blocks "
        "DROP cortex_tasks by design (FINTABLE since F1.4)",
    )