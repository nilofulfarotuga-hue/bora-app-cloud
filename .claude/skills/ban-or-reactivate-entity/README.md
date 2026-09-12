# README — ban-or-reactivate-entity

Bane/reativa cliente, estafeta ou parceiro, com auditoria completa.

## Instalação / ambiente
`.env`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
`BORA_ADMIN_USER_ID`, `BORA_ADMIN_EMAIL`. Para ban/force-logout de **driver** também
`BORA_ADMIN_JWT` (ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`).

## Mecanismo por tipo (confirmado via MCP)
- **driver** → colunas `drivers.is_banned/banned_*/ban_reason_code/ban_reason` + force-logout.
- **partner** → `restaurants.is_active_admin=false` (sem colunas de ban; razão em audit).
- **client** → **Supabase Auth** `ban_duration` (`users` não tem colunas de ban).

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S2 (Ctx/log/audit_log/get_admin_jwt) |
| `ban.py` | banir (`--type --id --reason-code --reason [--until]`); dry-run default |
| `reactivate.py` | reativar (`--type --id --reason`) |
| `history.py` | bans atuais/passados de uma entidade |

## Notas técnicas
- **Sem transação cross-table** via PostgREST: o UPDATE da linha é atómico; force-logout e
  auditoria são best-effort com logging. Para atomicidade total seria preciso uma RPC dedicada.
- **Bloqueio**: não bane entidades com pedidos em curso (preparing→onTheWay). Devolve order ids.
- **ban_reason_code** (driver) tem de pertencer ao enum: fraud, misconduct, documents_invalid,
  inactivity, safety, other.
- Listar clientes banidos: consultar **Auth** (`/auth/v1/admin/users`), não a tabela `users`.

## Pendências pré-launch
- Migration para colunas de ban em `restaurants` (hoje só `is_active_admin`).
- `users` sem ban a nível de coluna → app não reflete o ban de cliente (vive no Auth).
