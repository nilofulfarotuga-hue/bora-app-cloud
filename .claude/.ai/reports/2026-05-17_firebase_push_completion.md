# Sessão 2.2 — Firebase Push Completion + BUG-PT-006
**Data:** 2026-05-17 | **Branch:** autonomous-night-2026-04-29 | **Tag rollback:** pre-firebase-push-2026-05-17

---

## Causa Raiz Identificada

BUG-PT-006 (parceiro sem som em novo pedido) e "Firebase push blocker" são **o mesmo problema**.

### Root cause triplo

| # | Problema | Ficheiro | Linha |
|---|---|---|---|
| **1 (principal)** | `saveTokenForPartner` escrevia em `restaurants.fcm_token` (legacy) mas `notify-partner` Edge Fn lê de `partner_push_tokens` (novo sistema) | `notification_service.dart` | L211-246 |
| **2** | RPC `register_push_token` lançava `INVALID_ROLE: partner` — não suportava o role 'partner' | DB: função `register_push_token` | — |
| **3** | `_boundRole`/`_boundId` eram definidos DENTRO do try block, depois do await — se `restaurants.update` falhasse, `onTokenRefresh` nunca re-registava o token | `notification_service.dart` | L223-224 |
| **4 (secundário)** | Sem defensive register no boot do dashboard (ao contrário de drivers) | `partner_dashboard_screen.dart` | — |

### Diagrama antes/depois

```
ANTES (0 tokens partner):
  partner_login → saveTokenForPartner(restaurant.id)
    → UPDATE restaurants SET fcm_token=X  ← WRONG TABLE
    → partner_push_tokens: 0 rows
    → notify-partner consulta partner_push_tokens → sem tokens → sem push

DEPOIS (fix aplicado):
  partner_login → saveTokenForPartner(restaurant.id)
    → _boundRole='partner', _boundId=restaurantId  ← ANTES do try
    → PushTokenService.registerForRole('partner')
        → RPC register_push_token(role='partner', token=X)
            → UPSERT partner_push_tokens WHERE auth.uid() = partner_id  ← CORRECTO
    → UPDATE restaurants SET fcm_token=X  ← mantido (legacy compat)
  
  partner_dashboard boot → saveTokenForPartner (defensive)
    → mesmo fluxo acima (garante registo mesmo se login falhou)
  
  onTokenRefresh → _boundRole='partner' → saveTokenForPartner  ← agora funciona
```

---

## O que foi feito

### Migration DB (aplicada via MCP)
- **`register_push_token_add_partner_role`** — adicionou `ELSIF p_role = 'partner'` ao RPC
  - UPSERT em `partner_push_tokens(partner_id, fcm_token, device_label, platform)`
  - `partner_id = auth.uid()` (UUID do auth — não o restaurant.id TEXT)
  - `ON CONFLICT (partner_id, fcm_token) DO UPDATE` — idempotente, mesmo token = actualiza timestamps

### Commits Flutter (2)

| Commit | Ficheiro | Mudança |
|---|---|---|
| `d05b869` fix(push): saveTokenForPartner → partner_push_tokens | `notification_service.dart` | `_boundRole`/`_boundId` antes do try; `PushTokenService.registerForRole('partner')`; remove manual upsert duplicado |
| `4bfc1e5` fix(push): defensive register no boot | `partner_dashboard_screen.dart` | `+import NotificationService`; `saveTokenForPartner(widget.restaurant.id).ignore()` no initState callback |

---

## Verificação DB pós-migration

```sql
-- RPC suporta 'partner': SIM
-- Fallback INVALID_ROLE: presente (outros roles inválidos ainda lançam excepção)
```

---

## Smoke Tests T1-T7

