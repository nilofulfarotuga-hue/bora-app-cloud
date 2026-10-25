---
name: gh-cli-nao-encontrado
description: >
  Usa esta skill sempre que um comando invocar `gh` (GitHub CLI) no PC do Danilo e devolver 'Exit code 127 ... gh: command not found'. Visto 3x em 3 sessões/2 dias. O gh CLI não está instalado neste PC — não repetir o mesmo comando à espera que passe a funcionar.
metadata:
  versao: 1.0
  criada: 2026-09-23
  criada_por: vigia-habilidades (corrida 2026-09-23_2330)
  tema: "gh CLI não instalado no PC (exit code 127)"
  origem_literal:
    - "3x em 3 sessões/2 dias: Exit code 127 /usr/bin/bash: line 1: gh: command not found"
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# gh-cli-nao-encontrado

> Criada pelo vigia a 23/09/2026 porque o Danilo disse: 3x em 3 sessões/2 dias: Exit code 127 /usr/bin/bash: line 1: gh: command not found

# gh CLI não encontrado no PC do Danilo

Quando um comando devolve:
```
Exit code 127
/usr/bin/bash: line 1: gh: command not found
```
isto significa que o **GitHub CLI (`gh`) não está instalado** neste PC (Windows, Git Bash). Já aconteceu pelo menos 3 vezes em 3 sessões distintas em 2 dias — não é falha pontual.

## O que fazer

1. **Não repetir o mesmo comando** — sem `gh` instalado, ele nunca vai funcionar sozinho.
2. Preferir alternativas que já funcionam neste PC:
   - Operações de git puro (clone, push, fetch, branch, log) → usar `git` diretamente.
   - Issues, PRs, releases, checks do GitHub → API REST via `curl` com token, ou as ferramentas MCP já ligadas, se existirem para o repo em causa.
3. Se a tarefa depender mesmo de `gh` e não houver alternativa razoável, dizer isso no relatório em vez de insistir. Instalar software novo no PC do Danilo não é automático — é uma ação que precisa de confirmação dele, mesmo sendo grátis e reversível.

## Porquê

O Danilo não é programador e não vai instalar isto sozinho a meio de uma tarefa; o executor deve contornar com o que já existe (git, curl, MCP) em vez de travar a missão à espera do `gh`.
