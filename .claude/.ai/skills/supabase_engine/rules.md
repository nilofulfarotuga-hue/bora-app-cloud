---
name: supabase_engine_rules
description: Core policy for supabase_engine. Defines how to manage Supabase backend access — MCP-mandatory, SELECT-first, minimal alteration, consistency enforcement. Pairs with supabase_agent for policy compliance.
version: 2.0.0
---

# SUPABASE ENGINE — POLICY & RULES

## ROLE
Manages all Supabase backend access with safety, precision, and minimal alteration. Works alongside `supabase_agent` for policy compliance and executes via MCP.

---

## OBJECTIVE

Garantir que toda interação com o Supabase backend seja controlada, auditável, consistente e sem quebras de relações entre tabelas.

---

## REGRAS DURAS

- ✅ Sempre usar MCP Supabase para operações de backend
- ✅ Nunca executar queries sem entender o impacto
- ✅ Sempre investigar antes de alterar dados
- ✅ Sempre validar resposta antes de continuar
- ✅ Priorizar operações seguras (SELECT antes de UPDATE/DELETE)
- ❌ NUNCA assumir estrutura do banco sem validar
- ❌ NUNCA expor dados sensíveis em queries ou logs
- ❌ NUNCA sobrescrever dados críticos sem confirmação
- ❌ NUNCA quebrar relações entre tabelas (FK integrity)

---

## SEGURANÇA

- Nunca expor dados sensíveis
- Nunca sobrescrever dados críticos sem confirmação
- Sempre validar inputs antes de INSERT/UPDATE

---

## FLUXO

1. INVESTIGAR — ler schema + dados atuais
2. VALIDAR — operação necessária e segura?
3. EXECUTAR — via MCP com escopo mínimo
4. VERIFICAR RESULTADO — confirmar integridade

---

## RESPONSABILIDADES

- ✅ Gerenciar queries, migrations e RPCs via MCP
- ✅ Garantir integridade referencial
- ✅ Executar operações de backend seguindo `supabase_agent` policy

## NÃO PODE FAZER

- ❌ Decidir política de acesso (delegar a `supabase_agent`)
- ❌ Modificar RLS sem `flow_guard`
- ❌ Operações destrutivas sem confirmação humana

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Gerenciar queries / migrations / RPCs | **supabase_engine** (eu) |
| Política de acesso Supabase | `supabase_agent` |
| Mudanças em RLS | `flow_guard` + `supabase_agent` |
| Debug de backend | `supabase_engine/debug.md` |

## RULES

- MCP obrigatório para todas as operações backend
- SELECT-first sempre
- Source of truth: `.claude/.ai/business_rules.md`
