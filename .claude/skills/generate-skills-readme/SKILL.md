---
name: generate-skills-readme
description: Gera o README.md mestre das skills, agrupado por categoria (metadata.type), a partir do frontmatter + corpo de cada SKILL.md — nome, o que faz, comando exemplo e dry-run sim/não. Dry-run escreve em _preview/; --write grava README.md na raiz. NÃO toca no INDEX.md (curado à mão). Stdlib-only.
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

# Generate Skills README

Produz o **README.md mestre** — guia navegável de todas as skills, agrupado por
categoria (`metadata.type`), derivado do frontmatter + corpo de cada `SKILL.md`.

## Relação com o INDEX.md
- `INDEX.md` é **curado à mão** (notas ricas por lote S1–S4) — esta skill **não lhe toca**.
- O output vai para `README.md` (gerado, navegável) — complementar, não substituto.

## Uso
```bash
python scripts/gen_readme.py            # dry-run → _preview/README.generated.md
python scripts/gen_readme.py --write    # grava README.md na raiz das skills
```

## Saída
Secções por categoria (Foundation, Orquestração, Onboarding, Auditoria, Operações,
Dados, Suporte, QA, DevOps, Design, Financeiro, Consolidação…). Para cada skill:
**nome · o que faz (1ª frase) · comando exemplo (1º bloco bash) · dry-run sim/não** + contagem total.

## Salvaguardas
- Read-only sobre as skills; só **gera** um ficheiro de índice (preview por default).
- Nunca edita `INDEX.md`, `SKILL.md`, DB, Stripe ou `lib/`.
- Stdlib-only; reusa o parser de frontmatter de `skills-doctor` (DRY).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
