---
titulo: Lock órfão do executor.lock — correção definitiva (PID reciclado) — 2026-07-14
tipo: handoff
agente_origem: executor-headless
destino: bibliotecario-cerebro
---

## Pedido

Corrigir de vez o lock órfão do executor Bora: travou 2x no mesmo dia (PID 14592 e
8172, ambos mortos), deixando `executor.lock` preso e a fila parada. A correção
anterior (reduzir a tolerância de idade para 10min, FASE 1.5 em
`inbox/lock-concorrencia-2026-07-13.md`) não resolveu.

## Diagnóstico

O código de `executor-lock.ps1` (ação `acquire`) já verificava `Is-Alive($pid)` e já
assumia o lock imediatamente se o PID estivesse morto — em teoria, o cenário descrito
já devia estar coberto. A causa raiz real é mais sutil e já tinha sido documentada
noutro subsistema (memória `project_e2e_loop_ram_stall.md`, 3ª causa, sobre o
`.loop-noturno.lock` do E2E): **o Windows recicla números de PID**.

Sequência do bug:
1. O processo dono do lock (`cmd.exe` pai do `run-claude-loop.cmd`) morre e deixa o
   `executor.lock` com o seu PID (ex. 14592) escrito.
2. Minutos/horas depois, o Windows atribui esse **mesmo número** a outro processo
   qualquer do sistema (nada a ver com o Bora).
3. `Is-Alive(14592)` → `Get-Process -Id 14592` encontra esse processo novo e devolve
   `$true` — o código conclui "o dono ainda está vivo" e nunca mais considera o lock
   órfão, independentemente de quanto tempo passe. A tolerância de idade (10min) só
   se aplica quando o PID está **morto**; com um PID vivo (ainda que reciclado), essa
   branch nunca dispara.

Ou seja: o lock ficava preso não porque faltasse a checagem "PID morto", mas porque
"PID vivo" estava a dar falso-positivo por reciclagem — um bug de **identidade**, não
de **existência**.

## Correção aplicada

`.claude/.ai/hermes/orquestrador-carteiro/deploy/executor-lock.ps1`:

- `Write-Lock` agora grava também `start` — o start-time (epoch UTC) do processo dono,
  capturado no momento do `acquire`. Formato do lock: `{"pid":..,"ts":..,"start":..}`.
- Nova função `Test-LockAlive($info)`: só considera o lock vivo se (a) existe um
  processo com aquele PID **e** (b) o start-time desse processo bate exatamente com o
  gravado no lock. Discrepância = PID reciclado = **órfão imediato**, sem esperar
  tolerância nenhuma. Locks antigos sem o campo `start` (formato pré-fix) continuam a
  ser tratados só pela existência do PID, para não quebrar um lock legítimo a meio do
  deploy desta correção.
- Ação `acquire`: trocou `Is-Alive` por `Test-LockAlive` na decisão de assumir o lock.
- Ação `cleanorphans`: (a) a proteção da árvore de processos do executor ativo agora
  também usa `Test-LockAlive` (antes podia proteger por engano a árvore de um PID
  reciclado); (b) **novo passo de limpeza preventiva** — no arranque de cada ciclo
  (antes mesmo do `acquire`), se o `executor.lock` existir e `Test-LockAlive` disser
  que está órfão, é apagado logo ali, com log explícito no LIVELOG. Isto garante que
  a fila nunca fica à espera do próximo `acquire` para se curar sozinha.
- Removida `Is-Alive` (ficou órfã depois da troca para `Test-LockAlive` nos dois
  pontos que a usavam).

`.claude/.ai/hermes/orquestrador-carteiro/deploy/run-claude-loop.cmd`: adicionado
comentário FASE 1.8 no cabeçalho documentando o fix (mesmo padrão das FASE 1.3–1.7
já existentes), sem alteração de lógica — a chamada a `cleanorphans` já corria antes
do `acquire` em todos os ciclos (linha 73), por isso a limpeza preventiva entra em
vigor automaticamente sem precisar de nenhuma nova invocação no `.cmd`.

## Testes feitos (PowerShell, locks falsos em `%TEMP%`, nunca tocaram no lock real)

1. **PID morto** (`{"pid":999999,...}`, número que não existe) → `acquire`:
   `[loop-lock] lock orfao assumido (pid_anterior=999999 vivo=False ...)` → `ACQUIRED`.
