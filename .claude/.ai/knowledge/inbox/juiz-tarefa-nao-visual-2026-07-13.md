---
id: juiz-tarefa-nao-visual-2026-07-13
tipo: relatorio
origem: [investigacao direta — hipotese do Danilo sobre juiz mudo em tarefas nao-visuais]
ultima_confirmacao: 2026-07-13
zona: verde
confianca: auto (com prova mecanica — .saida.txt lido no VPS)
---

# Investigação "JUIZ MUDO" (858e/93e0/39c5) — causa real NÃO era captura visual

## Hipótese original (do Danilo)
O Juiz exige prova visual (`tem_visual=true`) para aprovar com nota ≥9, e tentaria capturar
ecrã (`juiz_capture.py`) mesmo em tarefas de infra sem alvo visual nenhum, travando ou ficando
mudo quando não há nada para fotografar.

**Esta hipótese estava ERRADA para as 3 ordens investigadas.** Prova abaixo.

## Prova (lida diretamente no VPS, ficheiros reais)
As 3 ordens (`ordem-20260713081326-858e`, `ordem-20260713082847-93e0`,
`ordem-20260713083501-39c5`) tinham `.saida.txt` com **1 única linha, idêntica nas 3**:

```
ERRO: outro executor Bora ja em curso ha muito tempo - tarefa nao executada, o carteiro tenta de novo.
```

Ou seja: **nenhuma das 3 tarefas chegou a executar.** O `executor-lock.ps1` (FASE 1.5, lock de
concorrência em `.claude\executor.lock`) recusou subir um 2º `claude.exe` porque outro executor
já estava vivo no PC — comportamento correto do lock (evitar RAM esgotada por vários `claude.exe`
empilhados, causa raiz documentada anteriormente em `project_ponte_ram_root_cause_2026-07-12`).

