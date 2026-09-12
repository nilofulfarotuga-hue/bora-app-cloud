---
id: ci-blindagem-docs-2026-07-18
data: 2026-07-18
tipo: relatorio
autor: devops-ci (executor autonomo)
estado: atual
---

# CI blindado contra builds redundantes em push só-documentação

## Problema

Commits que só tocam `.md`/`.claude/**` (relatórios, knowledge) disparavam a run
inteira de `build_android.yml`, que recompilava e tentava publicar na Google
Play batendo num `versionCode` já usado por uma run anterior — causa raiz das
falhas das builds 470 e 471 (a build real publicou; a run do commit de docs
falhou à toa e mandou email "Todas as tarefas falharam").

## Fix

Adicionado `paths-ignore` ao gatilho `on: push:` — só ignora a run quando
**todos** os ficheiros do push batem nos padrões `**.md` / `.claude/**`; um
push que mexe em código Flutter continua a compilar e publicar normalmente.

### Antes

```yaml
on:
  push:
    branches:
      - autonomous-night-2026-04-29
  workflow_dispatch:
```

### Depois

```yaml
on:
  push:
    branches:
      - autonomous-night-2026-04-29
    paths-ignore:
      - "**.md"
      - ".claude/**"
  workflow_dispatch:
```

Nenhum outro step do workflow foi alterado (steps, secrets, keystore, bump de
versionCode e publish mantidos exatamente como estavam).

## Commit real

```
c5831bd8a4e6f8f9ad772e85f9d73f5a7112d6aa
ci(build_android): ignorar pushes so-documentacao no trigger
```

Pushed para `origin/autonomous-night-2026-04-29` (`4335a0b..c5831bd`).

Nota: este commit mexe no `.yml` (código do workflow), por isso disparou UMA
build — esperado e ok, conforme instrução da tarefa.
