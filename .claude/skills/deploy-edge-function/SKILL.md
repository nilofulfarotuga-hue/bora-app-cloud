---
name: deploy-edge-function
description: Deploy seguro de uma Edge Function — mostra o diff (local vs versão deployed) ANTES, preserva verify_jwt, e bloqueia funções protegidas (dispatch-engine/create-payment-intent/refund/stripe-webhook) sem --i-know-what-im-doing + --reason. Dry-run default.
metadata:
  type: devops
  category: edge-functions
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Deploy Edge Function

Faz deploy de **uma** Edge Function com diff prévio e salvaguardas. 38 funções locais em
`supabase/functions/`. **Nunca** fazer deploy às cegas de funções financeiras/dispatch.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/08-edge-functions.md` (catálogo + payloads)
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN` (management — p/ ler corpo deployed) ou usar MCP
`get_edge_function`. Deploy: CLI `supabase` autenticada + `--project-ref ojykpzwqrtusfeakzrna`.

## Uso
```bash
python scripts/diff_function.py --name notify-driver        # diff local vs deployed
python scripts/deploy.py --name notify-driver               # dry-run (mostra o que ia deployar)
python scripts/deploy.py --name notify-driver --commit      # corre supabase functions deploy
# função protegida:
python scripts/deploy.py --name refund --i-know-what-im-doing --reason "fix idempotency" --commit
```

## 🔒 Funções protegidas (exigem flag + reason)
`dispatch-engine`, `create-payment-intent`, `refund`, `stripe-webhook`,
`create-mbway-payment-intent` → deploy **bloqueado** sem `--i-know-what-im-doing` + `--reason`.

## Modos
- **DEFAULT (dry-run)**: mostra diff/summary + verify_jwt atual + comando que seria corrido. NÃO faz deploy.
- **`--commit`**: corre `supabase functions deploy <name> --project-ref <ref>` (com `--no-verify-jwt`
  se a função tinha `verify_jwt=false`, para **preservar** o setting). Regista em `admin_audit_log`.

## Salvaguardas
- Diff obrigatório antes (mostra adições/remoções).
- Preserva `verify_jwt` (lê o atual; passa flag correta).
- Confirma que a pasta local `supabase/functions/<name>/index.ts` existe.
- Não toca noutras funções. `--reason` vai para auditoria.
- Pendência: deploy via CLI requer `supabase login`; em alternativa usar MCP `deploy_edge_function`
  (o relatório indica o comando/payload).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
