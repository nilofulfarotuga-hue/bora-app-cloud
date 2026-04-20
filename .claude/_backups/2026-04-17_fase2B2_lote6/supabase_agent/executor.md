---
name: supabase_agent_executor
description: Execution procedure for supabase_agent. Step-by-step protocol for safely running Supabase API operations (SELECT, INSERT, UPDATE). Not to be confused with skills/executor.md (the general action executor).
version: 2.0.0
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
- ✅ Sempre limitar resultados com `.limit()`
- ✅ Sempre usar filtros específicos

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
