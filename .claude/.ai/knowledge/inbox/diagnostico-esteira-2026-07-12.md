---
id: diagnostico-esteira-2026-07-12
tipo: diagnostico
origem: [MODO PROTECÇÃO TOTAL — missão read-only, ordem do Danilo 2026-07-12 tarde]
zona: verde (só leitura, nada corrigido)
---

# Diagnóstico — 5 ordens mortas com nota vazia (2026-07-12)

**Regra seguida:** 100% leitura. Nenhum processo morto, nenhum ficheiro editado, nenhum
serviço reiniciado. Tudo abaixo é PROVA lida do PC + da VPS (SSH read-only, `cat`/`grep`/`tail`/`ls`).

---

## 1. CAUSA-RAIZ de hoje

**Não há UMA causa — há duas, e a premissa "5/5 nota vazia" está só parcialmente certa.**
Das 5 ordens, só **3** (`c287`, `a837`, `b049`) fecharam `travada` com `nota:` genuinamente
vazia. `6188` fechou `travada` **com nota real** (faltou um ficheiro de relatório prometido).
`29b9` fechou **`aprovada`** — sucesso — e o `nota:` vazio aí é comportamento normal
(o script só escreve `nota` no ramo CORRIGIR; sucesso nunca escreve nota).

### Causa A — prova direta: a conta Claude Code no PC bateu no limite de sessão (`b049`)
`ordem-20260712111931-b049.saida.txt` (60 bytes, escrito 13:21 UTC) contém, literalmente:

```
You've hit your session limit · resets 5pm (Europe/London)
```

Isto é o `claude.exe -p` a devolver a mensagem de rate-limit da CLI em vez de trabalhar. O
`carteiro.log` confirma: `13:21:52 respondida (tentativa 5)` → **sem** aviso `SAIDA VAZIA`
(porque tecnicamente não é vazio, são 60 bytes) → `13:22:05` log de veredito **em branco**
(nenhuma linha `VEREDITO:` encontrada) → `nota` fica `""`. O juiz (`pc-judge`, mesma conta,
mesmo PC) muito provavelmente bateu no mesmo limite ao tentar avaliar, por isso não devolveu
`VEREDITO:` parseável. **Prova de recuperação:** o log mostra o sistema a voltar a produzir
vereditos reais (`APROVADA`, `CORRIGIR: ...`) a partir de `15:55:4x UTC` em diante — compatível
com o reset "5pm Europe/London" mencionado na própria mensagem (~16:00 UTC, com alguma folga).

