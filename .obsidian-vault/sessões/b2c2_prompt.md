# B2 commit 2 — Prompt Danilo (sync Obsidian)

**Data:** 2026-05-05
**Cópia do prompt orquestrador para histórico Obsidian.**

═══ MINI-SESSÃO B2 commit 2 — DROP+RENAME final_total ═══

PRÉ-REQUISITO: Sessão 4 (commit 9d3f459) push 2026-05-04.
+24h smoke prod completado. Sessões 5A-1, 5A-2, 5A-2-β, 4C, 6
todas em prod (último commit 49c5291).

⚠️ Opus 4.7 OBRIGATÓRIO. Estimativa 30-45 min.
⚠️ Sessão LEVE — só DB, sem Flutter. PC apertado aguenta.
⚠️ Sem testes em device.
⚠️ Operação de janela: PARTE 2 deve correr ≤60s após PARTE 1 OK.

OBJECTIVO: Concluir migração final_total double precision → numeric:
1. DROP trigger dual-write
2. DROP função sync
3. DROP coluna final_total (double precision)
4. RENAME final_total_numeric → final_total

Plano executado (com ajustes do audit Fase A + do erro intra-transacção em B1):

1. DROP TRIGGER trg_zz_final_total_dual_write
2. DROP FUNCTION fn_sync_final_total_numeric
3. DROP TRIGGER orders_enforce_cash_limit (dependência adicional)
4. DROP COLUMN final_total (double precision)
5. RENAME final_total_numeric → final_total
6. RECREATE TRIGGER orders_enforce_cash_limit (mesma definição)
7. CREATE OR REPLACE agent_get_user_orders_summary (fix referência _numeric)

Resultado: orders.final_total fica numeric, mesmo nome, sem dual-write.

## Aprovação Danilo

Após Fase A (audit), Danilo aprovou explicitamente o fix do agent RPC na mesma transacção. Fase B executou com sucesso.
