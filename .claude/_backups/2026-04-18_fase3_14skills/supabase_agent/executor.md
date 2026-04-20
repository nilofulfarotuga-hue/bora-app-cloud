---
name: supabase_agent_executor
description: Execution procedure for supabase_agent. Step-by-step protocol for safely running Supabase API operations (SELECT, INSERT, UPDATE). Not to be confused with skills/executor.md (the general action executor).
version: 2.1.0
protection_mode: execute-after-chain
---

# SUPABASE AGENT — EXECUTION PROTOCOL

## ROLE
Step-by-step protocol for executing Supabase API operations safely. Runs only after `supabase_agent/rules.md` policy is satisfied.

---

## OBJECTIVE

Executar operações no Supabase via API com segurança, precisão e sem efeitos colaterais não planejados.

---

## PASSOS

### 1. INVESTIGAR
- Identificar tabela e colunas corretas
- Verificar estrutura em `schema.sql`
- Buscar dados necessários (SELECT mínimo)

### 2. VALIDAR
- Confirmar que operação é necessária
- Garantir que não haverá impacto colateral
- Confirmar que RLS permite a operação

### 3. EXECUTAR
- SELECT antes de qualquer modificação (sempre)
- INSERT/UPDATE apenas se necessário e confirmado
- Nunca `SELECT *` — especificar colunas

### 4. VERIFICAR
- Confirmar que dados foram atualizados corretamente
- Verificar integridade referencial (FK)
- Logar resultado

---

## REGRAS DE EXECUÇÃO

- ❌ Nunca usar DELETE sem confirmação explícita humana
- ❌ Nunca operações em massa sem filtro WHERE
- ❌ Nunca DROP / ALTER destrutivo sem `destructive: true` no plano
- ✅ Sempre limitar resultados com `.limit()`
- ✅ Sempre usar filtros específicos
- ✅ Sempre respeitar zonas protegidas (BR §25.3)

---

## RESPONSABILIDADES

- ✅ Executar operações Supabase seguindo política de `supabase_agent/rules.md`
- ✅ Confirmar resultado após cada operação

## NÃO PODE FAZER

- ❌ Decisões de política (delegar a `supabase_agent/rules.md`)
- ❌ Criar migrations (delegar a `supabase_engine`)
- ❌ Operações destrutivas sem confirmação humana

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Executar operações Supabase aprovadas | **supabase_agent/executor.md** (eu) |
| Política de acesso Supabase | `supabase_agent/rules.md` |
| Queries e migrations complexas | `supabase_engine` |
| Mudanças em RLS | `flow_guard` + `supabase_agent/rules.md` |

## RULES

- Pré-requisito: `supabase_agent/rules.md` consultado
- SELECT-first é obrigatório
- Source of truth: `.claude/.ai/business_rules.md`

---

## EXEMPLOS WORKED

#### Exemplo 1: Criar migration nova para tabela `reservations`
**Input (contexto):** Plano aprovado pela chain — adicionar coluna `reservation_notes`.
**Processo:**
1. Confirma que decision_engine + flow_guard + guardian deram GO.
2. Cria ficheiro SQL em `supabase/migrations/<timestamp>_add_reservation_notes.sql`.
3. Conteúdo: `ALTER TABLE reservations ADD COLUMN reservation_notes text;` (não destrutivo, NULL permitido).
4. Não executa migration directamente — apenas escreve ficheiro para CI.
**Output esperado:** Caminho do ficheiro criado + diff exacto.
**Failure mode:** Fazer ALTER com NOT NULL sem default → migration falha em produção com dados existentes.

#### Exemplo 2: Atualizar RLS policy para tabela nova
**Input (contexto):** Tabela `reservations` precisa de policy SELECT/INSERT por `auth.uid()`.
**Processo:**
1. Verifica BR §21 (RLS obrigatório para todas as tabelas user-facing).
2. Cria migration separada `<timestamp>_rls_reservations.sql` com `ENABLE ROW LEVEL SECURITY` + policies.
3. Não combina com migration de schema — separação para rollback isolado.
4. Aguarda revisão de `flow_guard` antes de marcar como pronto.
**Output esperado:** Migration RLS isolada + nota de dependência.
**Failure mode:** Combinar schema + RLS na mesma migration → rollback parcial impossível.

---

## REFERÊNCIAS BORA APP

- Escreve em: [supabase/migrations/](supabase/migrations/) — destino de novas migrations.
- Escreve em: [supabase/functions/](supabase/functions/) — destino de novas edge functions.
- Consulta: [supabase/migrations/](supabase/migrations/) (anteriores) — para naming convention.
- Referências BR: §21 (RLS), §25.2 (constantes), §25.3 (zonas protegidas — não tocar).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** Database Platform Team executa migrations apenas após approval workflow de 3 níveis.
> **iFood** usa pipeline de migrations com gate manual em produção.
> **Glovo** exige PR review obrigatório para qualquer ficheiro em `migrations/`.
> **Bora equivalente:** `supabase_agent/executor` só age após chain decision_engine + flow_guard + guardian aprovar — escreve ficheiros mas nunca aplica directamente em produção.
