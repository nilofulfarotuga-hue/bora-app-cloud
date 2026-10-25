---
name: git-add-por-caminho
description: >
  Usa SEMPRE antes de correr 'git add' no Bash. Se vires 'bora-tranca: BLOQUEADO Bash — git add -A / git add .' (arrasta trabalho alheio), não contornes nem repitas o comando. Faz 'git status --short', escolhe só os ficheiros desta tarefa e adiciona-os por caminho exacto. Visto em 2 sessões/2 dias (21-22/10/2026).
metadata:
  versao: 1.0
  criada: 2026-10-22
  criada_por: vigia-habilidades (corrida 2026-10-22_2330)
  tema: "bora-tranca bloqueia git add -A / git add ."
  origem_literal:
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# git-add-por-caminho

> Criada pelo vigia a 22/10/2026 porque o Danilo disse: 

# git add por caminho

## Quando
Antes de qualquer `git add`. Também quando o erro for `bora-tranca: BLOQUEADO Bash — git add -A / git add .`.

## Porquê
O repo do Bora tem várias sessões e agentes a trabalhar ao mesmo tempo. `git add -A` e `git add .` levam para o commit o trabalho dos outros. A tranca bloqueia de propósito e não é falso positivo.

## Regra
1. Não repitas o comando bloqueado e não o contornes (`git commit -a`, `git add -u` e `git add :/` também são atalhos para o mesmo).
2. Corre `git status --short` e identifica só os ficheiros que tu mexeste nesta tarefa.
3. Adiciona um a um ou por pasta exacta: `git add caminho/ficheiro1 caminho/ficheiro2`.
4. Confirma com `git diff --cached --stat` que só viaja o que é teu.
5. Se a tranca bloquear mesmo assim, regista no e2e_log e avisa o Danilo numa linha. Não contornes.

## Lembrete
Push é publicação. O `git push` nunca se delega e só se faz depois de veres o que viaja junto.

## Origem
Erro repetido em 2 sessões/2 dias, 21-22/10/2026 (corpus do vigia).