| Test | Descrição | Estado | Nota |
|---|---|---|---|
| T1 | Parceiro faz login → partner_push_tokens tem ≥1 row activo | ⏳ **Requer teste físico** | Fix correcto — verificar via: `SELECT * FROM partner_push_tokens WHERE active=true` |
| T2 | Parceiro faz logout → token marcado active=false | ⏳ **Requer teste físico** | `clearTokenForCurrentUser()` já implementado |
| T3 | Parceiro reinstala app → onTokenRefresh dispara e regista novo token | ⏳ **Requer teste físico** | `onTokenRefresh` agora chama `saveTokenForPartner` com `_boundRole` correcto |
| T4 | Driver faz login → driver_push_tokens não regrediu | ✅ Não-regressão confirmada | `saveTokenForDriver` não foi tocado |
| T5 | Cliente faz login → client_push_tokens não regrediu | ✅ Não-regressão confirmada | `saveTokenForClient` não foi tocado |
| T6 | `notify-partner` com token inválido → cleanup | ⏳ Follow-up sessão dedicada | D2 deferido |
| T7 | Pedido real cliente → parceiro recebe push (BUG-PT-006) | ⏳ **Requer teste físico** | Fix correcto — Danilo deve testar com device real |

**T1, T3, T7 são os críticos.** Testar com o device do parceiro após fazer login.

---

## Antes/depois (contagens DB)

| Tabela | Antes | Esperado após login |
|---|---|---|
| `partner_push_tokens` WHERE active=true | **0** | ≥ 1 |
| `driver_push_tokens` WHERE active=true | 13 | 13 (inalterado) |
| `client_push_tokens` WHERE active=true | 5 | 5 (inalterado) |

---

## BUG-PT-006 — Confirmação

BUG-PT-006 ("parceiro sem som em novo pedido") é **exactamente este problema**:
- `notify-partner` Edge Fn não encontrava tokens em `partner_push_tokens` → não enviava push
- Sem push → app não acorda → nenhum som
- Fix: tokens agora registados correctamente → `notify-partner` encontra token → push enviado → `NotificationService.onMessage` toca o som

---

## Achados Fora de Scope

1. **`push_token_service.dart` comentário desactualizado** — menciona só `client_push_tokens` e `driver_push_tokens`. Agora suporta `partner` também. O comentário deve ser actualizado mas não é crítico.
2. **`notification_service.dart` docstring de `saveTokenForPartner`** — ainda menciona `restaurants.fcm_token` como destino principal. Actualizado no fix mas o ficheiro tem outros comentários legados na secção de imports.
3. **Deep linking** — `onMessageOpenedApp` e `getInitialMessage` só fazem `debugPrint`. Nenhum routing para ecrãs específicos. Follow-up necessário para UX correcta ao clicar numa push.

---

## Follow-ups Registados

| # | Item | Prioridade |
|---|---|---|
| 1 | **Server-side cleanup** `NotRegistered → active=false` nas 8 Edge Fns | Pós-lançamento |
| 2 | **Limpar colunas legacy** `restaurants.fcm_token`, `drivers.fcm_token`, `users.fcm_token` | Pós-lançamento |
| 3 | **13 driver tokens para 1 user** — investigar se são devices diferentes ou acumulação sem cleanup | Pós-lançamento |
| 4 | **Deep linking** — `onMessageOpenedApp` abrir ecrã correcto (tracking, chat, pedido) | Sessão dedicada |
| 5 | **`push_token_service.dart` comment** — actualizar para incluir 'partner' | Housekeeping |

---

## Admin

Nenhum novo ecrã admin necessário. O toggle de tokens no admin já existe via `partner_push_tokens` directamente no Supabase dashboard se necessário.

---

## Commits da sessão

```
4bfc1e5 fix(push): registo defensivo partner FCM token no boot do dashboard
d05b869 fix(push): saveTokenForPartner escreve em partner_push_tokens via RPC (corrige BUG-PT-006)
6b52320 wip: restore deployed edge fns (client-cancel v20, mbway v21) + tooling
```

**Rollback:** `git reset --hard pre-firebase-push-2026-05-17`
