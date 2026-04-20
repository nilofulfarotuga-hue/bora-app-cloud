---
name: supabase_engine_debug
description: Debug procedure for supabase_engine. Identifies and corrects backend Supabase issues — logs, API errors, auth failures, realtime faults, data inconsistencies, RLS problems.
version: 2.1.0
protection_mode: read-only
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
- [ ] RLS policies corretas? (testado com `SET role authenticated`) — BR §21
- [ ] Queries corretas? (filtros, tipos, colunas)
- [ ] FK integrity preservada?
- [ ] Constantes em uso correspondem a BR §25.2?

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

---

## EXEMPLOS WORKED

#### Exemplo 1: Edge function `dispatch-engine` retorna 500
**Input (contexto):** Drivers não recebem ofertas; logs mostram 500 na edge function.
**Processo:**
1. Lê logs via `supabase functions logs dispatch-engine --tail`.
2. Identifica `ReferenceError: SUPABASE_URL is not defined`.
3. Diagnóstico: variável de ambiente não definida na deploy actual.
4. Fix proposto: adicionar `SUPABASE_URL` ao `.env` e ao Dashboard → Project Settings → Edge Functions secrets.
5. Não modifica edge function — apenas configuração.
**Output esperado:** Causa raiz + checklist de envs em falta + nota "redeploy obrigatório".
**Failure mode:** Adicionar env apenas em local sem propagar ao Dashboard → produção continua a falhar.

#### Exemplo 2: pg_cron job não corre às 03:00 segunda-feira
**Input (contexto):** Job programado para reset semanal não executou.
**Processo:**
1. Query em `cron.job_run_details` — confirma job nunca correu.
2. Inspecciona `cron.job` — descobre que `schedule` foi criado em UTC, não em Europe/Lisbon.
3. Diagnóstico: differença de fuso (BR §25.2 — fuso é Europe/Lisbon).
4. Propõe correcção: `cron.alter_job` com schedule ajustado.
**Output esperado:** Causa raiz + comando SQL proposto.
**Failure mode:** Recriar job sem `unschedule` do antigo → 2 jobs concorrentes.

---

## REFERÊNCIAS BORA APP

- Consulta: Supabase Dashboard → Logs (Functions / Auth / Realtime / Postgres).
- Consulta: [supabase/functions/](supabase/functions/) — código edge functions actuais.
- Consulta: [lib/main.dart](lib/main.dart) — config Supabase no client.
- Referências BR: §21 (RLS), §9.1 (SLA 7 min), §6.3 (timeout 40s dispatch), §22 (notificações), §25.2 (constantes/fuso).

---

## BENCHMARK UBER/IFOOD/GLOVO

> **Uber** tem "Production Engineering" com runbooks por categoria de erro Postgres/edge.
> **iFood** usa "Site Reliability" com playbooks de RCA (root cause analysis) obrigatórios antes de qualquer fix.
> **Glovo** tem dashboards de erro por edge function com alertas automáticos.
> **Bora equivalente:** `supabase_engine/debug` exige causa raiz comprovada com evidência (log + SELECT que reproduz) — equivalente ao processo de RCA do iFood.