2. **PID reciclado** (PID de um processo PowerShell realmente vivo nesta sessão, mas
   com `start` falso/antigo no lock — simula exatamente o bug real) → `acquire`:
   `vivo=False` (fingerprint não bate) → órfão assumido imediatamente, `ACQUIRED`.
   Este é o teste que prova a correção do bug real (PID vivo mas não é o mesmo
   processo).
3. **Lock legítimo** (mesmo PID vivo, mas com `start` real/correto) → `acquire`:
   `[loop-lock] outro executor a correr ... - a espera` → `TIMEOUT` (comportamento
   correto preservado — não regride a espera por um executor genuíno).
4. **cleanorphans preventivo**: lock com PID morto → ação `cleanorphans` sozinha (sem
   passar por `acquire`) detecta e remove o ficheiro logo no arranque do ciclo, com
   log `[loop-lock] limpeza preventiva: executor.lock orfao removido no arranque do
   ciclo (...)`; `Test-Path` confirma o ficheiro apagado.

Verificação de sintaxe: `[System.Management.Automation.Language.Parser]::ParseFile`
sobre `executor-lock.ps1` → sem erros.

## Ficheiros tocados

- `.claude/.ai/hermes/orquestrador-carteiro/deploy/executor-lock.ps1` (lógica)
- `.claude/.ai/hermes/orquestrador-carteiro/deploy/run-claude-loop.cmd` (comentário
  FASE 1.8, documentação — zero mudança de lógica)
- `.claude/.ai/knowledge/inbox/lock-orfao-definitivo-2026-07-14.md` (este relatório)

Nenhuma zona protegida tocada (dinheiro/pricing/dispatch/Stripe). Commit local feito;
push segue sujeito à limitação conhecida de push headless (ver
`project_headless_push_credential.md`) — não é bloqueio novo deste trabalho.

## Nota para o Bibliotecário

Vale a pena ligar esta memória a `project_e2e_loop_ram_stall.md` — o mesmo padrão de
bug (PID reciclado invalidando uma checagem "só existência") já lá estava descrito
como "fix definitivo de código (não aplicado, não urgente)" para o
`.loop-noturno.lock` do E2E. Esse fix (gravar pid+timestamp+identidade e validar os
três) continua por aplicar noutro lock diferente (`loop-noturno.py`, Python, fora
deste ficheiro) — só o `executor.lock` (PowerShell) foi corrigido agora. Se o mesmo
sintoma reaparecer no loop E2E noturno, é o mesmo bug de fundo, só que no outro
ficheiro.

Uma linha final: LOCK ORFAO corrigido de vez - PID morto e sempre ignorado, fila
nunca mais trava por isso.

## Reconfirmação (2026-07-14, mesma tarde — tarefa repetida na fila)

A fila voltou a pedir exatamente esta correção, com a mesma descrição e os mesmos
PIDs de exemplo (14592 e 8172) já citados acima — ou seja, é a mesma ordem a
reentrar, não um incidente novo. Verificado antes de repetir qualquer trabalho:

- `Test-LockAlive`, `Get-ProcStartEpoch`, a limpeza preventiva em `cleanorphans` e o
  comentário FASE 1.8 no `.cmd` continuam intactos em `executor-lock.ps1` (sem
  regressão, `git log` confirma commit `89fda72` já na branch).
- Não há `executor.lock` preso neste momento (`find` não encontrou nenhum ficheiro).
- Reteste ao vivo (não só o histórico do commit anterior), com locks falsos em
  `%TEMP%`, nunca no lock real:
  - PID morto (999999) → `[loop-lock] lock orfao assumido (... vivo=False idade_s=1)
    ACQUIRED` — órfão assumido na hora, sem esperar tolerância.
  - PID vivo mas `start` falso (simula reciclagem) → mesmo resultado, `vivo=False`,
    `ACQUIRED` imediato — confirma que a checagem de identidade continua a funcionar,
    não só a de existência.
- Nenhum ficheiro alterado desta vez além deste relatório — não há regressão a
  corrigir, o fix de `89fda72` já cobre 100% do pedido.

Commit local; push segue com a mesma limitação conhecida (executor headless não
empurra diretamente — ver `project_headless_push_credential.md`), sem relação com
Lista Vermelha aqui (não é ficheiro financeiro).

Uma linha final: LOCK ORFAO corrigido de vez - PID morto e sempre ignorado, fila
nunca mais trava por isso (reconfirmado, nenhuma mudança de código necessária).
