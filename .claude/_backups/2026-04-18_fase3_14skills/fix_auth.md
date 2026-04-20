---
name: fix_auth
description: This skill should be used when the user says "SKILL: fix_auth", or when investigating any Supabase Auth bug — login failures, RLS denials, JWT issues, anonymous session mismatches, driverId UUID problems, or session persistence issues.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill diagnostica bugs de autenticação e autorização e **propõe** fix cirúrgico — nunca aplica. Fix vai sempre à chain (decision_engine → flow_guard se toca RLS → guardian → executor). RLS ancorada em BR §21.

# FIX AUTH — SUPABASE AUTH INVESTIGATOR

## ROLE
Investigates and proposes fixes for authentication and authorization bugs against Supabase Auth + RLS. Specialist in distinguishing client-side, JWT, RLS, and session-persistence root causes.

Runs BEFORE any auth-related Edit. Hands off approved changes to `executor`.

---

## OBJECTIVE

Diagnose auth failures with concrete evidence (file, line, error code) and propose minimal corrections that respect `business_rules.md` and existing RLS policies (BR §21).

---

## REGRAS DURAS

- ✅ Usar **Supabase Auth** — nunca custom auth
- ✅ Driver login = real Supabase user (UUID em `auth.users`)
- ✅ Checkbox obrigatório "Aceito Termos e Política de Privacidade" (BR §11.1 · §15.2 · §20.1)
- ❌ NUNCA permitir guest/anonymous para drivers
- ❌ NUNCA modificar RLS policies sem `flow_guard` aprovação
- ❌ NUNCA hardcode `driverId` ou bypassar `supabase.auth.currentUser`

---

## MATRIZ DE ERROS COMUNS

| Código / sintoma | Causa provável | Onde procurar | Acção |
|---|---|---|---|
| `PGRST116` | Row não encontrada (RLS bloqueou ou registo inexistente) | RLS policy + query filter | Verificar `auth.uid()` na policy; testar SELECT no SQL Editor |
| `JWT expired` | Sessão antiga não refreshed | `supabase.auth.refreshSession()` | Garantir auto-refresh activo na inicialização |
| `Invalid JWT` | Token corrompido / sessão limpa | LocalStorage / SecureStorage | `signOut()` + relogin limpo |
| `new row violates row-level security policy` | INSERT/UPDATE sem `auth.uid() IS NOT NULL` | Policy `WITH CHECK` | Confirmar utilizador autenticado antes do write |
| `permission denied for table X` | Tabela sem RLS habilitada OU policy ausente | `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` | Verificar `schema.sql` |
| `driverId is null` | `currentUser` ainda não disponível ao montar ecrã | `_subscribeToDriverStreams()` chamado cedo demais | Aguardar `onAuthStateChange` |
| `assigned_driver_id` é TEXT mas `auth.users.id` é UUID | Mismatch de tipos | `schema.sql orders.assigned_driver_id` | Cast explícito ou alinhar tipos |
| Login persiste em web mas não em mobile | `flutter_secure_storage` não configurado | `main.dart` Supabase init | Verificar `localStorage` provider |
| `Anonymous sign-in not enabled` | Projecto Supabase sem anonymous auth ON | Dashboard → Auth → Providers | Habilitar OU bloquear código que tenta |
| RLS passa em SELECT mas falha em UPDATE | Policy só cobre SELECT | `CREATE POLICY ... FOR ALL` | Adicionar policy completa |
| `auth.uid()` retorna null em RPC | Função definida como `SECURITY DEFINER` sem `set search_path` | `CREATE FUNCTION ...` | Adicionar `SET search_path = public` |

---

## CHECKLIST DE INVESTIGAÇÃO

Antes de propor qualquer correcção:

- [ ] Reproduzir o erro com logs do Supabase (Dashboard → Logs)
- [ ] Capturar `error.code` e `error.message` exactos
- [ ] Confirmar `supabase.auth.currentUser?.id` no momento do erro
- [ ] Verificar se sessão é anonymous ou autenticada
- [ ] Testar a mesma query no SQL Editor com `SET role authenticated`
- [ ] Conferir RLS policies da tabela em `supabase/migrations/*` (BR §21)
- [ ] Verificar se há mismatch de tipos (TEXT vs UUID)
- [ ] Conferir se Auto-refresh JWT está activo
- [ ] Verificar `onAuthStateChange` listeners para race conditions
- [ ] Conferir se `dispose()` cancela subscriptions de auth

