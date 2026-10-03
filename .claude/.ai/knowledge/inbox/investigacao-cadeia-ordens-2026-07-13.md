---
title: Investigação a fundo — por que as ordens do Claude.ai não executam sozinhas
data: 2026-07-13
autor: Claude Code (sessão interativa real, modo protecção total)
---

# Investigação da cadeia `cortex_nova_ordem` → execução → fecho

## RESUMO EXECUTIVO

A cadeia **NÃO está partida em nenhum elo de infraestrutura** (rede/autenticação/scripts) — todos os
6 elos foram apanhados **AO VIVO, a funcionar**, durante esta investigação: uma ordem real (`abab`)
foi despachada pela VPS, chegou ao PC via SSH, o `run-claude-loop.cmd` arrancou o `claude.exe`
headless, que trabalhou de verdade (24 turns, custo $1.30, escreveu ficheiros e memória) e terminou
com sucesso às 07:35:00 local.

**O problema real está no ELO 6 (retorno da saída) e no ELO 3 (carteiro serial):**

1. **Elo 6 — a ligação SSH não fecha depois do comando terminar.** Depois do `claude.exe` e de
   todos os processos filhos (PowerShell parser, MCP servers) terem saído completamente, a sessão
   `sshd.exe` no PC (PID 11116, aberta às 07:27:40) e a ligação TCP porta 22 **continuaram
   `Established`**, sem nenhum processo filho vivo por baixo. O `carteiro.sh` do lado VPS fica
   bloqueado num `read` de pipe (confirmado via `/proc/<pid>/wchan` = `pipe_read`) à espera de EOF
   que nunca chega dentro do ciclo. É isto que faz uma ordem **executada com sucesso** parecer
   "presa" — o trabalho foi feito, mas o carteiro nunca recebe o sinal de fim.
2. **Elo 3 — o carteiro processa as ordens uma de cada vez, de forma síncrona, sem prioridade.**
   Enquanto está bloqueado à espera da saída de UMA ordem (até ~900s = 15 min de teto), **nenhuma
   outra ordem é tocada** — é por isto que a `233a` (criada às 06:11:49) ficou às moscas em
   `estado: aberta, tentativa: 0` durante mais de 1h20: a `12ec` ocupou o carteiro das 05:57 às
   06:27 (2 tentativas, ambas em timeout/saída-vazia — sintoma do mesmo bug do elo 6), depois a
   `abab` ocupou-o das 06:27:40 até pelo menos 06:38 (ainda a aguardar o `read` no momento em que
   este relatório foi escrito, apesar do trabalho real ter acabado às 06:35:00 UTC).

**CADEIA QUEBRA NO ELO: 6 PORQUE a sessão SSH do Windows (sshd.exe) não fecha/liberta o pipe depois
do `run-claude-loop.cmd` terminar, deixando o `carteiro.sh` da VPS bloqueado num `read` sem EOF —
a ordem foi executada mas nunca é dada como "respondida"; agravado pelo elo 3 (carteiro
estritamente sequencial), que faz uma única ordem lenta bloquear toda a fila atrás dela.**

---

## PARTE 1 — Limpeza (feita nesta sessão)

- **Processos órfãos matados no PC** (pai já morto, confirmado via `Win32_Process.ParentProcessId`
  inexistente, todos anteriores a esta sessão e à execução ao vivo da `abab`):
  - 6 cadeias `cmd.exe → cmd.exe → python.exe → python.exe` nascidas entre 01:23 e 06:27 (heartbeat-
    desktop/limit_watch presos de ciclos anteriores) — 7 raízes + filhos terminados.
  - 1 sessão SSH pendurada em `CloseWait` desde 07:12 (`cmd.exe`/`powershell.exe`/`conhost.exe` sob
    `sshd.exe`, sessão "Services"/0, sem CPU) — provavelmente um health-check anterior que nunca
    fechou a ligação de forma limpa (mesma família de bug do elo 6, só que numa ligação diferente).
  - 2 `scrcpy.exe` órfãos deixados por duas das cadeias acima depois do pai ter sido terminado.
  - **Não tocado:** a sessão interativa desta própria conversa (`claude.exe` PID 10792 e os seus
    MCP), o Claude Desktop app (`claude.exe` PID 7716 e árvore), e a execução ao vivo da ordem
    `abab` (respeitada até terminar sozinha).
