# DIFF F1.4 — Estender protege-banco.sh ( aplicar à mão)

> **Porquê à mão:** o hook `protege-dinheiro.sh` auto-protege `.claude/hooks/**` — nenhum agente pode editar hooks (Trava por design). O Danilo aplica este diff directamente.

## Ficheiro: `bora_app/.claude/hooks/protege-banco.sh`

### Linha 51 atual:
```bash
FINTABLE='orders|wallets|ledger|ledger_entries|bora_tokens|wallet_transactions|tvde_driver_balances|driver_balances|order_financials|order_financial_transactions|driver_weekly_settlements|partner_weekly_settlements|appointment_payouts|partner_reservation_payouts|pending_charges'
```

### Nova linha 51 (adicionar 6 tabelas Cortex no fim do FINTABLE):
```bash
FINTABLE='orders|wallets|ledger|ledger_entries|bora_tokens|wallet_transactions|tvde_driver_balances|driver_balances|order_financials|order_financial_transactions|driver_weekly_settlements|partner_weekly_settlements|appointment_payouts|partner_reservation_payouts|pending_charges|cortex_tasks|cortex_task_messages|cortex_task_consensus_meta|llm_call_log|agent_events|worktree_registry'
```

## O que isto faz
Estas 6 tabelas nascerão em F2-F7 (`cortex_tasks` F2, `llm_call_log` F3, `cortex_task_messages` F4, `cortex_task_consensus_meta` F5, `worktree_registry` F6, `agent_events` F7). Com isto, o hook recusa:
- `DROP`/`TRUNCATE` sobre elas (regra 5 do hook, em contexto SQL).
- `DISABLE ROW LEVEL SECURITY` sobre elas (regra 6 do hook, em contexto SQL).

## Segurança do diff
- Harmless até as tabelas existirem (a regex só match quando aparece num comando SQL DDL).
- Não toca em ficheiros `$`, nem em MONEYFN/PROTSLUG.
- Mantém o resto do hook intacto.
- Estas tabelas não são financeiras — o nome é "protegidas de destruição", não "dinheiro". O guardião impede que um agente DROPe a fila de tarefas/logs do Cortex.

## Verificação pós-aplicação (pelo Danilo)
1. Abrir `bora_app/.claude/hooks/protege-banco.sh`, confirmar a linha 51 com as 6 tabelas no fim.
2. Teste manual (numa sessão interactiva):
   ```bash
   echo 'DROP TABLE cortex_tasks;' | bash .claude/hooks/protege-banco.sh
   ```
   → deve exit 2 com mensagem "DROP/TRUNCATE de tabela financeira".
3. Observar que `git status` mostra `protege-banco.sh` modificado; commit em `autonomous-night/fase1-hardening`.

## Commit sugerido (pelo Danilo)
```
security(fase1): estende protege-banco.sh às tabelas Cortex (F2-F7)

Adiciona cortex_tasks, cortex_task_messages, cortex_task_consensus_meta,
llm_call_log, agent_events, worktree_registry ao FINTABLE = protegidas
de DROP/TRUNCATE/DISABLE RLS. Harmless até existirem. Ver RED_MODEL.md §6.
```

---

*Aplica este diff à mão. Eu prossigo com o que o agente pode fazer (settings deny, RED_MODEL já criado, pre-flight já criado). Marcarei F1.4 como feito-assim que Tu aplicares.*