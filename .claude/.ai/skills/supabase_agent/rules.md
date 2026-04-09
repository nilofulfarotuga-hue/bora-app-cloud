---
name: supabase_agent_rules
description: Core policy for supabase_agent. Defines how to interact with Supabase safely — API-only (never direct Postgres), SELECT-first, minimal scope. Called before any backend operation.
version: 2.0.0
---

# SUPABASE AGENT — POLICY & RULES

## ROLE
Defines and enforces the policy for all Supabase interactions. Every backend operation must comply with these rules before execution.

---

## OBJECTIVE

Garantir que todas as operações no Supabase sejam seguras, controladas, com escopo mínimo e sem impacto colateral.

---

## REGRAS DURAS

- ✅ Sempre usar Supabase API via MCP — NUNCA conexão direta Postgres
- ✅ Sempre começar com SELECT antes de qualquer modificação
- ✅ Trabalhar com escopo mínimo necessário
- ✅ Garantir consistência de dados entre tabelas relacionadas
- ✅ Validar estrutura antes de assumir colunas/tipos
- ❌ NUNCA executar ações destrutivas sem confirmação
- ❌ NUNCA fazer queries sem filtro (WHERE) em tabelas grandes
- ❌ NUNCA assumir estrutura do banco sem verificar `schema.sql`

---

## FLUXO OBRIGATÓRIO

1. IDENTIFICAR NECESSIDADE — o que exatamente precisa mudar?
2. INVESTIGAR (SELECT) — confirmar estado atual
3. VALIDAR — a operação é necessária e segura?
4. EXECUTAR (INSERT/UPDATE) — com escopo mínimo
5. CONFIRMAR RESULTADO — verificar dados pós-operação

---

## RESPONSABILIDADES

- ✅ Definir política de acesso ao Supabase
- ✅ Revisar toda operação antes da execução
- ✅ Garantir SELECT-first, API-only, escopo mínimo

## NÃO PODE FAZER

- ❌ Executar operações destrutivas sem confirmação humana
- ❌ Modificar RLS sem `flow_guard`
- ❌ Criar migrations sem `supabase_engine`
- ❌ Executar queries em produção sem revisão

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Política de acesso Supabase | **supabase_agent** (eu) |
| Execução de queries e migrations | `supabase_engine` |
| Mudanças em RLS / políticas | `flow_guard` + **supabase_agent** |
| Auth / sessão | `fix_auth` |

## RULES

- API-only — nunca Postgres direto (regra inviolável)
- SELECT antes de qualquer modificação (regra inviolável)
- Source of truth: `.claude/.ai/business_rules.md`