---

## VALIDAÇÃO PÓS-CORRECÇÃO

- [ ] Login → logout → login funciona limpo
- [ ] Hot restart preserva sessão (se for o esperado)
- [ ] Driver ID é UUID real (não string vazia, não null)
- [ ] RLS bloqueia acesso de outros utilizadores (testar com 2 contas)
- [ ] Logs do Supabase não mostram mais o erro original
- [ ] Consentimento GDPR presente (BR §20.1 — data/hora gravada)

---

## EXEMPLOS WORKED

### Exemplo 1: Erro `PGRST116` "more than one row returned" no perfil

**Input (contexto real):**
Cliente faz login. Abre "Perfil". App crasha com `PGRST116: The result contains X rows. The query expects 0 or 1 rows`. Logs do Supabase confirmam query `SELECT * FROM user_profiles WHERE id = ...`.

**Processo:**
1. Capturar erro exacto: `PGRST116` em `SELECT ... .single()`.
2. Ler código em `lib/screens/profile_screen.dart` → query é `supabase.from('user_profiles').select('*').eq('id', someId).single()`.
3. Verificar `someId` → está a usar `userId` (generic), mas tabela `user_profiles` tem múltiplos rows para o mesmo `userId` (um por role: cliente/driver/parceiro).
4. Falta filtro `.eq('role', currentRole)`.
5. Alternativa: verificar schema — se `user_profiles` deve ter 1 row por utilizador, então o bug é dados duplicados no banco (escalar a `supabase_engine`).
6. Confirmar com SELECT no SQL Editor: `SELECT count(*) FROM user_profiles WHERE user_id = '<x>'`. Se > 1 → bug de dados; se 1 → bug de query.

**Output esperado (bug de query):**
```
## FIX_AUTH REPORT

Sintoma: PGRST116 ao abrir Perfil
Causa-raíz: query sem filtro .eq('role', currentRole) → retorna múltiplas rows
BR REF: §21 (RLS deve filtrar por user_id, mas query deve adicionar role)

Evidência:
  - error.code: PGRST116
  - lib/screens/profile_screen.dart:58 — .single() sem filtro de role
  - SQL Editor confirma 3 rows para o user_id testado (client, driver, partner profiles)

Fix proposto (mínimo):
  lib/screens/profile_screen.dart:58
    supabase.from('user_profiles')
      .select('*')
      .eq('user_id', auth.uid())
+     .eq('role', SessionStore.currentRole)
      .single();

Handoff: decision_engine → guardian → executor
Escopo: 1 ficheiro, 1 linha. Sem impacto RLS.
```

**Failure mode:**
Skill falha se sugerir `.maybeSingle()` — isso esconde o bug (retorna null em vez de crash), não corrige. Também falha se recomendar alterar RLS — causa é no cliente, não na policy.

---

### Exemplo 2: Login falha após update de versão da app

**Input (contexto real):**
Drivers reportam: "Depois de actualizar a app hoje, não consigo entrar. Pede credenciais outra vez e diz 'Invalid JWT'."

**Processo:**
1. Capturar erro: `Invalid JWT` em inicialização de `supabase.auth.currentSession`.
2. Verificar `main.dart` — novo build muda a versão de `supabase_flutter` (ex: 1.x → 2.x). Formato do JWT pode ter mudado incompatibilmente.
3. Alternativamente: `FlutterSecureStorage` encriptou com chave derivada de versão; key refresh faz JWT velho não descodificar.
4. Fix proposto: detectar `Invalid JWT` na inicialização → `signOut()` silencioso → forçar relogin sem erro visível.
5. Validar com BR §11.1 / §15.2 (checkbox consentimento já foi aceite, mantido em `auth.users` metadata — relogin não deve exigir re-consent).

