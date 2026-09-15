---
name: update-bora-knowledge
description: Deteta drift entre a skill bora-knowledge e a realidade do repo (Edge Functions em supabase/functions vs 08-edge-functions.md; pastas de skill vs INDEX.md + contagem) e, em MODO A, sincroniza factos verificáveis para um ficheiro auto-gerido (00-auto-facts.md). NUNCA edita os docs curados 01–12 (Knowledge Protocol). detect_drift é read-only; apply_updates só toca no ficheiro de máquina.
metadata:
  type: meta
  category: consolidation
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

# Update Bora Knowledge

Mantém a `bora-knowledge` honesta. Compara o que os docs afirmam com o que existe
mesmo no repositório e gera uma **proposta** de actualização para revisão.

## Knowledge Protocol (obrigatório)
Esta skill **nunca** escreve em `bora-knowledge/`. Segue o protocolo do CEO-AI:
detecta → **propõe diff ao Danilo** (`_preview/`) → Danilo aprova → edição manual +
entry em `decisions/`. Sync Obsidian fica a cargo do Danilo.

## O que verifica (repo-only, sem credenciais DB)
1. **Edge Functions** — pastas em `supabase/functions/` vs nomes citados em
   `knowledge/08-edge-functions.md`, nos dois sentidos:
   - em código mas não documentadas → sugerir documentar;
   - citadas no doc mas sem pasta → confirmar (renomeada / remota / planeada).
2. **Skills** — pastas reais vs tabela do `INDEX.md` + contagem declarada (`**N skills**`).

## Uso
```bash
# 1) Detetar drift (read-only)
python scripts/detect_drift.py            # relatório + _preview/knowledge-drift-<data>.md
python scripts/detect_drift.py --no-file  # só terminal

# 2) Sincronizar factos verificáveis — MODO A (preview → --apply)
python scripts/apply_updates.py           # preview → _preview/00-auto-facts.preview.md
python scripts/apply_updates.py --apply   # escreve knowledge/00-auto-facts.md
```

## MODO A — o que `apply_updates` toca
- **Só** escreve `knowledge/00-auto-facts.md` — ficheiro **gerido por máquina**
  (cabeçalho avisa "não editar"). Os docs curados 01–12 **nunca** são alterados.
- Sincroniza: contagem+lista de Edge Functions, contagem de skills por tipo, e o
  drift de Edge Functions. Factos que precisam de DB (tabelas, `platform_settings`,
  widgets, categorias) ficam como pendência (não inventados).

## Salvaguardas
- `detect_drift`: **nunca** escreve na knowledge — só propõe em `_preview/`.
- `apply_updates`: MODO A; o único ficheiro de knowledge tocado é o auto-gerido.
- Não toca docs curados, DB, Stripe, Edge Functions, `lib/`.
- Stdlib-only; reusa o motor meta de `skills-doctor` (DRY).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