- **Locks:** `.carteiro.lock` na VPS (0 bytes) é `flock`-based — não estava órfão, estava
  legitimamente detido pelo `carteiro.sh` (PID 2338408) que realmente estava a trabalhar. Nenhum
  `.lock` órfão encontrado no repo local (`scheduled_tasks.lock`, `.loop-noturno.lock` são de uso
  normal, não fantasma).
- **Spam `-aprv`/`-e2e`/`-evol` arquivado:** a fila já tinha sido quase toda limpa por uma passagem
  anterior desta mesma noite (ordem `abab`, concluída às 07:35 local — ver Parte 2). Restava
  **1 ficheiro** (`ordem-20260712213501-evol.md`, já `estado: aprovada`) fora de `arquivo/` — movido
  para `orquestracao/arquivo/` nesta sessão. `arquivo/` já continha 294 ficheiros arquivados. Os
  crons `hermes-aprovador-vermelho.sh` e `hermes-e2e-vigia.sh` já estavam **desativados** no
  `crontab -l` da VPS (`# DESATIVADO 2026-07-13 protecao-total`).

---

## PARTE 2 — Os 6 elos, um a um, com prova

### Elo 1 — a ordem existe no ficheiro da fila (VPS)
**VIVO.** `docker exec hermes-agent-fvnc-hermes-agent-1 ls /opt/data/cortex-brain/orquestracao/`
confirma `ordem-20260713061149-233a.md` bem formado (`estado: aberta`, `tentativa: 0`, `zona: verde`,
`teto_tentativas: 5`, tarefa completa). Path real: dentro do container, montado em
`/opt/data/cortex-brain/orquestracao/` (o `/root/orquestracao/` no host é só onde vivem os
scripts+logs, não a fila em si).

### Elo 2 — a campainha (inotifywait) está viva e a vigiar essa pasta
**VIVO.** `pgrep -fa inotifywait` devolve o processo a vigiar exatamente
`/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao`. `campainha.log` mostra eventos reais a
disparar (`evento em ordem-...054002-aprv.md -> carteiro`) e o mecanismo de *coalescing*
("coalescido (carteiro há <8s)") a funcionar como desenhado.

### Elo 3 — o carteiro recebeu e tentou processar a ordem
**VIVO mas SERIAL/SÍNCRONO — aqui nasce metade do problema.** `carteiro.log` mostra o carteiro a
processar ordens uma a uma, em sequência estrita: `...054002-aprv` (3 tentativas) → `12ec`
(2 tentativas, ambas com veredito "SAIDA-VAZIA"/"TIMEOUT-900s", terminou `TRAVADA-TIMEOUT` às
06:27:38) → `abab` (arrancou 06:27:40). A `233a`, criada às 06:11:49 — **enquanto a `12ec` ainda
estava na sua 2.ª tentativa** — nunca chegou a ser tocada porque o carteiro só processa 1 ordem de
cada vez e ficou ocupado com `12ec` e depois `abab`. Confirmado com `ps -o etimes` que o processo
`carteiro.sh` (PID 2338408) esteve **bloqueado >20 min** com `wchan=pipe_read`, e que outras 2
instâncias (`2340777`, `2340779`) ficaram em `do_wait` — arrancadas pelo cron/vigia mas incapazes de
avançar porque a instância principal detém o `flock`.