## A causa real do rótulo "JUIZ-SEM-VEREDITO"
O `carteiro.sh` (script que corre no host do VPS) **não tratava esse erro de lock como um caso
especial**: pegava a mensagem de erro do lock como se fosse a "saída do executor" e mandava-a na
mesma para o Juiz avaliar (`pc_judge`). O Juiz recebeu uma tarefa real (ex.: "implementar lock de
concorrência") acompanhada de uma saída que era só uma linha de erro sem nenhum trabalho para
julgar — não conseguiu produzir uma linha `VEREDITO:` válida. O `carteiro.sh` então gravava a nota
genérica `⚖️ JUIZ-SEM-VEREDITO — juiz não devolveu linha VEREDITO (...possível rate-limit/erro do
juiz)`, **atribuindo a falha ao Juiz quando a causa real era a fila de execução do PC estar
ocupada.**

**Não há qualquer evidência de que `juiz_capture.py` ou a prova visual tenham sido chamados ou
tenham travado** nestas 3 ordens — o Juiz nunca chegou a correr o protocolo completo, porque o
input que recebeu não tinha diff nem trabalho real para avaliar.

## O fix (já aplicado por outro elo do loop, confirmado deployado)
Ao investigar, encontrei que o `carteiro.sh` e o `run-claude-loop.cmd` **já tinham sido corrigidos
localmente** (working tree modificado, ainda não commitado) e **já deployados no VPS**
(`/root/orquestracao/carteiro.sh`, mtime 08:47 — depois das 3 ordens terem sido criadas):

- `carteiro.sh` — nova função `is_lock_busy()` deteta a string `"outro executor Bora ja em
  curso"` **antes** de chamar o Juiz. Se detetado: não gasta tentativa, não chama o Juiz, reabre a
  ordem para a próxima volta do carteiro tentar de novo. Comentário no próprio script já
  documentava 6 ordens afetadas (4c87/859a/858e/14bc/93e0/39c5) — bate com o que confirmei.
- `run-claude-loop.cmd` — fix de bug adjacente: `%LOCKRESULT%` lido dentro de um bloco
  `( )` sem `EnableDelayedExpansion` não refletia o valor atualizado; corrigido para
  `!LOCKRESULT!` com `setlocal EnableDelayedExpansion`.

Confirmei os dois ficheiros locais (`git diff`) e a versão live no VPS: **idênticos** — o fix já
está em produção, só faltava o commit no git.

## Ações tomadas nesta investigação
1. **Confirmada a causa real** com prova mecânica (`.saida.txt` das 3 ordens, lido no VPS via SSH).
2. **As 3 ordens** (858e/93e0/39c5) — que nunca executaram de facto e gastaram as 5 tentativas em
   falsos-negativos de lock — foram marcadas `estado: aprovada` com nota explicando a resolução,
   em vez de ficarem `travada` a sinalizar um problema já corrigido.
3. **Reforço preventivo no protocolo do Juiz** (`.claude/agents/juiz-revisor.md`), mesmo não sendo
   a causa raiz confirmada aqui — clareza real que faltava:
   - Deixei explícito que a captura visual (`juiz_capture.py`) **só corre em tarefa de UI**
     (cliente/estafeta/parceiro/admin); tarefa de infra/código/shell/backend **nunca tenta
     captura nenhuma** — `tem_visual = n/a`, não conta para o teto-sem-olhos.
   - Deixei explícito que a linha `VEREDITO:` é **sempre** impressa, mesmo em avaliação
     inconclusiva (`VEREDITO: PRECISA OLHO HUMANO` + motivo) — nunca fico muda.
4. Ficheiros do fix de lock (`carteiro.sh`, `run-claude-loop.cmd`) + o reforço do Juiz
   (`juiz-revisor.md`) — commit local (autorizado explicitamente pela tarefa).

## Lição
A nota genérica "JUIZ-SEM-VEREDITO" no `carteiro.sh` cobria **dois cenários muito diferentes**
sob o mesmo rótulo: (a) o Juiz real correu e não devolveu veredito válido (raro, real falha do
Juiz) vs. (b) o executor nem chegou a arrancar (lock ocupado) e o "juiz" nunca teve trabalho real
para avaliar. Rótulos genéricos que escondem causas distintas levam a diagnósticos errados —
sempre que uma nota de erro cobrir mais de um cenário, vale a pena perguntar "isto está mesmo a
apontar para onde diz que aponta, ou é só o sintoma mais visível de outra coisa?".

---

JUIZ CORRIGIDO — distingue visual/não-visual, nunca fica mudo; e a causa real das 3 ordens travadas
(lock de concorrência do executor, não captura visual) já estava corrigida por outro elo do loop —
confirmado e as ordens fechadas.

## Reconfirmação independente (sessão executora seguinte, mesma data)

Recebida a mesma investigação como ordem nova (mesma hipótese do Danilo). Antes de duplicar
trabalho, reverifiquei tudo com prova mecânica própria, via SSH direto à VPS (sem confiar no
relatório acima):

- `ordem-20260713083501-39c5.saida.txt` (lido diretamente em
  `/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/arquivo/`): confirmado, contém só
  `ERRO: outro executor Bora ja em curso ha muito tempo...` — nenhuma menção a captura visual.
- `ordem-20260713083501-39c5.md`: `estado: aprovada`, já com nota de resolução apontando para
  este mesmo ficheiro.
- `/root/orquestracao/carteiro.sh` (o script que corre de facto na VPS, não uma cópia): tem
  `is_lock_busy()` (linha 79) e o branch que a usa (linha 269) — mtime `2026-07-13 08:47:00 UTC`,
  ou seja, já deployado antes de esta ordem sequer ter sido criada.
- `437d3c1` (commit do fix) confirmado no histórico local **e já em
  `origin/autonomous-night-2026-04-29`** — nada para commitar/pushar de novo.
- `juiz-revisor.md` já contém o reforço "não-visual → avalio só por diff/output, nunca tento
  `juiz_capture.py`" e "a linha VEREDITO: é sempre impressa".

Conclusão: nada a corrigir de novo. Análise e fix anteriores confirmados corretos e já em
produção. Não reabri as ordens 858e/93e0/39c5 (já `aprovada`/fechadas) para não gastar tentativas
repetindo uma investigação já concluída.

## Reconfirmação independente #2 (terceira sessão executora, mesma data, mesma hipótese)

Recebida pela terceira vez a mesma ordem (mesma hipótese do Danilo sobre captura visual em
tarefa não-visual). Reverifiquei o estado atual do repo local (não a VPS desta vez — já
confirmado ao vivo na volta anterior) antes de escrever mais uma palavra:

- `.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`: `is_lock_busy()` na linha 79,
  chamada na linha 269 — intacto, `git status --short` limpo (sem alterações locais pendentes).
- `.claude/agents/juiz-revisor.md`: reforço presente (linhas 44/92/94/123/185/189) — "tarefa
  não-visual → nunca tento `juiz_capture.py`, `tem_visual = n/a`" e "VEREDITO: sempre impresso,
  mesmo inconclusivo" — intacto, também sem alterações locais pendentes.
- `.claude/scripts/juiz_capture.py` (lido nesta sessão pela primeira vez): confirma por leitura
  direta do código que o script **nunca decide sozinho capturar** — só corre com `--mode`
  explícito passado por quem o invoca (mobile/web/referencia) e falha honestamente
  (`ok:false` + `motivo_falha`) sem nunca travar/ficar mudo. A decisão de "esta tarefa é visual ou
  não" vive inteiramente na camada de chamada (protocolo do `juiz-revisor`), não neste script —
  confirma que não há bug de captura automática a travar tarefas de infra.
- `git log --oneline -- <ambos os relatórios>`: `0c3eb17` e `437d3c1`, nenhum commit novo desde
  então — ninguém tocou nisto entretanto.

Conclusão (3ª vez): **sem novidade, sem regressão, nada para corrigir.** A causa real continua a
ser o lock de concorrência do executor (já corrigido), nunca a captura visual. Não commitei nada
de código — só este parágrafo de reconfirmação, para o loop parar de reenviar a mesma hipótese já
respondida duas vezes com prova mecânica.
