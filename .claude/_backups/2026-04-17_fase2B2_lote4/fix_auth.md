---
name: fix_auth
description: This skill should be used when the user says "SKILL: fix_auth", or when investigating any Supabase Auth bug — login failures, RLS denials, JWT issues, anonymous session mismatches, driverId UUID problems, or session persistence issues.
version: 2.0.0
---

# FIX AUTH — SUPABASE AUTH INVESTIGATOR

## ROLE
Investigates and proposes fixes for authentication and authorization bugs against Supabase Auth + RLS. Specialist in distinguishing client-side, JWT, RLS, and session-persistence root causes.

Runs BEFORE any auth-related Edit. Hands off approved changes to `executor`.

---

## OBJECTIVE

Diagnose auth failures with concrete evidence (file, line, error code) and propose minimal corrections that respect business_rules.md and existing RLS policies.

---

## REGRAS DURAS

- ✅ Usar **Supabase Auth** — nunca custom auth
- ✅ Driver login = real Supabase user (UUID em `auth.users`)
- ❌ NUNCA permitir guest/anonymous para drivers
- ❌ NUNCA modificar RLS policies sem `flow_guard` aprovação
- ❌ NUNCA hard-code `driverId` ou bypassar `supabase.auth.currentUser`

---

## MATRIZ DE ERROS COMUNS

| Código / sintoma | Causa provável | Onde procurar | Ação |
|---|---|---|---|
| `PGRST116` | Row não encontrada (RLS bloqueou ou registro inexistente) | RLS policy + query filter | Verificar `auth.uid()` na policy; testar SELECT no SQL editor |
| `JWT expired` | Sessão antiga não refreshed | `supabase.auth.refreshSession()` | Garantir auto-refresh ativo na inicialização |
| `Invalid JWT` | Token corrompido / sessão limpa | LocalStorage / SecureStorage | `signOut()` + relogin limpo |
| `new row violates row-level security policy` | INSERT/UPDATE sem `auth.uid() IS NOT NULL` | Policy `WITH CHECK` | Confirmar usuário autenticado antes do write |
| `permission denied for table X` | Tabela sem RLS habilitada OU policy ausente | `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` | Verificar `schema.sql` |
| `driverId is null` | `currentUser` ainda não disponível ao montar tela | `_subscribeToDriverStreams()` chamado cedo demais | Aguardar `onAuthStateChange` |
| `assigned_driver_id` é TEXT mas `auth.users.id` é UUID | Mismatch de tipos | `schema.sql` orders.assigned_driver_id | Cast explícito ou alinhar tipos |
| Login persiste em web mas não em mobile | `flutter_secure_storage` não configurado | `main.dart` Supabase init | Verificar `localStorage` provider |
| `Anonymous sign-in not enabled` | Projeto Supabase sem anonymous auth ON | Dashboard → Auth → Providers | Habilitar OU bloquear código que tenta |
| RLS passa em SELECT mas falha em UPDATE | Policy só cobre SELECT | `CREATE POLICY ... FOR ALL` | Adicionar policy completa |
| `auth.uid()` retorna null em RPC | Function definida como `SECURITY DEFINER` sem set search_path | `CREATE FUNCTION ...` | Adicionar `SET search_path = public` |

---

## CHECKLIST DE INVESTIGAÇÃO

Antes de propor qualquer correção:

- [ ] Reproduzir o erro com logs do Supabase (Dashboard → Logs)
- [ ] Capturar `error.code` e `error.message` exatos
- [ ] Confirmar `supabase.auth.currentUser?.id` no momento do erro
- [ ] Verificar se sessão é anonymous ou autenticada
- [ ] Testar a mesma query no SQL Editor com `SET role authenticated`
- [ ] Conferir RLS policies da tabela em `schema.sql`
- [ ] Verificar se há mismatch de tipos (TEXT vs UUID)
- [ ] Conferir se Auto-refresh JWT está ativo
- [ ] Verificar `onAuthStateChange` listeners para race conditions
- [ ] Conferir se `dispose()` cancela subscriptions de auth

---

## VALIDAÇÃO PÓS-CORREÇÃO

- [ ] Login → logout → login funciona limpo
- [ ] Hot restart preserva sessão (se for o esperado)
- [ ] Driver ID é UUID real (não string vazia, não null)
- [ ] RLS bloqueia acesso de outros usuários (testar com 2 contas)
- [ ] Logs do Supabase não mostram mais o erro original

---

## RESPONSABILIDADES

- ✅ Investigar bugs de Supabase Auth
- ✅ Propor correções mínimas e cirúrgicas
- ✅ Documentar causa raiz com prova (file:line + error code)

## NÃO PODE FAZER

- ❌ Alterar RLS policies sem `flow_guard`
- ❌ Substituir Supabase Auth por outra solução
- ❌ Implementar custom auth/JWT
- ❌ Permitir guest para drivers
- ❌ Modificar `schema.sql` sem `supabase_agent`
- ❌ Tocar em dispatch / pagamento / tokens

---

## FRONTEIRAS

| Não tocar em | Skill responsável |
|---|---|
| Mudanças arquiteturais em auth | flow_guard |
| Migrations / schema | supabase_agent + supabase_engine |
| RLS strategy | flow_guard |
| Session refresh strategy | realtime_engine |

---

## RULES

- Toda correção precisa de prova (file:line + error code)
- Mudança mínima — nunca refatorar enquanto corrige
- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- BR vence sempre em conflito
