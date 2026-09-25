# Dois bugs do loop fechados — pré-voo de RAM + caminho de volta da zona vermelha (2026-08-01, tarde)

Nada foi commitado (instrução do Danilo). Tudo foi **deployado** para as cópias de execução.

---

## BUG 1 — o pré-voo de RAM media a coisa errada e com limiar inventado

### O que estava mal
`run-claude-loop.cmd` lia `Win32_OperatingSystem.FreePhysicalMemory` e travava abaixo de **800 MB**.

- **Métrica**: no Windows a memória *free* é mantida baixa de propósito (o SO prefere páginas na
  standby list a servir de cache). A pergunta "cabe mais um processo?" responde-se com
  **Available** (`\Memory\Available MBytes` = free + zero + standby) — o número que o Gestor de
  Tarefas mostra como "Disponível".
- **Limiar**: 800 MB nunca saiu de medição nenhuma.

**Custo real**: `ordem-20260801100404-ffc9-aprovado` recusada com *"769MB livres"* — e um executor
completou um ciclo inteiro (23 turnos, $1.16) nessas mesmas condições às 12:13 do mesmo dia.

### Medição feita (não estimada)
| facto | valor |
|---|---|
| RAM total do PC | 3902 MB |
| Commit limit / headroom típico | 12007 MB / ~3600–4400 MB |
| **Pico REAL de um executor** | **340 MB working set · 328 MB private** (medido, `.claude/executor-rss.csv`) |
| Sessões CLI do Danilo abertas durante a prova | 3 CLI + 12 processos Claude Desktop |

O "executor pede ~600 MB" do comentário antigo estava errado; e o pico de 1002 MB que se via em
`Get-Process claude` era de um **renderer do Claude Desktop** (Electron, também chamado `Claude.exe`),
não de um executor.

### O que passou a existir
- **`deploy/ram-preflight.ps1`** — lê `Win32_PerfRawData_PerfOS_Memory` (mesmos contadores de
  `\Memory\*` mas **sem nomes localizados** — neste PC o Windows está em PT). Dois testes com
  significados diferentes:
  - **duro (commit)**: headroom de commit < necessário → a alocação pode **falhar** de verdade;
  - **brando (available)**: abaixo do piso → o processo ainda arranca mas a máquina **pagina**.
  Pisos: `avail ≥ 300 MB` (baixo de propósito) e `commit_headroom ≥ private_medido + 500 MB`.
  Overrides por `LOOP_MIN_AVAIL_MB` / `LOOP_MIN_COMMIT_MB` sem editar código.
- **`deploy/executor-rss-sampler.ps1`** — grava o pico real de cada execução em
  `.claude/executor-rss.csv`. O gate usa o **máximo das últimas 20** corridas, com o default a
  servir de **piso** (a medição só pode SUBIR a exigência, nunca baixá-la — senão uma ordem leve
  baixava o gate para todas as seguintes).

### Prova (com as sessões do Danilo abertas)
| caso | resultado |
|---|---|
| A · condições reais de hoje (avail=345, headroom=3533) | `OK` exit=0 — **passa** |
| B · piso de available forçado a 5000 MB | `BLOCK motivo=available-baixa` exit=7 |
| C · piso de commit forçado a 99999 MB | `BLOCK motivo=commit-headroom` exit=7 (o teste duro corre primeiro) |
| D · override por env `LOOP_MIN_AVAIL_MB` | `BLOCK` exit=7 |
| E · métrica antiga no mesmo instante | Free=351 MB → **bloquearia** (falso-negativo) |

Em produção, duas corridas reais passaram com `avail=355` e `avail=714` — a primeira teria sido
recusada pelo gate antigo.

> Nota honesta sobre a premissa: neste PC *Free* e *Available* andam próximos (351/330, 365/375,
> 738/618). A métrica passou a ser a correcta, mas o falso-negativo veio **esmagadoramente do
> limiar de 800 MB contra um executor de 340 MB**, não do desvio entre as duas métricas.

### Defeito encontrado pelo caminho
`%MYPID%` no `run-claude-loop.cmd` **não é o dono do ciclo**: em cmd.exe, `for /f ('comando')` corre
o comando num `cmd.exe` intermédio (`%COMSPEC% /c`), logo o `ParentProcessId` que o powershell vê é
esse processo transitório, que morre logo a seguir. O sampler seguia descendentes desse PID e nunca
via nada. Passou a identificar o executor pela **linha de comando** (`--append-system-prompt` +
`--max-budget-usd`, que as sessões interactivas não têm).
**`%MYPID%` também é o dono do `executor.lock` — ficou por rever, fora do âmbito desta correcção.**

Segundo defeito: `start /B` a partir de um `.cmd` corrido por SSH é morto quando o comando remoto
termina — o sampler nunca chegava ao seu próprio fim para escrever. Quem grava a linha do CSV passou
a ser o `.cmd` (síncrono, chega sempre ao fim); o sampler só deixa o pico corrente num ficheiro de estado.

---

## BUG 2 — ordem despromovida não tinha caminho de volta

`ordem-20260801100404-ffc9-aprovado-chat` foi devolvida a `zona_vermelha` pelo carteiro no pickup e
**nenhum "vai" do Danilo conseguia lá chegar**. Duas causas, ambas silenciosas:

