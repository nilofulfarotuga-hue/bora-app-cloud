# FASE 2 · PARTE B.1 — Investigação JWT admin gate migration

> **Data:** 2026-04-28
> **Estado:** ⏸ AGUARDA OK do Danilo para avançar para B.2 (plano)
> **Counts:** 3 sítios Dart · 0 RLS email-based · 2 RLS já bora_role · 5 RPCs admin-gated · 1 RPC sem gate (`admin_dashboard_metrics`) · 1 Edge Function admin (`refund`)

---

## Surpresa positiva — **a maior parte do server-side já está migrado**

A migração JWT é **principalmente cliente-side**. Server-side a Fase 1 e Fase 2A já moveram quase tudo para `bora_role`. Há um único gap server-side (admin_dashboard_metrics).

---

## B.1.1 — Gate actual em `profile_screen.dart`

`lib/screens/profile_screen.dart:420-441`:

```dart
// ── Admin panel ────────────────────────────────────────────────
if (user?.email == 'nilofulfarotuga@gmail.com' ||
    user?.email == 'nilofulfaro@gmail.com')
  Padding(...
    child: ElevatedButton.icon(
      onPressed: () => Navigator.pushNamed(context, '/admin'),
      ...
```

**Allowlist (2 emails):**
- `nilofulfarotuga@gmail.com` ← admin actual
- `nilofulfaro@gmail.com` ← backup/historical

---

## B.1.2 — Mapeamento Dart-side completo