**Output esperado:**
```
## FIX_AUTH REPORT

Sintoma: "Invalid JWT" em 100% dos drivers após update 4.5 → 5.0
Causa-raíz: migração de supabase_flutter v1 → v2 alterou formato do JWT armazenado
BR REF: §20.1 (consentimento GDPR mantido em auth.users metadata)

Evidência:
  - pubspec.yaml: supabase_flutter bumped 1.10 → 2.3
  - lib/main.dart:42 — Supabase.initialize() não trata Invalid JWT
  - Logs: "Invalid JWT" após update em 95%+ dos drivers

Fix proposto (mínimo):
  lib/main.dart:42 — envolver Supabase.initialize() em try/catch;
    em Invalid JWT → supabase.auth.signOut(scope: SignOutScope.local) silencioso
    → app reabre em tela de login, utilizador relogga com credenciais existentes.
  + Preservar consentimento GDPR — não exigir re-aceitação do checkbox (BR §20.1).

Handoff: decision_engine → guardian → executor
Escopo: 1 ficheiro, ~10 linhas.
```

**Failure mode:**
Skill falha se propor "forçar re-signup" — isso apaga consentimento GDPR (BR §20.1) e quebra experiência. Também falha se não validar que o bug é universal (se fosse pontual, seria outro padrão — ex: corrupção local).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/auth/auth_store.dart` | Dupla camada (in-memory + Supabase Auth) |
| `lib/main.dart` | Setup Supabase + FlutterSecureStorage |
| `lib/screens/login_screen.dart` · `driver_login_screen.dart` · `partner_login_screen.dart` | Fluxos de login por role |
| `supabase/migrations/*.sql` | RLS policies (BR §21) |
| `supabase/migrations/` com `auth.uid()` | Verificar policies activas |
| Supabase Dashboard → Logs → Auth | Evidência de falha de login / JWT |
| Supabase Dashboard → SQL Editor | Reproduzir query com `SET role authenticated` |
| `.claude/.ai/business_rules.md` §21 | RLS por tabela (orders, drivers, driver_transactions, reservations) |
| `.claude/.ai/business_rules.md` §20 | GDPR — consentimento obrigatório, apagar conta |
| `.claude/.ai/business_rules.md` §11.1 · §15.2 | Checkbox "Aceito Termos" obrigatório |
| skill `fix_realtime` | Delegar se bug é de subscription (não auth) |
| skill `flow_guard` | Escalar se fix toca RLS |
| skill `supabase_agent` | Escalar se fix exige migration |

**NOTA:** skill lê logs e código, propõe fix. Aplicação é via chain; mudança em RLS exige `flow_guard`.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Auth Troubleshooter" dedicado — ferramenta interna que correlaciona códigos de erro (PGRST equivalentes, 401, 403) com runbooks específicos. Engenheiros de produto usam sem envolver backend team.
>
> **iFood** tem "Identity Service Debug Mode" — modo especial que loga cada passo da autenticação (client → gateway → identity service → RLS) para diagnosticar.
>
> **Glovo** tem "Session Inspector" — dashboard que mostra todas as sessões activas de um utilizador (device, IP, expiry, role) em tempo real.
>
> **Bora App equivalente:** `fix_auth` combina as três abordagens — matriz de erros comuns (Uber), checklist de investigação step-by-step (iFood), e validação pós-fix com 2 contas (Glovo). Cobre os três num skill único, sem tooling dedicado ainda.

---

## RESPONSABILIDADES

- ✅ Investigar bugs de Supabase Auth
- ✅ Propor correcções mínimas e cirúrgicas
- ✅ Documentar causa-raíz com prova (file:line + error code)
- ✅ Ancorar decisões em BR §21 (RLS) e §20 (GDPR)

## NÃO PODE FAZER

- ❌ Alterar RLS policies sem `flow_guard`
- ❌ Substituir Supabase Auth por outra solução
- ❌ Implementar custom auth / JWT
- ❌ Permitir guest para drivers
- ❌ Modificar `schema.sql` / migrations sem `supabase_agent`
- ❌ Tocar em dispatch / pagamento / tokens
- ❌ Modificar ficheiros (é read-only)

---

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Bug específico de auth / RLS / JWT | **fix_auth** (eu) |
| Mudanças arquiteturais em auth | `flow_guard` |
| Migrations / schema | `supabase_agent` + `supabase_engine` |
| Session refresh / realtime auth state | `realtime_engine` |
| Bug de subscription (não auth) | `fix_realtime` |

---

## RULES

- Toda correcção precisa de prova (file:line + error code)
- Mudança mínima — nunca refactor enquanto corrige
- Preservar consentimento GDPR (BR §20.1) em qualquer fix
- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md` v2
- BR vence sempre em conflito