### Elo 4 — a ponte SSH/Tailscale VPS→PC está a FUNCIONAR
**VIVO — não é o suspeito.** O evento log `OpenSSH/Operational` do Windows mostra dezenas de
`Accepted publickey for hermes from 100.120.181.115` ao longo de toda a noite (06:00–07:38,
ritmo ~1/min), cada uma com o par `Accepted`/`Disconnected` limpo — a conta Windows local `hermes`
autentica-se sem falhas com a chave ED25519 `SHA256:SFbliNxSr8jHVteCX9GjAe7KLlGOLTTsMq+RI86z0uU`.
`ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud "echo PONG"` (sentido PC→VPS, chave
dedicada) também respondeu de imediato. A ponte está saudável nos dois sentidos.

### Elo 5 — o `run-claude-loop.cmd` É invocado quando chega uma ordem
**VIVO — confirmado ao vivo, com timestamp exato.** Às 07:27:40 local (= 06:27:40 UTC, **o segundo
exato** em que `carteiro.log` regista `ordem ...abab: aberta (tentativa=0)`), nasceu no PC a árvore
`sshd.exe(11348)→sshd.exe(11116)→cmd.exe(8096)→claude.exe(11596)` + `powershell.exe(11616)` +
`conhost.exe(12200)`, com `claude.exe` a gerar filhos MCP reais (`graphify-mcp.exe`, `node.exe`) —
ou seja, uma execução `claude -p` headless genuína, não uma injeção na janela interativa.
**Isto responde diretamente à pergunta da ordem 4833: o executor de hoje é HEADLESS, não interativo
via automação de teclado.**

