# BUG 4 — Diagnóstico do toggle "Activar parceiro"

> **Data:** 2026-04-28
> **Origem:** Auditoria FASE 1 (relatório-mãe `2026-04-28-admin-panel-audit.md`)
> **Estado:** ⏸ ESPERA APROVAÇÃO Danilo
> **Ficheiros tocados na investigação:** ZERO (só leitura)

---

## 1. Schema actual de `public.restaurants` (17 colunas)

| Coluna | Tipo | Default | Semântica |
|---|---|---|---|
| `id` | text | `gen_random_uuid()` | PK textual |
| `created_at` | timestamptz | `now()` | — |
| `user_` | uuid | — | Owner Auth |
| `name` | text | — | — |
| `address` | text | — | — |
| `phone` | text | — | — |
| **`is_partner`** | boolean | NULL | Flag de **parceria comercial** (10+5+5%). NÃO é toggle administrativo. |
| `category` | text | — | — |
| `cuisine_type` | text | `''` | — |
| `photo_url` | text | `''` | — |
| **`is_online`** | boolean | `true` | Toggle **operacional do PRÓPRIO parceiro** (abrir/fechar agora). |
| `email` | text | `''` | — |
| `lat`, `lng` | double precision | — | — |
| `reservations_enabled` | boolean | `false` | Toggle de reservas. |
| `fcm_token` | text | — | Push do parceiro. |
| `business_hours` | jsonb | mon-sun 09:00-22:00 | Horários fixos. |

**Não existe** `is_active`, `is_open`, `accepting_orders`, `status`, `is_paused`, `paused_until`, `is_suspended`, `is_active_admin`. Confirmado por SQL.

---

## 2. Quantos sítios no código têm o bug

**3 ocorrências, TODAS em `lib/screens/admin/admin_partners_screen.dart`:**

| Linha | Operação |
|---|---|
| L32 | `.select('id, name, category, address, is_active')` ← lê coluna inexistente (retorna NULL) |
| L54 | `.update({'is_active': !currentActive}).eq('id', id)` ← escreve coluna inexistente (PATCH falha com 4xx, snackbar) |
| L111 | `final isActive = r['is_active'] as bool? ?? true;` ← cai no fallback `true` (toggle aparece sempre activo) |

**Nenhum outro ficheiro Dart** usa `is_active` em contexto de `restaurants`. O bug está perfeitamente isolado.

---

## 3. Há coluna admin (admin desliga) vs operacional (parceiro desliga)?

**NÃO existe coluna administrativa.** Apenas **`is_online`** que é controlado pelo *próprio* parceiro:
- `lib/stores/restaurant_store.dart:651` → `updatePartnerOnline(restaurantId, isOnline)` (chamado pelo dashboard parceiro)
- Default `true` na BD.
- Se admin reutilizar `is_online` para suspender, **o parceiro consegue reactivar-se a si próprio** → admin perde poder de override.

---

## 4. Recomendação: 3 opções com trade-offs

### ⭐ Opção A — Criar coluna `is_active_admin` (RECOMENDADO)

**O quê:** Nova coluna boolean `is_active_admin` default `true` em `restaurants`.

**Semântica:** override administrativo. Parceiro só aparece como disponível se `is_active_admin = true AND is_online = true`.

**Esforço:**
- 1 migration (`20260428000001_restaurants_is_active_admin.sql`) — `ALTER TABLE … ADD COLUMN is_active_admin BOOLEAN NOT NULL DEFAULT true;`
- 3 strings em `admin_partners_screen.dart` (L32, L54, L111) — `is_active` → `is_active_admin`
- 1 ajuste em `restaurant_store.dart` para filtrar `is_active_admin=true` ao listar restaurants ao público (linhas 130 e 135)
- 1 chamada `AdminAuditService.logAction(action: 'partner_toggle', entityId: restaurantId-textual-em-details, details: {old, new})` no toggle

**Risco:** **Baixo.** Default `true` preserva comportamento actual (todos os restaurants ficam visíveis). O ajuste em `restaurant_store` só esconde os que admin desligar — se nenhum for desligado, comportamento idêntico ao de hoje.

**Vantagens:**
- Separação limpa entre acção admin e operacional.
- Fácil reverter (admin pode reactivar).
- Padrão alinhado com o que o relatório-mãe descreveu na Fase B.

### Opção B — Reutilizar `is_online` (não recomendado)

**Esforço:** mínimo (mudar `is_active` → `is_online` em 3 strings).

**Problema:** parceiro reabre-se a si próprio → toggle do admin perde efeito. **Não resolve o problema operacional.**

### Opção C — `partner_status` enum (`active` / `paused_admin` / `suspended_admin` / `archived`)

**Esforço:** maior (enum + filtros + UI multi-estado).

**Quando faz sentido:** quando precisarmos de granularidade (suspender por 24h, banir definitivo, archive). Por agora **overkill** — recomendo deixar para Fase B/C do roadmap.

---

## 5. Observação lateral (separada deste bug)

Durante o smoke test do RPC `log_admin_action` descobri:

```
SELECT id, email, raw_user_meta_data->>'bora_role'
FROM auth.users WHERE email='nilofulfarotuga@gmail.com';
→ bora_role = "client"
```

O admin **NÃO tem** `bora_role='admin'` no JWT — a migration `20260424100000_set_admin_role.sql` foi **sobrescrita por um signup posterior** (o user signed-up no app cliente, que fez merge de `bora_role='client'`).

**Impacto:**
- A RLS policy de SELECT no `admin_audit_log` que acabei de criar **não deixa ler** com este user actual.
- A migration de roles do roadmap (Fase B7) já está parcialmente quebrada na origem.

**Recomendação:** task separada para (a) re-aplicar `bora_role='admin'` ao user e (b) adicionar trigger que impede signup do cliente de sobrescrever role admin existente. **Não bloqueia este bug 4** — o gate efectivo continua a ser o email allowlist em `profile_screen.dart:421-422`.

---

## 6. O que está PRONTO da PARTE A (já aplicado)

| Item | Estado | Localização |
|---|---|---|
| Migration `20260428000000_admin_audit_log.sql` | ✅ aplicada | `bora_app/supabase/migrations/` + DB |
| Tabela `public.admin_audit_log` (RLS on, 4 indexes) | ✅ criada | DB |
| RPC `public.log_admin_action(action, entity_type, entity_id, details) → uuid` (SECURITY DEFINER) | ✅ criada e testada | DB |
| Policy `admin_audit_log_select_admin` (FOR SELECT, role admin via JWT) | ✅ aplicada | DB |
| Helper `AdminAuditService.logAction(...)` Dart | ✅ criado | `bora_app/lib/services/admin_audit_service.dart` |
| Smoke test RPC (insert+delete via JWT simulado) | ✅ pass | DB limpa, 0 rows |

**Nada chamado em lado nenhum ainda** — conforme A.4.

---

## 7. Pergunta ao Danilo (decisão necessária)

**Qual opção aplico no BUG 4?** A / B / C — **default sugerido: A**.

E sobre a observação lateral (`bora_role` perdido): **task separada agora** ou **deixa para Fase B7 do roadmap**?

Após aprovação avanço para B.3 (aplicar fix) e B.4 (chamar audit log no toggle).
