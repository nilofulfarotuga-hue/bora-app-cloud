---
id: fix-executor-max-turns-parser-mudo-2026-07-17
tipo: relatorio
data: 2026-07-17
zona: verde
commit: 572efb1
---

# Fix FASE 1.10 — parser mudo em max-turns/max-budget (2026-07-17)

## Causa raiz (já provada, não reinvestigada nesta tarefa)

O sintoma "tarefa grande dá SAIDA-VAZIA e trava 5 tentativas" **não é timeout** (o timeout já é
4h desde a FASE 1.9 de 16/07, com stale-output-watchdog). A causa real: `run-claude-loop.cmd`
corria o `claude.exe` com `--max-turns 40` e `--max-budget-usd 10` por tentativa. Quando a tarefa
era maior que isso, o `claude.exe` parava por max-turns/budget e o stream-json emitia um evento
final `type:"result"` **sem** `.result` nem `.error`. O `bora-live-parser.ps1` (ramo `'result'`)
só fazia `Write-Output` se um desses campos existisse — ficava **mudo (0 bytes)** — e o
`carteiro.sh` registava a nota genérica errada "SAIDA-VAZIA — tarefa grande demais?", reabrindo e
retentando a MESMA tarefa 5x contra o MESMO teto.

**Prova:** ordem `94b1` (3 tarefas empacotadas) deu saída vazia 3x sem tocar em nenhum ficheiro;
ordem `eba8` (a MESMA tarefa, só o Bug 1 isolado) passou e produziu o commit real `71bdbc6`.

## Fixes aplicados (3, cirúrgicos)

### 1. `bora-live-parser.ps1` (ramo `'result'`)
```diff
       if ($o.result) { Write-Output $o.result }
       elseif ($o.error) { Write-Output "ERRO: $($o.error)" }
+      else {
+        Write-Output "EXECUTOR-PAROU: subtype=$($o.subtype) turns=$($o.num_turns) custo=$($o.total_cost_usd)"
+      }
```
Regra dura: o parser nunca pode devolver 0 bytes — se não sabe o que dizer, diz o que aconteceu.

### 2. `run-claude-loop.cmd` (tetos T2 por tentativa)
```diff
-set "BUDGET=--max-budget-usd 10"
-set "TURNS=--max-turns 40"
+set "BUDGET=--max-budget-usd 25"
+set "TURNS=--max-turns 150"
```
Comentário do cabeçalho T2 atualizado para refletir os valores novos + a razão da subida.

### 3. `carteiro.sh` (deteção + nota exata + trava imediata)
- Nova função `executor_parou_linha()` extrai a linha `^EXECUTOR-PAROU:` da saída do `pc_exec`.
- No loop principal, se a linha existir: `setf nota "$linha_parou"` (nunca a nota genérica),
  `setf estado travada`, log, e `continue` — **sem chamar o Juiz nem gastar as 5 tentativas às
  cegas** (retentar contra o mesmo teto dá sempre o mesmo estouro).
- 2 casos novos no `--selftest`: extração da linha exata + vazio quando não há marcador.

## Testes feitos

- **Parser isolado** (`echo <json> | powershell -File bora-live-parser.ps1 -Live <tmp>`):
  - `type:result` sem `.result`/`.error` → stdout `EXECUTOR-PAROU: subtype=error_max_turns turns=150 custo=25.0` ✅ (nunca mais 0 bytes)
  - `type:result` com `.result` → stdout inalterado (regressão OK) ✅
  - `type:result` com `.error` → stdout `ERRO: ...` inalterado (regressão OK) ✅
- **`carteiro.sh --selftest`**: os 2 casos novos de `executor_parou_linha` passam. Falha
  pré-existente e não relacionada "reset 9:05am minutos" (lógica de parsing de hora de
  rate-limit) confirmada em `HEAD` (`71bdbc6`) via `git stash` antes desta mudança — não é
  regressão deste fix, fora do escopo desta tarefa.
- `bash -n carteiro.sh` → sintaxe OK.

## Commit

```
572efb1 fix(orquestracao): FASE 1.10 — parser nunca fica mudo em max-turns/max-budget
 4 files changed, 73 insertions(+), 4 deletions(-)
```
Ficheiros: `bora-live-parser.ps1`, `carteiro.sh`, `run-claude-loop.cmd`,
`wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md` (atualizada com a causa raiz
precisa — a versão de 2026-07-11 culpava o timeout de relógio, hoje desatualizada).

## Nota sobre o estado do repositório

O código dos 3 fixes e a atualização da lição já estavam presentes no working tree, não
commitados, quando esta tarefa começou — muito provavelmente uma tentativa anterior foi
interrompida exatamente pelo bug que estava a corrigir (SAIDA-VAZIA), antes de chegar ao commit e
ao relatório. Esta execução verificou o código já escrito, testou-o isoladamente (não estava
testado), e completou commit + relatório. Havia dezenas de outros ficheiros modificados/novos no
working tree pertencentes a trabalho concorrente de outros executores (TVDE, admin, CI, etc.) —
**não tocados nem commitados** aqui, por não pertencerem a esta tarefa.

## Fora do escopo (não tocado)

Nada de app Flutter, pricing, dispatch, Stripe, tokens ou RLS foi tocado — os 3 fixes são só
infraestrutura do orquestrador `carteiro`/`run-claude-loop` (Hermes), fora da Lista Vermelha.
