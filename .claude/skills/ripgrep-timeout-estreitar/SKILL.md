---
name: ripgrep-timeout-estreitar
description: >
  Usa quando a pesquisa Grep/Ripgrep devolve 'Ripgrep search timed out after 20 seconds'. Não repitas a mesma pesquisa larga: restringe path e glob, exclui node_modules/build/.dart_tool/.git, ou usa ctx_execute para filtrar. Visto 4x em 4 sessões/2 dias (05-06/10/2026).
metadata:
  versao: 1.0
  criada: 2026-10-06
  criada_por: vigia-habilidades (corrida 2026-10-06_2332)
  tema: "Pesquisa Ripgrep/Grep a expirar aos 20 s"
  origem_literal:
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# ripgrep-timeout-estreitar

> Criada pelo vigia a 06/10/2026 porque o Danilo disse: 

# Grep a expirar: estreitar, nunca repetir igual

Origem: erro técnico repetido, `Ripgrep search timed out after 20 seconds`. Visto 4x em 4 sessões/2 dias (05 e 06/10/2026). O PC tem 4 GB e repos grandes.

## Regra
1. Não repitas a mesma pesquisa: vai expirar outra vez.
2. Restringe `path` à subpasta provável (`lib/`, `supabase/`, `.claude/skills/`) e nunca ao repo inteiro ou ao `C:\Users\danil`.
3. Usa `glob` ou `type` (`*.dart`, `*.sql`, `*.md`).
4. Exclui o que se regenera: `node_modules`, `build`, `.dart_tool`, `.git`, `%TEMP%`.
5. Ainda assim lento: `ctx_execute` ou `ctx_batch_execute` a filtrar na sandbox, ou `Glob` primeiro para listar os candidatos e depois `Grep` nesses.
6. Se os resultados forem parciais, diz que a pesquisa não terminou. Não declares 'não existe' sem ela ter completado.
7. Se a RAM estiver baixa, mede-a (Available MBytes) antes de insistir.
