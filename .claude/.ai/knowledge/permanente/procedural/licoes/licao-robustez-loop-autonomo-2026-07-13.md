---
tema: licao-robustez-loop-autonomo-2026-07-13 · escopo: projeto · estado: atual · atualizado: 2026-07-13
---
# Robustez do loop autónomo — 5 causas-raiz confirmadas numa só semana (2026-07-13)

> Agrupadas por tema (mesmo incidente-família: o carteiro/executor headless a ficar preso ou a
> mentir sobre o próprio estado). A 6.ª lição desta semana (LEI DO PRE-VOO) já vive em
> `permanente/procedural/decision-brain.md` (secção "✈️ LEI DO PRE-VOO") — não duplicada aqui.

## 1 — Pipe SSH não fecha = carteiro bloqueado para sempre (Elo 6)
- **Contexto:** ordens executadas com sucesso no PC (via SSH headless) apareciam "presas" —
  o trabalho tinha terminado mas o carteiro no VPS nunca via o fim.
- **O que correu mal:** `[Console]::In.ReadLine()` no `bora-live-parser.ps1` não deteta EOF de
  forma fiável quando há um `conhost.exe` anexado (caso do `sshd` do Windows a invocar `cmd.exe`)
  — o parser ficava à espera de mais input mesmo depois do `claude.exe` ter terminado, mantendo a
  sessão SSH `Established` e o `carteiro.sh` bloqueado num `read` de pipe sem EOF
  (`/proc/<pid>/wchan` = `pipe_read`).
- **Regra a aplicar:** ao ler stdin de um processo filho via pipe/SSH no Windows, usar
  `System.IO.StreamReader` sobre `[Console]::OpenStandardInput()` (lê o pipe redirecionado
  diretamente), nunca `ReadLine()` puro — e sempre envolver a leitura remota com `timeout N` do
  lado que espera a resposta (defesa em profundidade, não só o fix na fonte).
- **Evidência:** `inbox/investigacao-cadeia-ordens-2026-07-13.md`,
  `inbox/cura-elo6-pipe-ssh-2026-07-13.md`; `bora-live-parser.ps1` (correção 1);
  `carteiro.sh` `pc_exec()` (timeout 900→2400s, correção 2).

## 2 — Grep cego numa saída longa = falso rate-limit
- **Contexto:** uma ordem 100% bem-sucedida (relatório de 1986 bytes) foi marcada
  `pausada-rate-limit`, pausando a fila inteira até ao reset.
- **O que correu mal:** `is_rate_limit()` fazia `grep -iqE "...limit..."` sobre a saída inteira do
  `claude -p`. Quando a TAREFA pedia para citar literalmente a frase de rate-limit (ordem de
  diagnóstico), a própria citação disparava o grep — apesar de não haver bloqueio nenhum.
- **Regra a aplicar:** deteção de rate-limit real nunca pode ser só "a frase aparece em algum
  lugar" — um bloqueio genuíno da CLI é **sempre curto** (a CLI imprime a mensagem e para). Exigir
  as DUAS condições: frase presente **e** saída inteira ≤ limiar curto (600 bytes — ~10× a maior
  saída real observada, ~3× menor que a menor saída falsa observada). Qualquer heurística de
  "está bloqueado" sobre texto livre precisa de um segundo sinal barato (tamanho, formato, campo
  estruturado) além da string-match.
- **Evidência:** `inbox/rate-limit-falso-corrigido-2026-07-13.md`,
  `inbox/diagnostico-rate-limit-2026-07-13.md`; `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`
  (`is_rate_limit`, selftest 12/12).

## 3 — Múltiplos `claude.exe` em paralelo estouram RAM (4GB) e devolvem saída vazia
- **Contexto:** tarefas grandes/autorreferenciais devolviam saída **vazia** (não bloqueada —
  vazia) mesmo com o pipe a fechar corretamente.