### Causa B — timeout de tarefa grande demais (`c287`, provável em `a837`)
`c287` e `a837` são pedidos **enormes**, auto-referenciais ("redesenhar toda a arquitetura de
encadeamento", "Fase 0 do Plano Mestre: matar processos + limpar fila + consertar vigia + criar
hook + disparar 2 tarefas"), cada um com 4 passos distintos. Isto bate ponto-por-ponto com a
lição já documentada `wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md`: o
executor só imprime no FIM (`--output-format text`); se a tarefa não cabe em 900s/40 turnos/$10
Opus, o `timeout` mata a meio → 0 bytes → `⚠️ SAIDA VAZIA` (confirmado no log para **ambas** as
tentativas finais de `c287` 10:33 e `a837` 13:17) → o juiz não tem o que avaliar → `nota` vazia.
`a837` falhou às 13:17, mesmos minutos em que a conta entrou em rate-limit — não dá para
separar 100% timeout-por-tamanho de já-estar-a-ficar-sem-quota nesse caso específico, mas o
formato da tarefa por si só já a coloca no perfil "grande demais para uma tentativa".

### O fio condutor real
As 5 ordens foram pedidas seguidas em <3h (08:24, 10:04, 10:15, 11:04, 11:19), todas a pedir
"conserta a própria esteira de orquestração" em tarefas gigantes de 4 passos, cada uma com até
5 tentativas × até 900s × modelo Opus. Isto **consumiu o orçamento de sessão da conta Claude Code
do PC** durante a tarde — o que explica tanto os timeouts genuínos (tarefa grande demais) como o
rate-limit final (`b049`). Não foi falta de espaço em disco (só 12–14 GB livres nessa altura,
mas nunca chegou a bloquear — a "Not enough disk space" de ontem já tinha sido resolvida pela
limpeza de disco desta manhã, ver `missao-completa-2026-07-12.md` Parte 1).

**Bug mecânico exposto por isto:** quando o juiz não devolve uma linha `VEREDITO:` — seja por
rate-limit, timeout, ou qualquer outra falha do juiz — o `carteiro.sh` grava `nota: ""` sem
distinguir a causa. Rate-limit, timeout-por-tamanho e "juiz confuso" ficam **indistinguíveis**
olhando só para a fila — foi por isto que o Danilo não conseguiu ver a causa sem esta
investigação.

---

## 2. Inventário da esteira (como É, hoje)

**Cadeia:** `campainha.sh` (inotifywait, event-driven, serviço `orq-campainha`, systemd
`Restart=always`) → deteta ficheiro novo em `/opt/data/cortex-brain/orquestracao/` (=
`/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/` no host) → corre `carteiro.sh` →
`pc_exec()` (`docker exec -u hermes … timeout 900 pc-loop "<tarefa>"`) → `pc-loop` faz SSH
`hermes@PC` (via `tailscale nc`, ponte) → `run-claude-loop.cmd --b64stdin` no PC → decodifica
base64 de STDIN para `%TEMP%\bora_loop_task.txt` → `claude.exe -p --model opus
--dangerously-skip-permissions --max-turns 40 --max-budget-usd 10 --output-format text <
ficheiro` → stdout volta pelo SSH → `carteiro.sh` grava em `<id>.saida.txt` → `pc_judge()`
(mesmo mecanismo, `run-claude-judge.cmd`, Haiku, `--max-turns 3 --max-budget-usd 1`, tools
desligadas) → extrai linha `VEREDITO:` → `APROVADA` fecha, senão volta a `aberta` (até 5
tentativas) → `hermes-hook-conclusao.sh` (deployado em `/usr/local/bin/`, **atualizado hoje às
11:50** pela própria ordem 6188) decide o próximo passo e só manda Telegram em 2 casos.

**Onde vai a saída:** só para o `carteiro.log` (VPS) e para `<id>.saida.txt` (fila, VPS). **No
PC não fica log nenhum** — nem do `.cmd`, nem do `claude.exe`. `%TEMP%\bora_loop_task.txt` é
reescrito a cada chamada (mesmo nome fixo) e foi apagado hoje de manhã pela limpeza de disco da
missão — por isso não há vestígio dele agora, mesmo sabendo (pelo lado da VPS) que correu várias
vezes com sucesso hoje (`6188` e `29b9` devolveram texto real e detalhado, com PIDs e serials de
dispositivo concretos — prova de execução real, não fantasma).

**Lock contra 2 execuções em simultâneo:** sim, dois níveis — `flock` no `carteiro.sh` (VPS,
`/root/orquestracao/.carteiro.lock`) e implicitamente o `timeout 900` por tentativa. **Não há**
lock equivalente no lado do PC contra dois `claude.exe -p` do loop a correr ao mesmo tempo — mas
como o `carteiro.sh` só chama `pc_exec` sequencialmente (dentro do próprio `flock`), isto nunca
acontece na prática, a menos que dois carteiros escapem ao lock (não visto no log de hoje).

---

## 3. Proposta de visibilidade (SÓ PROPOSTA — nada aplicado)

Hoje, zero. As execuções correm 100% headless — nada aparece em nenhum terminal aberto do
Danilo, nem no PC nem na VPS.

Duas peças, sem custo de implementar:
1. **Já existe e funciona hoje:** `ssh … "tail -f /root/orquestracao/carteiro.log"` na VPS dá
   quase-tempo-real das transições de estado (`aberta`→`respondida`→`VEREDITO`). É a vista mais
   barata e já pronta — só falta o Danilo saber que pode fazer isto.
2. **Proposta nova (PC):** adicionar ao `run-claude-loop.cmd`, na linha do `%CLAUDE_EXE%`, um
   `tee` para um ficheiro fixo (ex. `%TEMP%\bora_loop_live.log`), para o Danilo correr
   `Get-Content -Wait "$env:TEMP\bora_loop_live.log"` no PC. **Ressalva honesta:**
   `--output-format text` só emite no FIM — um `tee` não mostraria progresso a meio da tarefa,
   só o resultado final no mesmo instante em que já chega à VPS. Para progresso real a meio
   seria preciso trocar para `--output-format stream-json` (mudança maior, fora deste
   diagnóstico) — mencionar ao Danilo como trade-off, não implementar sem "vai".
3. **Proposta no `carteiro.sh`:** quando `veredito` não contiver `VEREDITO:`, gravar em `nota`
   uma causa explícita em vez de string vazia — ex. detectar a substring literal `"session
   limit"` / `"rate limit"` na saída do executor/juiz e escrever `nota: 🚫 CONTA CLAUDE EM
   RATE-LIMIT (ver saida.txt)` em vez de `""`. Separa de forma imediata, olhando só para a fila,
   rate-limit vs. timeout-por-tarefa-grande vs. juiz-confuso.

---

## 4. Outros problemas encontrados (fora do escopo do pedido, mas relevantes)

- **Cron a mais a bater na campainha, contra o próprio desenho event-driven documentado:**
  `DEPLOY.md` diz explicitamente que a campainha é `inotify`, não polling. Mas hoje há **5 crons
  adicionais** a disparar a cada 5–10 min (`hermes-evolution-trigger.sh`,
  `hermes-carteiro-vigia.sh`, `hermes-e2e-vigia.sh`, `hermes-aprovador-vermelho.sh`, além do
  fallback horário `orq-fallback` já documentado) — o `carteiro.log` das 15:55–17:30 mostra
  `"outro carteiro a correr — saio"` a cada 2 segundos, ou seja, vários crons a colidir contra o
  `flock` continuamente. Inofensivo (o lock protege), mas é ruído puro e contradiz o desenho
  "event-driven" — vale revisitar se todos os 5 crons precisam mesmo desta cadência.
- **`hermes-carteiro-vigia.sh` não tem log próprio** (`/root/hermes-carteiro-vigia.log` não
  existe) — não dá para confirmar que ele *alguma vez* correu com sucesso hoje, só que não havia
  nada para reviver (campainha nunca morreu). Sem log, fica impossível provar que o vigia
  "funciona de verdade" (era exatamente o que a ordem `a837` pedia para testar, e não chegou a
  fazer por falta de saída).
- **`b049` pediu explicitamente "NAO disparar nenhuma tarefa nova… sistema deve ficar PARADO"** —
  mas como `b049` acabou `travada` (rate-limit), essa instrução nunca chegou a ser executada. Os
  5 crons automáticos continuaram a criar ordens novas (`evol`, `aprv`, `e2e`) a cada poucos
  minutos, ignorando por completo a intenção de "parar tudo" — porque não existe nenhum
  mecanismo que ligue "há uma ordem tipo stop-limpo pendente" a "os crons de auto-geração de
  ordens pausam". É um buraco de desenho: um "PARAR TUDO" pedido dentro de uma ordem não tem
  como se propagar aos geradores de ordens, que vivem em crons independentes.
- **Nenhum dos 3 problemas acima é o que causou as 5 mortes de hoje** — são achados adicionais
  encontrados a investigar o resto da esteira, não a causa-raiz.
- Espaço em disco do PC **não foi a causa**: por volta das 10:33–13:22 já tinha sido limpo
  (Parte 1 da missão desta manhã, 14.39→19.42 GB); o "Not enough disk space" que o Danilo viu
  ontem já estava resolvido antes destas 5 ordens.
- RAM do PC: não foi possível confirmar via `Get-CimInstance Win32_OperatingSystem` nesta sessão
  (comando devolveu vazio) — não bloqueou o diagnóstico porque a causa já ficou provada por
  outras vias, mas fica como gap de instrumentação a repetir se precisar no futuro.

---

## 5. Lições existentes — bate com o padrão de hoje?

- `wiki/licoes/ponte-loop-nao-devolve-output.md` (o argumento base64 grande partia o `.cmd`):
  **não é isto.** O `--b64stdin` já está em produção (confirmado no `.cmd` de 10/07 e no `pc-loop`
  a funcionar hoje para `6188`/`29b9` com texto real). Essa causa já está fechada.
- `wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md`: **bate exatamente** com
  `c287` e provavelmente `a837` — tarefa grande demais para o orçamento de uma tentativa,
  timeout a 900s, saída vazia, sem ser ponte morta.
- **Causa nova, não documentada ainda:** rate-limit de sessão da conta Claude Code do PC
  (`b049`) — consumido por repetir 5× tarefas gigantes em <3h. Vale nova lição
  `wiki/licoes/conta-claude-code-bate-rate-limit-esgotada-por-retries.md` (proposta de título,
  não escrita — cabe ao `bibliotecario-cerebro` gravar após handoff).

---

DIAGNOSTICO COMPLETO — causa: 3 das 5 ordens mortas por tarefas-gigantes-auto-referenciais
esgotarem o orçamento de tentativa (timeout 900s, lição já conhecida) e a conta Claude Code do
PC ter batido rate-limit de sessão a meio da tarde (prova literal em `b049.saida.txt`); as
outras 2 (`6188` travada-com-nota-real, `29b9` aprovada) não são falhas de "nota vazia" — é
comportamento normal do script.
