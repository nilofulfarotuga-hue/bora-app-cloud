---
name: ban-or-reactivate-entity
description: Bane ou reativa cliente, estafeta ou parceiro, com auditoria (quem/quando/razão/código). Driver via colunas ban; parceiro via is_active_admin; cliente via Supabase Auth ban_duration. Bloqueia ban com pedidos em curso. Dry-run por defeito; --commit escreve.
metadata:
  type: operator
  category: moderation
  depends_on: bora-knowledge
  uses_edge_fns: [admin-force-driver-logout]
  version: 1.0.0
---

# Ban / Reactivate Entity

Modera contas. **Mecanismo difere por tipo** (confirmado via MCP):

| Tipo | Onde mora o ban | Reason/código/until |
|------|-----------------|---------------------|
| **driver** | `drivers.is_banned/banned_at/banned_by/banned_until/ban_reason_code(enum)/ban_reason` | colunas dedicadas |
| **partner** | `restaurants.is_active_admin=false` (não há colunas de ban) | só em `admin_audit_log.details` |
| **client** | **Supabase Auth** `ban_duration` (a tabela `users` NÃO tem colunas de ban) | só em `admin_audit_log.details` |

> Enum `ban_reason_code` (drivers): `fraud, misconduct, documents_invalid, inactivity, safety, other`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
`BORA_ADMIN_EMAIL` (opcional); para driver force-logout: `BORA_ADMIN_JWT` ou
`BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD` (a Edge Fn exige JWT de admin).

## Modos
```bash
python scripts/history.py --type driver --id <uuid>
python scripts/ban.py --type driver --id <uuid> --reason-code misconduct --reason "..." [--until 2026-12-31T00:00:00Z]   # dry-run
python scripts/ban.py --type driver --id <uuid> --reason-code misconduct --reason "..." --commit
python scripts/reactivate.py --type partner --id <text-id> --reason "Resolvido" --commit
```

## Pipeline ban.py
1. Ler bora-knowledge 05/10.
2. `SELECT` entidade (confirma existência).
3. **Idempotência**: já banida → "já banido[a]" (exit 0).
4. **Bloqueio por pedidos em curso** (`orders.status IN
   preparing/callingDriver/driverAccepted/pickedUp/onTheWay`):
   - client → `orders.user_id`; driver → `orders.assigned_driver_id`; partner → `orders.restaurant_id`.
   - Se houver, **NÃO bane** e devolve a lista de order ids.
5. Aplica (atómico por linha):
   - **driver**: UPDATE ban cols + `is_online=false` → depois chama `admin-force-driver-logout`.
   - **partner**: UPDATE `is_active_admin=false`.
   - **client**: Auth `PUT /auth/v1/admin/users/{id}` com `ban_duration`.
6. `admin_audit_log` (action `entity_banned`, details com reason/code/until).

## reactivate.py
- driver: `is_banned=false, banned_at/until/reason_code/reason=NULL`.
- partner: `is_active_admin=true`. client: Auth `ban_duration='none'`.
- Auditoria `entity_reactivated`.

## Salvaguardas
- Dry-run default; `--commit` explícito.
- Bloqueio por pedidos em curso (acima).
- UPDATE é atómico por linha; side-effects (force-logout, audit) são best-effort com log
  (não há transação cross-table via REST — ver README).
- NÃO toca pricing/tokens/dispatch.

## Pendências (pré-launch)
- `restaurants` sem colunas de ban → considerar migration (`is_banned/banned_at/banned_by/
  ban_reason_code/ban_reason/banned_until`). NÃO feito nesta sessão.
- `users` sem colunas de ban → ban de cliente vive em Auth (app pode não refletir).
