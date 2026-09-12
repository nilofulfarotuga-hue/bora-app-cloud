# B2 commit 2 — Audit Fase A (sync Obsidian)

**Cópia do relatório original:** `.claude/.ai/reports/20260502_megafinal/b2c2_final_total_audit.md`
**Data sync:** 2026-05-05
**Estado:** Fase A concluída, aguardar luz verde Fase B

## TL;DR

- ✅ A0: Estado actual confirmado, sessões 1-6 intactas, drift=0
- ⚠️ A1: **DIVERGÊNCIA CRÍTICA** baseline — `agent_get_user_orders_summary` referencia `final_total_numeric` directamente. Sem fix, RPC quebra após RENAME.
- ✅ A2: Flutter safe (28 hits, 9 ficheiros, padrão `(num?)?.toDouble()` universal — zero refs `final_total_numeric`)
- ✅ A3: Plano dry-run ajustado (CREATE OR REPLACE da RPC dentro da transacção)
- ✅ A4: Backup capturado em `.claude/.ai/backups/b2c2_pre_migration_20260505.sql`
- ✅ A5: Análise impacto + rollback documentados

## Pergunta para Danilo

A baseline Claude.ai 2026-05-05 estava errada quanto a casts. Há **1 RPC** (`agent_get_user_orders_summary`) que precisa de `CREATE OR REPLACE` na mesma transacção do RENAME.

Plano ajustado: aprovar B1+B2 incluindo o fix da RPC?

## Próximos passos

1. Luz verde do Danilo via Claude.ai validação
2. Executar B1 (dry-run BEGIN/ROLLBACK)
3. Executar B2 (apply_migration ≤60s após B1)
4. Smokes S1-S12
5. Update `business_rules.md §29.1`
6. 1 commit atómico