- **D1 — formato de id demasiado estreito.** O guard do `porta-vai.sh` era
  `^ordem-[0-9]{14}-[0-9a-fA-F]{4,}$`, que só aceita o id "cru". Metade das ordens reais nasce com
  sufixo (`-aprovado`, `-aprovado-chat`). Qualquer "vai" caía em `vai-invalido`. O aviso do Telegram
  mandava responder `vai <id>` com um id que o próprio guard recusava.
- **D2 — o "vai" era gravado num campo que ninguém lê.** A rotina escrevia `autorizado_por` +
  `autorizado_em`; `grep -c 'autorizado_por[^_]' carteiro.sh` = **0**. O carteiro só conhece duas
  portas: `vai: sim` (linha 681) e o par `autorizado_por_admin`+`audit_id` revalidado contra a base
  (linha 670). Mesmo com o id certo, o ciclo seguinte re-avaliava `zona_vermelha(tarefa)` sobre o
  mesmo texto e voltava a fechar: **ping-pong infinito**, não desbloqueio.

### O que passou a existir (`deploy/porta-vai.sh` — que **nem estava no repo**)
- Formato aceita sufixos: `^ordem-[0-9]{14}-[0-9a-fA-F]{4,}(-[A-Za-z0-9]+)*$`.
- **Desambiguação**: id exacto ganha sempre; senão prefixo que case com **exactamente um** ficheiro.
  Prefixo ambíguo é **recusado** com a lista dos candidatos no Telegram. Nunca se escolhe "o primeiro"
  — adivinhar qual ordem o humano quis libertar numa barreira de dinheiro é o erro que a barreira existe
  para impedir.
- Grava **`vai: sim`** (o campo que o carteiro lê de facto), com `autorizado_por`/`autorizado_em` ao lado
  como registo, não como mecanismo. `vai: sim` é escrito **antes** de `estado: aberta`: se morrer a meio,
  o pior caso é uma ordem fechada mas autorizada, nunca aberta sem autorização.
- **Modo CLI** `--vai <id> --origem <texto>` — mesma rotina, mesmas barreiras, para autorização dada
  fora do Telegram. A origem é gravada tal como é: o `e2e_log` nunca regista "telegram" a mentir.
- Barreiras intactas: chat_id do Danilo, mensagem exactamente `vai <token>`, ficheiro tem de existir e
  estar em `zona_vermelha` **neste instante**, backup antes de escrever, tudo registado em `e2e_log`.
  `zona_vermelha()` no `carteiro.sh` **não foi tocada**.

### Prova
**Caminho Telegram** (log sintético, fila de teste, offset de produção intocado em 1385635):

| mensagem | resultado |
|---|---|
| `chat=999999` → `vai …-aprovado-chat` | `REJEITADO: chat nao autorizado` |
| Danilo → `vai ordem-20260801100404-ffc9` | `AMBIGUO` — casa com as duas irmãs, **nenhuma libertada** |
| Danilo → `vai ordem-20260801100404-ffc9-aprovado-chat` | `DESTRAVADA … (vai: sim)` — a irmã ficou fechada |

**Ordem real libertada** (`--vai … --origem danilo-sessao-claude-2026-08-01`):
```
estado: aberta
vai: sim
autorizado_por: danilo-sessao-claude-2026-08-01
autorizado_em: 2026-08-01T11:32:57Z
```

**Prova de que D2 está mesmo fechado** — reproduzido o teste T3 do carteiro sobre o ficheiro real:
```
zona_vermelha(tarefa) = VERMELHO (o texto continua a bater)
campo vai = [sim]
>>> T3 NAO dispara -> a ordem SEGUE para execucao
```
Ou seja: a barreira continua a classificar vermelho — o que muda é que agora existe uma resposta humana
que ela respeita.

---

## Ficheiros

| ficheiro | repo | cópia de execução |
|---|---|---|
| `run-claude-loop.cmd` | `.claude/.ai/hermes/orquestrador-carteiro/deploy/` | `Desktop\produtividade-ia\hermes-bridge\` |
| `ram-preflight.ps1` (novo) | idem | idem |
| `executor-rss-sampler.ps1` (novo) | idem | idem |
| `porta-vai.sh` (**não existia no repo**) | idem | VPS `/home/hermes-exec/.porta-vai/` (cron `*/2`) |

Hashes conferidos dos dois lados. Backups: `run-claude-loop.cmd.bak_*_pre-ramv2`,
`porta-vai.sh.bak_*_pre-retorno`.

---

## Por fechar (honesto)

1. **`%MYPID%` continua a apontar para o `cmd.exe` transitório** e é o dono do `executor.lock`. Não
   mexi — está fora do âmbito e o lock tem funcionado. Merece uma ordem própria.
2. **A calibração tem `n=1`** (340/328 MB, tarefa leve de 28 s). O CSV enche-se sozinho com as ordens
   reais; até lá o piso de 700 MB private continua a mandar. Rever o número daqui a ~20 corridas.
3. **`ordem-20260801100404-ffc9-aprovado`** (a irmã, com trilho de admin válido) está **`travada`** nas
   5 tentativas — queimou-as antes desta correcção. A gémea agora libertada é que vai fazer o trabalho.
4. `porta-vai.sh` vive fora de `/usr/local/bin` e do cron do root (user `hermes-exec`). Continua assim.
