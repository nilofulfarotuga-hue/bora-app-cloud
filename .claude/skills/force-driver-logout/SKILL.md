---
name: force-driver-logout
description: Força logout de um estafeta via Edge Fn admin-force-driver-logout (revoga sessões, limpa fcm_token, is_online=false, audita). Operação atómica de emergência — exige --confirm. Avisa se o estafeta tiver pedido em curso (--force-anyway).
metadata:
  type: operator
  category: driver
  depends_on: bora-knowledge
  uses_edge_fns: [admin-force-driver-logout]
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Force Driver Logout

Chama com segurança a Edge Fn `admin-force-driver-logout` (v11, **existe** — confirmado
via MCP). A Edge Fn faz tudo o trabalho server-side; esta skill valida, confirma e verifica.

## Como a Edge Fn funciona (do código real)
- POST `{ driver_id (uuid), reason }`, `Authorization: Bearer <JWT de admin>`
  (gate `app_metadata.role='admin'` — **não** aceita service_role).
- Revoga todas as sessões (`signOut global`), limpa `fcm_token`, `is_online=false`,
  carimba `last_forced_logout_at/by`, escreve `driver_force_logout` em `admin_audit_log`.
- Responde `{ success, driver_id, driver_name, sessions_revoked, fcm_cleared, last_forced_logout_at }`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (p/ ler driver),
e **JWT de admin**: `BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`.

## Modo (único — operação de emergência)
- Sem `--confirm` → **pré-visualiza** (não chama a Edge Fn).
- `--confirm` → executa.

```bash
python scripts/logout.py --driver-id <uuid> --reason "Suspeita de fraude"            # preview
python scripts/logout.py --driver-id <uuid> --reason "Suspeita de fraude" --confirm
python scripts/logout.py --driver-id <uuid> --reason "..." --confirm --force-anyway  # ignora pedido em curso
```

## Pipeline (logout.py)
1. Ler bora-knowledge 05/10.
2. `SELECT` driver (existência + `is_online` + estado).
3. Se tiver pedido em curso (preparing→onTheWay) → aviso; exige `--force-anyway`.
4. Obter JWT de admin; POST à Edge Fn com `{driver_id, reason, admin_user_id}`.
5. Verificar via `SELECT` que `is_online=false`.
6. Relatório PT-BR com request/response.

## Salvaguardas
- `--driver-id` validado como UUID (a Edge Fn rejeita não-UUID).
- Nunca chama sem `SUPABASE_SERVICE_ROLE_KEY` (leitura) e sem JWT de admin (Edge Fn).
- Não toca pricing/tokens/dispatch. A auditoria é feita pela própria Edge Fn.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