- **O que correu mal:** sem lock de concorrência ao vivo no PC (`executor-lock.ps1` existia no
  repo mas não estava copiado para a pasta de deploy real), tarefas disparavam outro `claude.exe`
  por cima de um já a correr. Com só ~216 MB livres de ~3.9 GB, o processo novo falhava ou
  devolvia vazio.
- **Regra a aplicar:** um executor headless que pode ser invocado concorrentemente (SSH, cron,
  trigger) precisa de lock de exclusão mútua **deployado de facto**, não só existente no repo —
  confirmar sempre que o ficheiro vivo na pasta de execução é byte-a-byte igual ao do repo.
  Segundo processo que encontra o lock ocupado deve devolver um erro estruturado e reconhecível
  (ver lição 4), nunca silêncio.
- **Evidência:** `project_ponte_ram_root_cause_2026-07-12` (memória), `project_e2e_loop_ram_stall`
  (memória), `inbox/cura-elo6-pipe-ssh-2026-07-13.md` (secção "Causa secundária"),
  `executor-lock.ps1`.

## 4 — "JUIZ MUDO" era o lock a recusar 2.º executor, não falha de captura visual
- **Contexto:** 3 ordens (858e/93e0/39c5) ficaram com a nota genérica
  `⚖️ JUIZ-SEM-VEREDITO`, levantando a hipótese de que o Juiz tentava capturar prova visual em
  tarefas de infra sem alvo visual e travava.
- **O que correu mal:** as 3 ordens nunca chegaram a executar — `.saida.txt` continha só
  `ERRO: outro executor Bora ja em curso ha muito tempo` (o lock da lição 3 a funcionar
  corretamente). O `carteiro.sh` não tratava esse erro como caso especial: mandava-o ao Juiz como
  se fosse a saída real do trabalho, e o Juiz — sem diff nem trabalho para avaliar — não produzia
  `VEREDITO:` válido. A causa foi atribuída ao Juiz quando era a fila de execução ocupada.
- **Regra a aplicar:** (a) um erro estrutural do próprio orquestrador (lock ocupado, timeout,
  crash do executor) nunca deve seguir para o avaliador (Juiz/LLM) como se fosse o resultado da
  tarefa — detetar a string/padrão de erro ANTES de invocar o avaliador e tratar como retry, não
  como avaliação. (b) o avaliador deve distinguir tarefa visual (UI cliente/estafeta/parceiro/
  admin) de não-visual (infra/código/shell/backend): só a primeira tenta captura de ecrã; a
  segunda nunca tenta, `tem_visual = n/a`. (c) o avaliador imprime sempre uma linha `VEREDITO:`,
  mesmo inconclusiva (`VEREDITO: PRECISA OLHO HUMANO` + motivo) — nunca fica muda.
- **Evidência:** `inbox/juiz-tarefa-nao-visual-2026-07-13.md`; `carteiro.sh` (`is_lock_busy()`);
  `run-claude-loop.cmd` (`!LOCKRESULT!` com `EnableDelayedExpansion`);
  `.claude/agents/juiz-revisor.md` (secção "✈️ PRÉ-VOO").

## 5 — Ordens grandes estouram o teto de timeout
- **Contexto:** tarefas grandes legítimas (mega-ordens de várias partes) esgotavam o teto de
  15 min (`900s`) do `carteiro.sh` antes de terminar, aparecendo como travadas por timeout em vez
  de por bug.
- **Regra a aplicar:** dividir tarefa estimada >15 min em sub-tarefas menores **antes** de
  começar (ver LEI DO PRE-VOO em `decision-brain.md`) é a correção estrutural; como rede de
  segurança, o teto do carteiro subiu de 900s→2400s (`pc_exec`) e 200s→400s (`pc_judge`) para dar
  margem a tarefas legítimas que não foram divididas a tempo.
- **Evidência:** `inbox/cura-elo6-pipe-ssh-2026-07-13.md` (correção 2);
  `wiki/skills-metrics.md` (série de entradas `TIMEOUT-900s x2`, evolution-engine 2026-07-12/13).
