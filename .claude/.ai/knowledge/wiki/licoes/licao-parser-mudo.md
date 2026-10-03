---
id: licao-parser-mudo
tipo: licao
origem: [bora-live-parser.ps1 · run-claude-loop.cmd · carteiro.sh · FASE 1.10 / mega-fix 2026-07-18 Parte 1]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — um parser que às vezes devolve 0 bytes faz o orquestrador diagnosticar a causa errada

**Problema.** Ordens grandes travavam mudas: o carteiro registava "SAIDA-VAZIA — tarefa grande
demais?" e retentava 5× a MESMA tarefa contra o MESMO teto (orçamento queimado, zero progresso).

**Causa real.** Quando o `claude.exe` para por atingir `--max-turns`/`--max-budget-usd`, o
stream-json emite um evento final `type:"result"` **sem** `.result` nem `.error`. O
`bora-live-parser.ps1` só fazia `Write-Output` se um desses campos existisse → nesse caso ficava
**mudo (0 bytes)** no stdout. O `carteiro.sh` interpretava 0 bytes como a causa genérica errada e
reabria a ordem em ciclo. Prova: ordem `94b1` (3 tarefas) = vazio 3×; ordem `eba8` (1 tarefa) =
passou (commit `71bdbc6`).

**Regra generalizável.**
- **Um parser/adaptador nunca pode devolver 0 bytes.** Se não sabe o que dizer, diz o que
  aconteceu: `EXECUTOR-PAROU: subtype=... turns=... custo=...`. Silêncio é lido como outra coisa
  a jusante.
- "SAIDA-VAZIA" não é uma causa — é um sintoma de várias (timeout de relógio, teto de
  turnos/orçamento, lock ocupado, rate-limit). Cada uma precisa do seu diagnóstico explícito na
  nota da ordem; nunca reduzir todas ao mesmo rótulo genérico.
- Tetos por tentativa têm de caber nas tarefas reais (subidos 40→150 turnos, $10→$25); e a
  camada acima deve TRAVAR já ao ver `EXECUTOR-PAROU:`, não repetir às cegas.

Ausência de sinal também é informação — mas só se alguém a emitir. Ver
[[licao-executor-vivo-mas-tarefa-pesada-esgota-tentativas]].
