---
name: generate-release-notes
description: Gera notas de versão (PT-PT) a partir dos commits git desde o último tag/versão — agrupa por tipo (feat/fix/chore/docs), e inclui secção amigável "Para testers". Read-only sobre git; só escreve um markdown. Não cria tag nem push.
metadata:
  type: devops
  category: release
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

# Generate Release Notes

Cria `RELEASE_NOTES_v{N}.md` a partir do histórico git. **Read-only sobre git** — não faz
tag, não faz push (o Danilo decide isso).

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/11-conventions.md` (estilo de commits/versão)

## Ambiente
Nenhum (só git local). Versão lida de `pubspec.yaml` (`version: 1.0.1+230`).

## Uso
```bash
python scripts/release_notes.py                       # desde o último tag → RELEASE_NOTES_v{build}.md
python scripts/release_notes.py --since v1.0.0        # desde um ref específico
python scripts/release_notes.py --version 231         # força o nº de versão no título
```

## O que faz
1. Determina o range: `--since` (ref) ou último tag (`git describe --tags --abbrev=0`); senão raiz.
2. `git log <range>..HEAD` (read-only).
3. Agrupa por tipo de Conventional Commit: **feat / fix / chore / docs / refactor / outros**.
4. Gera markdown PT-PT em `bora_app/RELEASE_NOTES_v{N}.md`:
   - Resumo (contagens por tipo).
   - Secções por tipo (lista de commits, sem o prefixo).
   - **"Para testers"** — linguagem amigável (o que há de novo / o que testar).
5. Versão (N) = `--version` ou o `+build` do `pubspec.yaml`.

## Salvaguardas
- **Read-only sobre git**: só `git log`/`describe`. Não cria tags, não faz push, não toca código.
- Único output: o ficheiro markdown (revisável antes de publicar).
- Não incrementa `versionCode`/build (decisão do Danilo).

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
