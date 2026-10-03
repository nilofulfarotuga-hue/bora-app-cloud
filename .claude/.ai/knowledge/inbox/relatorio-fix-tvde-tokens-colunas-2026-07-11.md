# Fix TVDE — colunas tokens_applied em tvde_rides (2026-07-11)

**Estado:** ✅ RESOLVIDO — produção desbloqueada.
**Autorização:** Danilo, explícita ("vai"). Migration aditiva já commitada no repo.

## Problema
`tvde_finish_ride` (overload de 4 args, `p_tokens_to_apply`) — aplicada em prod a
2026-07-10 (`20260710000000_tvde_tokens_threading_rpcs*`) — faz UPDATE das colunas
`tokens_applied_count` e `tokens_applied_value_cents` em `tvde_rides`. Essas colunas
**não existiam** em prod → erro de coluna inexistente → **QUALQUER** finalização de
corrida TVDE falhava, para todos os utilizadores.

Causa: a migration da fundação (`20260709010000_tvde_tokens_applied_columns.sql`)
existia no repo mas nunca tinha sido aplicada ao banco; os RPCs de threading (do dia
seguinte) foram aplicados por cima, referenciando colunas ausentes.

## Diagnóstico (antes de mexer)
- Colunas ausentes em `tvde_rides` — confirmado por `information_schema.columns` (0 linhas).
- Migration `20260709010000_tvde_tokens_applied_columns` **não** constava em `list_migrations`.
- Overloads presentes: `tvde_finish_ride` de 2, 3 e **4 args** (o de 4 escreve as colunas).

## Ação
Aplicada **exatamente** a migration já commitada (não foi criada nenhuma nova):
`supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
```sql
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS tokens_applied_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tokens_applied_value_cents INTEGER NOT NULL DEFAULT 0;
```
Via Supabase MCP `apply_migration` (name `tvde_tokens_applied_columns`,
projeto `ojykpzwqrtusfeakzrna`) → `{"success":true}`. Operação aditiva, não-destrutiva,
reversível (rollback documentado no próprio ficheiro).

## Verificação
1. **Colunas existem:** `tokens_applied_count` e `tokens_applied_value_cents` — `integer`,
   `NOT NULL`, `DEFAULT 0`. ✅
2. **Teste real de finalização** (conta de teste, transação `BEGIN…ROLLBACK`, sem persistir):
   corrida real `b17d579a-2b09-40d1-84c1-06d8e5e199d9` em `em_andamento`, driver impersonado
   via `request.jwt.claims`, chamada ao RPC de 4 args com `p_tokens_to_apply=2`:
   - **Sem erro** (antes rebentava com coluna inexistente). ✅
   - Resultado: `status=finalizada`, `final_fare_cents=890`, `driver_earn_cents=660`,
     `bora_cut_cents=230`, `tokens_applied_count=2`, `tokens_applied_value_cents=10`
     (2 tokens × 5c = 10c, dentro do teto de 50% = 445c). ✅
3. **ROLLBACK confirmado:** a corrida continua `em_andamento`, colunas a 0 — produção
   intacta, nenhum dado de teste deixado para trás. ✅

## Alterações de código
Nenhuma. A migration já estava commitada no repo; só faltava aplicar ao banco.
Nada para enviar (git push) — sem alterações de ficheiros de código.

## Notas / pendências
- Isto era **só a fundação** (as colunas). O débito real de Bora Tokens numa corrida TVDE
  e o threading do desconto nas RPCs de cobrança continuam como estava (🔴 dinheiro, à parte).
- Atualizar a memória `project_tvde_tokens_half_deployed.md`: o meio-implantado ficou
  **fechado** — colunas aplicadas, finish TVDE já não quebra.
