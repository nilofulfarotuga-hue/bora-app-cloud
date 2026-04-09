---
name: supabase_engine_queries
description: Query execution procedure for supabase_engine. Protocol for running controlled, efficient Supabase queries via MCP — SELECT, INSERT, UPDATE with proper filters and validation.
version: 2.0.0
---

# SUPABASE ENGINE — QUERY EXECUTION

## ROLE
Step-by-step protocol for executing database queries efficiently and safely via Supabase MCP.

---

## OBJECTIVE

Executar queries no banco de forma controlada, eficiente e sem impacto desnecessário.

---

## PASSOS

### 1. INVESTIGAR
- Identificar tabela correta
- Identificar colunas necessárias (nunca `SELECT *`)
- Ler estrutura mínima antes de modificar

### 2. VALIDAR
- Confirmar query antes de executar
- Estimar impacto (quantas rows afetadas?)
- Verificar se operação é realmente necessária

### 3. EXECUTAR
- Preferir SELECT primeiro
- INSERT/UPDATE só se necessário e confirmado
- Nunca operações em massa sem filtro WHERE

### 4. VERIFICAR
- Confirmar resultado da query
- Verificar integridade dos dados (FK, constraints)
- Logar resultado para rastreabilidade

---

## REGRAS

- ❌ Nunca `SELECT *` — especificar colunas
- ❌ Nunca sem filtro WHERE em tabelas grandes
- ❌ Nunca joins desnecessários
- ✅ Sempre limitar resultados com `.limit(n)`
- ✅ Sempre usar índices quando disponíveis

---

## RESPONSABILIDADES

- ✅ Executar queries individuais controladas
- ✅ Garantir eficiência e integridade

## NÃO PODE FAZER

- ❌ Decidir política de acesso (delegar a `supabase_agent`)
- ❌ Executar migrations (usar procedure separada)
- ❌ Operações destrutivas sem confirmação

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Executar queries controladas | **supabase_engine/queries.md** (eu) |
| Investigar problema de backend | `supabase_engine/debug.md` |
| Política de acesso | `supabase_agent/rules.md` |

## RULES

- SELECT-first obrigatório antes de qualquer modificação
- Filtros WHERE obrigatórios em tabelas grandes
- Source of truth: `.claude/.ai/business_rules.md`