### Elo 6 — o `claude -p` executa e escreve o resultado de volta → **AQUI PARTE**
O `claude.exe` da `abab` trabalhou a sério: `bora-live.log` mostra passo a passo as suas ferramentas
(`Bash: ssh ...`, `Edit: memory/project_hermes_bridge_oneway.md`, `Edit: MEMORY.md`) e terminou
`[07:35:00] FIM (turns=24 custo=$1.30...)` com a conclusão correta ("a faxina já tinha sido
executada por uma passagem anterior"). **Às 07:38:57 — mais de 3 minutos depois do FIM — a ligação
TCP da sessão SSH que a transportou continuava `Established`, e o processo `sshd.exe` (11116)
continuava vivo SEM NENHUM processo filho** (`claude.exe`, `powershell.exe`, `conhost.exe` — todos
já tinham saído). Ou seja: **o trabalho terminou, mas o canal SSH que devia devolver o resultado ao
`carteiro.sh` não fechou.** Do lado da VPS, isso significa que o `read` do `carteiro.sh` nunca
recebe EOF dentro do ciclo — a ordem fica indefinidamente em `estado: executando` até um timeout
externo (o mesmo ~900s visto na `12ec`) a declarar "SAIDA-VAZIA" e marcar `TRAVADA-TIMEOUT`, **mesmo
que o trabalho real tenha sido concluído com sucesso segundos ou minutos antes.**

---

## Porque as ordens ficam presas mesmo executadas

Não ficam em "tentativa 0" por a ponte não entregar — ficam presas porque **a entrega chega, o
trabalho corre, mas o sinal de "acabei" não volta**. O padrão observado (`12ec`: 2 tentativas, ambas
"TIMEOUT-900s"/"SAIDA-VAZIA") é a mesma família de sintoma da `abab` ao vivo: o processo remoto
termina, mas o canal SSH não solta o pipe. Cada retentativa repete o mesmo bug, por isso o contador
de tentativas sobe sem nunca produzir um veredito real do Juiz.

## Porque funciona à mão mas não sozinho

Quando o Danilo (ou uma sessão interativa real, como esta) trabalha uma ordem diretamente — editando
o ficheiro da fila ou correndo Claude Code na janela aberta — **não passa pelo caminho SSH
`carteiro→hermes@PC→run-claude-loop.cmd`** que tem o bug do elo 6. É por isso que a `4833` foi
fechada com a nota "executada manualmente por claude.ai (protecao-total 2026-07-13)" e ficou correta,
enquanto o ciclo automático continuava sem conseguir fechar `12ec`/`233a`. **A janela interativa e o
`claude -p` headless são processos completamente diferentes** (perfis Windows diferentes — `danil`
vs `hermes` — e caminhos diferentes) — não competem por lock nem por RAM entre si de forma direta;
competem apenas indiretamente pelos 4GB totais do PC.

---

## O que consertar (proposta concreta)

1. **Elo 6 (prioridade máxima):** garantir fecho limpo do canal SSH no fim do
   `run-claude-loop.cmd`. Candidatos a causa raiz, por ordem de probabilidade:
   - O pipeline `claude.exe | powershell ... bora-live-parser.ps1` no fim do `.cmd` pode deixar um
     handle do `conhost.exe` (consola oculta que o Windows OpenSSH cria para comandos `exec` sem
     pty) aberto por mais tempo do que os processos "visíveis". Testar a remover o `conhost` do
     caminho (ex.: `--% ... 2>&1` já usado, mas experimentar `powershell -NoProfile -Command "... |
     Out-File"` sem `cmd.exe` de permeio, ou envolver tudo num único processo PowerShell em vez de
     `cmd.exe` a invocar `claude.exe` a invocar `powershell.exe`).
   - Adicionar um `exit` explícito e um `[Console]::Out.Flush()` / fecho de stdout no fim do
     `bora-live-parser.ps1`, e confirmar que ele não fica ele próprio à espera de mais input depois
     do EOF do `claude.exe`.
   - No lado do carteiro, adicionar um `timeout` mais curto e explícito ao `ssh ... run-claude-
     loop.cmd` (ex.: `timeout 600 ssh ...`) para não depender só do teto de 900s do Juiz — isto não
     resolve a causa mas limita o dano enquanto a causa não é corrigida.
2. **Elo 3:** o carteiro processar em série é aceitável para não rebentar os 4GB de RAM do PC (isso
   já foi decidido conscientemente — ver `ordem 233a`, que pede precisamente um lock de
   concorrência), **mas falta prioridade/timeout mais agressivo por ordem** para que uma ordem lenta
   ou presa (bug do elo 6) não bloqueie novas ordens por >1h. Sugestão: reduzir o teto efetivo de
   espera por resposta de 900s para algo como 300-400s quando não há sinal de atividade nova no
   `bora-live.log`, e deixar o carteiro **saltar para a próxima ordem** assim que a atual estourar
   esse teto, em vez de ficar preso no `pipe_read`.
3. Nenhuma mudança necessária nos elos 1, 2, 4 e 5 — estão a funcionar corretamente, confirmado ao
   vivo nesta investigação.
4. Achado secundário (não bloqueante agora, mas indício de um bug de deploy passado): ficheiros
   `${AUTH_KEY_FILE}` e `aqui)` na pasta `C:\Users\hermes\` — nomes literais de variável não
   expandida, prova de um script com sintaxe bash (`${VAR}`) que foi corrido em `cmd.exe` (que não
   expande `${}`), provavelmente durante o provisionamento da chave SSH da conta `hermes`. Não
   afeta o funcionamento atual (a chave já está a funcionar), mas vale limpar os 2 ficheiros-lixo e
   rever esse script de deploy se for reutilizado no futuro.

---

**CADEIA QUEBRA NO ELO: 6 PORQUE a sessão SSH do Windows não fecha/liberta o pipe de saída depois do
`run-claude-loop.cmd` terminar, deixando o `carteiro.sh` da VPS bloqueado à espera de EOF que nunca
chega — a ordem é executada com sucesso mas nunca é marcada "respondida" dentro do ciclo (agravado
pelo processamento estritamente serial do elo 3, que deixa novas ordens como a 233a à espera atrás
de uma ordem presa).**
