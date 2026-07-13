---
title: Conserto do "juiz mudo" — causa real e correção (não era o juiz)
data: 2026-07-13
autor: Claude Code (sessão interativa real)
---

# RESUMO

**Não era o juiz.** As 6 ordens travadas com nota `⚖️ JUIZ-SEM-VEREDITO` (`4c87`, `859a`, `858e`,
`14bc`, `93e0`, `39c5`) nunca chegaram a executar de todo — o `.saida.txt` de cada uma continha
apenas: `ERRO: outro executor Bora ja em curso ha muito tempo - tarefa nao executada, o carteiro
tenta de novo.` O `carteiro.sh` chamava o Juiz sobre essa mensagem de erro (sem sentido para
avaliar), e como o Haiku não devolvia uma linha `VEREDITO:` válida para aquilo, a nota enganosa
"JUIZ-SEM-VEREDITO" mascarava o problema real: o **lock de concorrência do PC** (`executor.lock`,
FASE 1.5) recusava sempre arrancar o `claude.exe`.

## Causa raiz do lock: bug de parsing do `cmd.exe`

Reproduzi o erro em isolamento total (sem SSH, sem outra ordem a correr, lock limpo) e confirmei
com instrumentação byte-a-byte que `LOCKRESULT` continha exatamente `ACQUIRED` — e mesmo assim o
`if /I not "%LOCKRESULT%"=="ACQUIRED"` entrava sempre no ramo de erro. A causa: a linha dentro
desse bloco `if (...)` tinha um parêntesis literal não escapado —
`... claude.exe (evita empilhar RAM) >> ...` — que confunde o parser do `cmd.exe` ao contar a
profundidade de parênteses de um bloco `if (...)`/`for ... do (...)`, um problema clássico e bem
documentado do batch do Windows. O resultado: o `if` nunca avaliava corretamente, e **toda** ordem
caía sempre no ramo "ERRO: outro executor" — mesmo com o lock genuinamente livre.

## Correção aplicada (2 ficheiros, repo + PC + VPS)

1. `run-claude-loop.cmd`: `setlocal EnableExtensions EnableDelayedExpansion` + troca de
   `%LOCKRESULT%` por `!LOCKRESULT!` no `if` de verificação do lock, e remoção dos parênteses
   literais do texto de log (`evita empilhar RAM` sem parênteses). Testado isoladamente no PC:
   `TESTE-LOCAL-OK` — o `claude.exe` arrancou e respondeu corretamente pela primeira vez.
2. `carteiro.sh`: nova deteção `is_lock_busy()` — se a saída do executor for exatamente essa
   mensagem de erro do lock, o carteiro **não chama o Juiz, não gasta tentativa**, marca nota
   `🔒 LOCK-OCUPADO` e reabre a ordem para a próxima volta. Confirmado ao vivo: uma ordem colidiu
   de propósito com um lock forçado e ficou corretamente `LOCK-OCUPADO — reaberta sem gastar
   tentativa` em vez de queimar tentativas.

Uma sessão paralela (ordem `6c0a`, despachada pelo Danilo em paralelo) chegou à mesma correção de
forma independente e já tinha commitado — reconciliei em vez de duplicar. Essa sessão foi mais
longe e reforçou `juiz-revisor.md`: captura visual só é exigida em tarefas de UI (nunca em
infra/shell) e a linha `VEREDITO:` deve ser sempre impressa, mesmo inconclusiva — proteção
preventiva para este mesmo tipo de falha não voltar a acontecer disfarçada de "juiz mudo".

## Prova

- Teste local isolado (fora da fila, sem qualquer concorrência): `TESTE-LOCAL-OK` — sucesso limpo.
- Teste ao vivo do `LOCK-OCUPADO`: ordem colidiu com lock forçado, ficou reaberta sem gastar
  tentativa (confirmado no `carteiro.log`).
- Teste ponta-a-ponta pela fila oficial (`ordem-20260713091435-3481`): disparado, ainda em fila
  atrás de outra ordem legítima e longa (`6c0a`, tarefa de investigação a decorrer dentro do
  orçamento normal de 2400s) — vai resolver sozinho quando `6c0a` terminar; não é preciso mais
  intervenção.

## Commits

`437d3c1` (carteiro.sh + run-claude-loop.cmd + reforço juiz-revisor.md + este relatório da sessão
paralela), já com push feito para `origin/autonomous-night-2026-04-29`.

## Ordens antigas travadas por este bug

`4c87`, `859a`, `858e`, `14bc`, `93e0`, `39c5` continuam `travada` com a nota enganosa antiga — o
objetivo de cada uma já foi respondido por este conserto (não precisam ser reabertas; reabri-las
gastaria orçamento a repetir uma investigação já concluída). Seguro arquivar quando conveniente.

---

**JUIZ CORRIGIDO — nunca mais trava por engano; causa real era o lock de concorrência do PC a
falhar sempre por um bug de parsing do cmd.exe (parênteses literais dentro de um bloco if), agora
corrigido nos dois pontos: a causa raiz (run-claude-loop.cmd) e a rede de segurança
(carteiro.sh não gasta tentativa nem confunde com falha do juiz).**
