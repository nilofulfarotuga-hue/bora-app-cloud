---
name: skills-doctor
description: Meta-skill read-only que valida todas as skills em .claude/skills/ — frontmatter (name/description/type), name == pasta, depends_on bora-knowledge, py_compile de cada script, README/requirements presentes, indício de dry-run em skills que escrevem. Relatório PT-PT [OK]/[!]/[X]. Não altera nada.
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

# Skills Doctor

Diagnóstico de saúde de **todas** as skills do Bora App. Read-only — nunca edita
nem executa as skills filhas, só inspeciona ficheiros e compila os scripts.

## Quando usar
- Antes de um build / antes de fechar uma sessão de skills.
- Depois de criar/editar uma skill (validar frontmatter + compilação).
- Auditoria periódica de consistência do diretório de skills.

## O que verifica (por skill)
| Nível | Regras |
|-------|--------|
| **[X] erro** | SKILL.md ausente · frontmatter sem `name`/`description` · `name` != pasta · script `.py` não compila (py_compile) |
| **[!] aviso** | sem `metadata.type` · sem `depends_on: bora-knowledge` (exceto foundation/orchestrator/validator) · sem README.md · scripts sem requirements.txt · escreve sem indício de dry-run |
| **[OK]** | sem erros nem avisos |

Skills isentas de `depends_on` (foundation/meta): `bora-knowledge`, `ceo-ai`,
`prompt-blindado-validator`, `auto-rules-sync`, e as 3 de consolidação S4-F.

## Uso
```bash
python scripts/check.py                      # valida todas
python scripts/check.py --skill notify-broadcast
python scripts/check.py --strict             # avisos contam para o exit code
```

Exit code = nº de skills com erro (com `--strict`, soma também os avisos). Útil em CI.

## Salvaguardas
- **Read-only total**: só lê ficheiros e corre `py_compile` (não executa lógica das skills).
- Não toca DB, Stripe, Edge Functions, nem `lib/`.
- Stdlib-only (sem dependências externas).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