| # | Ficheiro:Linha | Tipo | Snippet (essência) | Defesa |
|---|---|---|---|---|
| 1 | `lib/screens/profile_screen.dart:421-422` | **email-based** UI gate | `if (user?.email == 'nilo…@gmail.com' \|\| …)` | Esconde botão "Painel Admin" |
| 2 | `lib/screens/admin/admin_dashboard_screen.dart:58-61` (`_isAuthorized`) | **email-based** screen gate | `email == 'nilo…@gmail.com' \|\| email == 'nilof…@gmail.com'` | Mostra "Acesso negado." se falhar |
| 3 | `lib/main.dart:157` | **route registration sem guard** | `'/admin': (_) => const AdminDashboardScreen()` | Nenhuma — depende do gate interno do screen (#2) |

**Conclusão:** Apenas **#1 e #2** fazem efectivamente gate. #3 é a porta aberta — a rota é alcançável via `Navigator.pushNamed(context, '/admin')` por qualquer ponto do código. A única defesa do `/admin` é o `_isAuthorized` interno do `AdminDashboardScreen` (#2).

**Note:** `admin_dashboard_screen.dart` também tem um comentário (L20-24) que justifica a escolha do email allowlist:

> "The `bora_role` metadata is reserved for the app's role system (client/driver/partner) and cannot be reused for admin without breaking client login."

Este comentário ficou **desactualizado** com a Fase 1 — `bora_role='admin'` foi adicionado **sem partir o login client/driver/partner** porque cada user tem o seu próprio `bora_role` distinct.

**Outros sítios admin no Dart (já migrados ou não relevantes):**
- `admin_partners_screen.dart` — sem gate próprio (depende do screen #2 acima); chama `admin_audit_service` que tem gate server-side.
- `admin_driver_approval_screen.dart` + `admin_drivers_screen.dart` — chamam RPCs com `_admin_op_guard()` (Fase 2A) que já valida `bora_role`. Server-side blinda — gate Dart é só UX.
- `auth_store.dart:128` — `static const _kRole = 'bora_role'` — reusa para client/driver/partner roles (não admin).

**Variantes não encontradas:** zero ocorrências de `isAdmin`, `IS_ADMIN`, `adminEmails` (variável). 100% do gate Dart está nos 3 sítios da tabela.

---

## B.1.3 — Mapeamento server-side

### RLS policies admin

| Source | Policy | Gate atual | Veredicto |
|---|---|---|---|
| `public.admin_audit_log` | `admin_audit_log_select_admin` (SELECT) | `COALESCE(jwt()->user_metadata->>'bora_role', jwt()->>'role') = 'admin'` | ✅ Já bora_role |
| `storage.objects` | `admin_read_all_driver_docs` (SELECT) | `EXISTS(auth.users WHERE id=auth.uid() AND raw_user_meta_data->>'bora_role'='admin' OR raw_user_meta_data->>'role'='admin')` | ✅ Já bora_role (via DB join) |

**Zero policies email-based.** Procurei explicitamente por `auth.email()`, `nilofulfarotuga`, `admin_email` — nada encontrado.

### RPCs admin-gated

| RPC | Pattern actual | Status |
|---|---|---|
| `_admin_op_guard()` (Fase 2A) | `bora_role='admin'` via auth.jwt() | ✅ Modelo do que queremos |
| `admin_approve_driver` | usa `_admin_op_guard()` | ✅ |
| `admin_reject_driver` | usa `_admin_op_guard()` | ✅ |
| `protect_admin_bora_role` (trigger fn) | matcha por email + bora_role | ✅ Protecção contra overwrite |
| `enforce_financial_immutability` (trigger fn) | `service_role` (não admin role) | ✅ separado |
| **`admin_dashboard_metrics()`** | **só `GRANT EXECUTE TO authenticated`** — sem check de role | 🚨 **GAP — qualquer authenticated chama** |

→ `admin_dashboard_metrics` tem um comentário inline: *"TEMPORARY: access is gated on the CLIENT (email allowlist) until a real admin role is introduced."* Esta é exactamente a migração que estamos a fazer.

**Mitigação que já existe**: a função só retorna **agregados** (4 totais) — blast radius limitado. Mas convém adicionar gate para coerência.

### Edge Functions admin-relevantes

| Function | `verify_jwt` | Gate adicional | Usado pelo admin? |
|---|---|---|---|
| `refund` | true | `claims.role === 'service_role'` (decoded inline) | **Não chamada** pelo admin actualmente (BUG 3 do roadmap) — relevante quando migrarmos cancel order |
| outras (charge-extra, dispatch-engine, notify-*, create-payment-intent, stripe-webhook) | mistura | n/a | não admin |

→ `refund` exige `service_role` token — hoje **só callable via service_role secret** (não via JWT do user). Para o admin chamar via app, ou (a) usar token service_role no client (péssima ideia), (b) migrar para gate `bora_role='admin' OR service_role`. **Decisão para B.2.**

### Triggers DB

`auth.users.trg_protect_admin_bora_role` ✅ activo (BEFORE UPDATE), proteje `bora_role='admin'` para `nilofulfarotuga@gmail.com`.

---

## B.1.4 — Estado actual do JWT (com prova empírica)

### Metadata em produção

```json
// raw_user_meta_data (writable by client via auth.updateUser)
{
  "sub": "c9fccf85-03ee-4efc-83bf-613f211a78ff",
  "email": "nilofulfarotuga@gmail.com",
  "bora_name": "Danilo",
  "bora_role": "admin",                            ← Fase 1 + trigger anti-overwrite
  "bora_phone": "9XXXXXXXXX",
  "email_verified": true,
  "phone_verified": false,
  "bora_consent_version": "1.0",
  "bora_consent_accepted_at": "2026-04-28T14:14:24.354925Z"
}

// raw_app_meta_data (only writable by service_role)
{
  "role": "admin",                                 ← !! NOVO: descoberta nesta investigação
  "provider": "email",
  "providers": ["email"]
}
```

### 🎯 Descoberta NOVA — `app_metadata.role = 'admin'` já existe!

Não estava documentado em lado nenhum: o `raw_app_meta_data` do admin tem `role='admin'`. **Isto é uma claim inalterável pelo cliente** (só service_role pode escrever). Foi setada num momento qualquer no passado (Studio admin? script?) e propaga-se ao JWT como `app_metadata.role`.

**Implicação:** podemos fazer um gate **mais seguro** com fallback chain de 3 níveis:

1. **`app_metadata.role = 'admin'`** ← imutável pelo cliente, **mais forte**
2. **`user_metadata.bora_role = 'admin'`** ← editável mas protegida pelo trigger Fase 1
3. **`email allowlist`** ← deprecated, fallback temporário com `debugPrint('DEPRECATED…')`

### JWT propagation confirmada

Supabase gotrue por default copia `raw_user_meta_data` → claim `user_metadata` e `raw_app_meta_data` → claim `app_metadata`. Confirmado pela construção simulada da query (mostra ambos os buckets).

**Sessão actual do admin:** `last_sign_in_at = 2026-04-28 17:53:17.85+00` — após Fase 1. **O JWT actual no telemóvel/app já carrega ambos os claims** (`bora_role` e `app_metadata.role`).

### Trigger Fase 1 verificado

`trg_protect_admin_bora_role` em `auth.users`, BEFORE UPDATE, function `protect_admin_bora_role` ✅ encontrado e activo.

---

## B.1.5 — Inventário de risco de lockout

| # | Risco | Probabilidade | Mitigação proposta |
|---|---|---|---|
| R1 | **Self-lockout client por bug no helper `isAdmin()`** (ler claim errado) | Médio se mal codado | Helper com 3 fallbacks (app_metadata.role → user_metadata.bora_role → email allowlist) + unit test mental antes de apply |
| R2 | **Cache JWT sessão antiga** sem `bora_role` | Baixo (sessão actual já tem) | `auth.refreshSession()` antes de denegar acesso. Se ainda falhar → fallback email |
| R3 | **Self-lockout RLS** | **Nulo** | Não há RLS de tabelas core que dependa de admin para o admin operar (RPCs SECURITY DEFINER bypassam) |
| R4 | **Self-lockout em Edge Function `refund`** se mudarmos service_role → bora_role | Médio | Dual gate `service_role OR bora_role='admin'` durante migração. Refund hoje não é chamado pelo painel — risco controlado |
| R5 | **Signup do cliente sobrescrever bora_role** (vector descoberto na Fase 1) | **Bloqueado** pelo trigger | trigger Fase 1 está activo (verificado) |
| R6 | **`admin_dashboard_metrics` sem gate server-side** permite que cliente normal chame e veja KPIs | Baixo (apenas agregados) | Adicionar gate `_admin_op_guard()` na RPC; remover comentário "TEMPORARY" |
| R7 | **Remoção precoce do email allowlist** antes de validação de tudo | Crítico se acontecer | Manter fallback durante 1 versão completa; removê-lo só na fase final B.6 com Danilo a confirmar |
| R8 | **Token antigo (tokenizado antes Fase 1) sem `bora_role`** | Baixo (admin signed-in 28 Apr) | Forçar refresh + fallback. `auth.refreshSession()` é SDK-native |

---

## B.1.6 — Resumo numérico e mapa

### Counts

- **3** sítios Dart com email allowlist (todos a substituir)
- **0** RLS policies email-based (👏)
- **2** RLS policies já bora_role-based
- **5** RPCs SECURITY DEFINER com gate admin (4 com `_admin_op_guard()`, 1 com service_role)
- **1** RPC SECURITY DEFINER sem gate (`admin_dashboard_metrics` — gap)
- **1** Edge Function admin-relevante (`refund` — não usado actualmente, decisão para B.2)
- **1** trigger anti-overwrite activo
- **2** claims admin no JWT actual: `app_metadata.role='admin'` (NOVO) + `user_metadata.bora_role='admin'`

### Quem fica afetado pela migração

| Camada | Alteração | Risco |
|---|---|---|
| **Dart** | Substituir 3 sítios + criar `AuthService.isAdmin()` | Médio (testar bem antes) |
| **Server RPC** | Adicionar `_admin_op_guard()` ao `admin_dashboard_metrics` | Baixo |
| **Edge Function** | `refund`: dual gate (deferível para Fase 3 BUG 3) | Baixo (não usado) |
| **RLS / triggers** | Nenhuma alteração | Zero |

### Estimativa

- Camada Dart: ~50 linhas (helper + 3 substituições)
- Camada server: ~5 linhas (1 GRANT/SELECT change em admin_dashboard_metrics)
- Camada Edge: 0 (deferível)
- **Total: ~55 linhas em ~5 ficheiros**

---

## Pergunta ao Danilo

OK na investigação? Direcção da solução proposta:

1. **Helper Dart `AuthService.isAdmin()`** com fallback chain de 3 níveis (app_metadata.role → user_metadata.bora_role → email allowlist deprecated)
2. **Refresh forçado** de JWT se claim missing antes de fallback
3. **Migrar 3 sítios Dart** identificados
4. **Adicionar gate em `admin_dashboard_metrics`** (cobrir GAP server-side)
5. **Diferir** `refund` Edge Function para quando o BUG 3 (cancel order) for trabalhado — não toca em produção atual
6. **Manter** email allowlist como fallback durante 1 versão; remover só na fase final

Se OK, escrevo plano detalhado **B.2** (helper exacto + edits linha-a-linha + ordem de apply + plano de rollback) e paro outra vez para o teu OK final antes do apply (B.3).
