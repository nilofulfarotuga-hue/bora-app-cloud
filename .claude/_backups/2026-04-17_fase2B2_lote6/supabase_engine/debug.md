---
name: supabase_engine_debug
description: Debug procedure for supabase_engine. Identifies and corrects backend Supabase issues — logs, API errors, auth failures, realtime faults, data inconsistencies, RLS problems.
version: 2.0.0
---

# SUPABASE ENGINE — DEBUG PROCEDURE

## ROLE
Investigation and correction protocol for backend Supabase issues. Works within `supabase_engine` policy constraints.

---

## OBJECTIVE

Identificar e corrigir problemas no backend Supabase com causa raiz comprovada antes de qualquer fix.

---

## PASSOS

### 1. IDENTIFICAR ERRO
- Logs do Supabase Dashboard (Functions, Auth, Realtime)
- Respostas de API (error.code + error.message)
- Falhas de autenticação (PGRST116, JWT expired, etc.)
- Falhas de realtime (eventos não chegam)

### 2. INVESTIGAR
- Verificar tabelas envolvidas (`schema.sql`)
- Verificar dados inconsistentes (SELECT para confirmar)
- Verificar políticas RLS (Dashboard → Auth → Policies)
- Verificar conexões e channels ativos

### 3. VALIDAR
- Confirmar causa raiz com evidência
- Nunca assumir — testar hipótese no SQL Editor

### 4. CORRIGIR
- Aplicar mudança mínima
- Não quebrar sistema ao corrigir

### 5. VERIFICAR
- Reproduzir o fluxo original
- Confirmar que erro não ocorre mais

---

## CHECKLIST

- [ ] Auth funcionando? (`auth.currentUser` não null)
- [ ] Dados existem na tabela? (SELECT confirma)
- [ ] Realtime ativo? (Supabase Dashboard → Realtime)
- [ ] RLS policies corretas? (testado com `SET role authenticated`)
- [ ] Queries corretas? (filtros, tipos, colunas)
- [ ] FK integrity preservada?

---

## RESPONSABILIDADES

- ✅ Investigar e propor fix para problemas de backend
- ✅ Confirmar causa raiz com evidência antes de corrigir

## NÃO PODE FAZER

- ❌ Modificar RLS sem `flow_guard`
- ❌ Executar DELETE sem confirmação humana
- ❌ Alterar schema sem migration documentada

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Investigar problema de backend Supabase | **supabase_engine/debug.md** (eu) |
| Executar queries/migrations | `supabase_engine/queries.md` |
| Política de acesso | `supabase_agent/rules.md` |
| Bug de auth específico | `fix_auth` |

## RULES

- Causa raiz obrigatória antes de qualquer fix
- Prova: log + SELECT que reproduz o problema
- Source of truth: `.claude/.ai/business_rules.md`
