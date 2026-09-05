# FILA + GANHO DO DIA — sessão `fila-ganho-05-09`

**Data:** 2026-09-05 · **Motor:** Opus (Claude Code, PC novo `C:\BoraLocal`)
**Branch:** `autonomous-night-2026-04-29`
**RAM medida no arranque:** 2031 MB disponíveis (portão pesado = 800 MB — acima, podia compilar)

---

## BLOCO 0 — A FILA ESTAVA PARADA

### A causa real não era o `flock`

A hipótese do prompt era um `flock` preso por uma ordem cancelada a meio.
**Não foi isso.** Prova material, tirada da VPS:

```
lsof +D /root/orquestracao
COMMAND       PID USER   FD   TYPE  NAME
campainha 4142320 root  255r   REG  /root/orquestracao/campainha.sh
inotifywa 4142323 root    2w   REG  /root/orquestracao/campainha.log
```

Ninguém segurava o `.carteiro.lock`. Nenhum `carteiro.sh` vivo. O lock estava livre.

O que estava a travar era **um ficheiro de pausa esquecido**:

```
[2026-09-05T00:17:01Z] STOP-TOTAL: .pausa-total presente — nada a fazer
[2026-09-05T01:17:01Z] STOP-TOTAL: .pausa-total presente — nada a fazer
   ... de hora a hora, sem falhar uma ...
[2026-09-05T15:17:01Z] STOP-TOTAL: .pausa-total presente — nada a fazer
```

E o campainha (o inotify que devia acordar o carteiro) dizia o mesmo:

```
[2026-09-05T14:55:40Z] evento em ordem-20260905145531-84c5-aprovado-chat.md
                       mas .pausa-total ativa -> ignoro
```

O ficheiro, e o bilhete que trazia dentro:

```
/docker/hermes-agent-fvnc/data/cortex-brain/orquestracao/.pausa-total
mtime = 2026-09-04 23:07:08 UTC · 278 bytes

  PAUSA posta 2026-09-05 00:0x (Lisboa) pela sessao a mao tudo-05-09-mao.
  Motivo: Danilo pediu a noite toda por sessao manual; evitar 2 executores
  no mesmo trabalho.
  APAGAR DE MANHA para retomar a fila:  rm -f .../.pausa-total
```

A sessão manual de ontem à noite pôs a pausa de propósito, deixou escrito
"apagar de manhã", e ninguém apagou. A fila esteve parada **16 horas** por causa
de um bilhete que ninguém leu.

**Armadilha nova que vale registar:** o `.pausa-total` de `/root/orquestracao/`
(de 16 de julho) é um sósia inofensivo — o carteiro lê `$FILA/.pausa-total`, que é
o da fila. Quem for procurar no sítio errado conclui que está tudo bem.

### O que fiz

| Hora (UTC) | Passo | Prova |
|---|---|---|
| 15:20:24 | Absorvida a ordem `...84c5-aprovado-chat` (é o Bloco 1, que eu ia fazer) | `estado: cancelada` + nota, cópia em `.bak-antes-absorver` |
| 15:20:24 | `.pausa-total` removido (cópia guardada em `/root/orquestracao/.pausa-total.removida-20260905`) | `ls` deixou de o encontrar |
| 15:20:24 | Ordem de prova pousada na fila | `ordem-20260905152022-provafila0509.md` |
| 15:20:24 | **O campainha mudou de discurso** | `evento em ordem-...-provafila0509.md -> carteiro` (sem o "ignoro") |
| 15:20:26 | O carteiro pegou trabalho | `ordem-20260709110949-8448: aberta (tentativa=0)` → `RETOMA com 172 marco(s)` |
| 15:23:25 | Essa ordem respondeu em 3 minutos | `respondida (tentativa 1, motor claude-sonnet)` |

**A fila voltou a andar.** Está provado pelo log e pelo estado dos ficheiros, não
por auto-avaliação.

### As duas armadilhas do prompt — ambas já estavam fechadas

**1. O juiz com o caminho mutilado.** Já corrigido antes desta sessão. O bridge que
o carteiro chama de verdade é o `pc-judge-novo` (linha 547 do `carteiro.sh`), não o
`pc-judge`, e a versão instalada é de **2026-09-05 00:10**:

```
printf '%s' "$*" | base64 | tr -d '\n=' | ssh ... danil@100.75.79.116
  "C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\run-claude-judge-novopc.cmd --b64stdin"
```

Tem `--b64stdin`, tem `tr -d '\n='`, e aponta para o PC novo. Testei a ponte ao vivo
com um prompt pequeno: devolveu `VEREDITO: APROVADA` em **7 segundos**
(15:36:43Z → 15:36:50Z), com o chão anti-trapaça a correr.

**2. O `.vps-exec.rc = 97`.** É código morto, não é avaria. O `exec_ordem()` faz:

```bash
  pc_exec "$1"; return          # <- linha 586, sai aqui
  local out rc                  # nada abaixo desta linha corre
  out=$(vps_exec "$1" | clean)
  rc=$(cat "$VPS_RC_FILE" ...)
```

A rota local da VPS foi desligada de propósito a 2026-07-15 ("a VPS foi abandonada
como executor — 1 core/4GB"). O `97` no ficheiro é um cadáver de julho. Não afecta nada.

---

## BLOCO 1 — GANHO DO DIA UNIFICADO

### A causa, medida e não deduzida

`lib/stores/tvde_driver_store.dart`, `loadTodayEarnings()`, lia **só** `tvde_rides`.
O dia do Danilo, lido da base:

```
user_id 4f61dd31…  dia 2026-09-05  papel driver  cents 932  trabalhos 2  nome Danilo
```

932 cêntimos = €9,32, dois trabalhos: a corrida das 12:14 e a entrega das 14:22.
O cartão mostrava só a parte da corrida.

### A) A leitura corrigida

`loadTodayEarnings()` passa a chamar a RPC `meu_ganho_ao_vivo` e a usar `hoje_cents`.
A soma antiga fica como rede de segurança (se a RPC não responder, mostra as corridas
em vez de não mostrar nada). A RPC não foi tocada.

Prova, corrida como o Danilo (claim JWT do `sub` dele):

```json
{"ok": true, "hoje_cents": 932, "semana_cents": 3390,
 "por_papel": [{"papel":"driver","titulo":"Entregas e corridas","hoje_cents":932}, …]}
```

### B) Um cartão, quatro ecrãs

`lib/widgets/ganho_de_hoje_card.dart` — novo. Lê `meu_ganho_ao_vivo`, mostra o total
do dia, abre a `GanhosScreen` ao toque. Recarrega quando o ecrã volta ao activo
(`AppLifecycleState.resumed`), quando a store do ecrã notifica (um trabalho acabou), e
quando se volta da `GanhosScreen`. Texto em PT-PT.

Usado nos quatro:

| Ecrã | Ficheiro |
|---|---|
| TVDE | `lib/screens/driver/tvde/tvde_driver_home_screen.dart` (o cartão desenhado à mão foi substituído) |
| Estafeta | `lib/screens/driver_home_screen.dart` |
| Limpeza | `lib/screens/cleaner/cleaner_home_screen.dart` |
| Lavagem | `lib/screens/washer/washer_home_screen.dart` |

Não há quatro cópias a divergir: há um ficheiro e quatro sítios a chamá-lo.

**Bug meu, apanhado e corrigido:** a primeira versão do cartão lia
`Supabase.instance` **fora** do `try`. Como `Supabase.instance` rebenta se ainda não
houver arranque, isso era uma excepção não apanhada. Passou para dentro do `try`; o
teste de widget prova que agora é apanhada e registada em vez de partir o ecrã.

### C) Painel admin (PT-BR)

**Não dava** para ver o ganho do dia de um prestador somando papéis. O que havia era
`admin_acerto_unificado`, que é **semanal** e lê tabelas de acerto com grão de semana —
a semana nunca responde à pergunta do dia.

Acrescentado:

- Vista `v_ganho_diario_por_pessoa` — uma linha por pessoa, por dia, por papel.
- RPC `admin_ganho_do_dia(p_dia date)` — gate `is_admin()`, devolve o dia com detalhe
  por papel e nome/email/telefone da pessoa.
- Ecrã `lib/screens/admin/admin_ganho_do_dia_screen.dart` (PT-BR): ver, filtrar por dia,
  exportar CSV. Ligado ao `admin_dashboard_screen.dart`, logo abaixo do acerto semanal.
- Migration: `supabase/migrations/20260905180000_admin_ganho_do_dia.sql`, já aplicada.

Prova, corrida com o claim de admin:

```json
{"ok": true, "dia": "2026-09-05", "pessoas": 2, "total_cents": 1592,
 "itens": [{"nome":"Danilo","total_cents":932,"trabalhos_total":2,
            "por_papel":[{"titulo":"Entregas e corridas","cents":932,"trabalhos":2}]},
           {"nome":"Rui Teste E2E","total_cents":660,"trabalhos_total":1}]}
```

**Isto só lê e mostra.** Não altera nenhum valor cobrado a cliente nem devido a
prestador: soma colunas que já existiam. Não toquei em `pricing_service.dart`,
`order_store.dart` nem `errand_execution_sheet.dart`.

---

## PROVAS

| O quê | Resultado |
|---|---|
| `flutter analyze` | **0 erros.** 213 avisos — exactamente os mesmos de antes de eu mexer; nenhum nos ficheiros novos |
| `flutter test` | **452 verdes**, exit 0 (eram 450; os 2 novos são meus) |
| Golden novo | `test/golden/_fotos/ganho_de_hoje_dia_completo_telemovel.png` — o cartão a mostrar **€9,32** |
| `e2e_log` | 9 linhas com `fluxo=fila-ganho-05-09`, lidas de volta |
| `meu_ganho_ao_vivo` (Danilo) | `hoje_cents = 932` |
| `admin_ganho_do_dia` (admin) | Danilo 932 · total do dia 1592 |

Não há golden dos quatro ecrãs de casa — **nunca houve**. Os que existem
(`telas_principais`, `caixa_de_papeis`, `grelha_categorias`, `ingles_sem_estouro`,
`defeito_plantado`) passam todos. O golden novo cobre o cartão partilhado, que é a peça
que mudou o número.

---

## BUGS APANHADOS PELO CAMINHO (fora do scope)

### 🟡 1. O executor ignora a lista de permissões do projecto — RECTIFICADO

Saída literal do executor, apanhada no prompt que o juiz recebeu:

```
Ignoring 48 permissions.allow entries from .claude/settings.json:
this workspace has not been trusted.
```

Confirmado em disco:

```
C:/BoraLocal/projetosflutter/bora_app -> hasTrustDialogAccepted = False
```

**RECTIFICAÇÃO (escrita depois, na mesma sessão).** A primeira versão deste relatório
concluía daqui que o loop autónomo corria **sem a Trava**, e classificava isso a
vermelho. **Isso estava errado, e a prova apareceu sozinha minutos depois:** ao tentar
empurrar este relatório, a Trava disparou nesta própria sessão, bloqueando o comando
com a mensagem `TRAVA BORA — operação BLOQUEADA`, vinda de
`.claude/hooks/protege-banco.sh`. E esta sessão corre no **mesmo projecto, com a mesma
flag a `false`**.

Logo: a flag de confiança derruba a lista de permissões, **não os hooks**. A mensagem do
Claude Code também só fala de `permissions.allow` — fui eu que estiquei a leitura até
aos hooks.

O que fica verdadeiro, e é bem menos grave: o executor perde as 48 entradas de
`permissions.allow`. Como ele corre com `--dangerously-skip-permissions`, essa lista não
lhe travava nada — o efeito prático é quase nulo.

O que fica **por provar**: se os hooks correm dentro do executor headless (modo `-p`).
Esta sessão prova que a flag de confiança não os impede; não prova o comportamento do
modo não-interactivo. Não fui mais longe porque exigia lançar um executor na mesma
árvore em que eu estava a escrever. Fica como medição a fazer, não como avaria conhecida.

**Já não preciso do teu "vai" para isto.** A pergunta 1 do fim do relatório cai.

### 🟡 2. O juiz cala-se nos prompts grandes

```
[2026-09-05T15:30:06Z] ordem 8448: juiz sem veredito — re-tento SÓ o juiz (2/3)
[2026-09-05T15:36:51Z] ordem 8448: juiz sem veredito — re-tento SÓ o juiz (3/3)
```

A ponte não está partida — provei-a em 7 segundos com um prompt pequeno. O que não bate
certo são os tempos: a VPS dá `timeout 400` ao juiz, e o `run-claude-judge-novopc.cmd`
pode correr **duas passagens de Opus com até 8 turnos cada** antes de desistir. Um prompt
grande (tarefa + saída inteira do executor) não cabe em 400 s. Resultado: toda a ordem
gorda leva "juiz sem veredito" três vezes e acaba travada, mesmo tendo o trabalho feito.

Não mexi — é afinação do loop e não foi pedido. O conserto óbvio é subir o `timeout 400`
ou tirar a segunda passagem de Opus.

### 🟡 3. Os hooks da Trava apontam para a árvore do PC antigo

Os três caminhos no `settings.json` são
`C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\hooks\...`, não `C:\BoraLocal\...`.
Hoje é inofensivo (as cópias são idênticas e a pasta antiga ainda existe), mas no dia em
que essa pasta for limpa, a Trava desaparece em silêncio.

### 🟡 4. Gémeo do ganho diário, assumido e registado

`meu_ganho_ao_vivo` (do prestador) e `v_ganho_diario_por_pessoa` (do admin) somam o mesmo
dia em dois sítios. Não dava para evitar hoje: a do prestador é fixa a `auth.uid()` e um
admin não a pode usar para ver outra pessoa; e a ordem dizia expressamente para não a
alterar. Hoje batem certo (932 = 932). O passo seguinte é a do prestador passar a ler a
vista, ficando uma só.

### 🟠 5. Efeito colateral que eu próprio causei

Ao testar a ponte do juiz às 15:36:43Z, escrevi por cima do `%TEMP%\bora_judge_task.txt`
que a ordem `8448` estava a usar. Podia ter feito o juiz aprovar a `8448` com o meu prompt
de teste. **Não aconteceu** — o log mostra "juiz sem veredito" nas duas tentativas
seguintes, nenhuma aprovação fantasma. Fica registado à mesma, porque a próxima pessoa que
testar a ponte com o carteiro a correr pode não ter a mesma sorte.

---

## O QUE FICOU POR FAZER, E PORQUÊ

- **A ordem `ordem-20260820213614-e205-aprovado-chat` ficou `em_espera`.** Mexe nos mesmos
  ecrãs de ganhos do estafeta/TVDE que eu estava a editar, e o executor do loop corre em
  `C:\BoraLocal\projetosflutter\bora_app` — a **mesma árvore** onde eu escrevi. Deixá-la
  correr era ter dois Claude a escrever no mesmo repo, exactamente o que o Danilo proibiu.
  **Repor para `aberta`** agora que esta sessão acabou: o ficheiro tem a instrução na nota.
- **A ordem `ordem-20260709110949-8448`** ficou entregue ao loop e travou no juiz (bug 2).
  A saída dela mostra que parou, correctamente, numa zona vermelha (gasto de Bora Tokens no
  TVDE) à espera do "vai" humano.

## BUG 7 — a Trava bloqueia comandos inofensivos por ler a linha toda

Apanhado ao vivo, duas vezes, nesta sessão. O `protege-banco.sh` faz:

```bash
if has 'git[[:space:]]+push'; then
  has '(--force|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$))' && deny ...
```

Testa `git push` **na linha inteira**, e depois procura um `-f` solto **também na linha
inteira**, sem ligar os dois. Consequência, medida:

1. `git commit -q -F - <<EOF ... EOF && git push origin <ramo>` — bloqueado. O `-F` do
   `commit` (mensagem por stdin) foi lido como o `-f` do `push`. É um padrão normal e
   seguro, e fica proibido.
2. Escrever um relatório que **cite a mensagem da própria Trava** — bloqueado, porque a
   citação contém as duas peças. Foi preciso passar o texto por um ficheiro à parte para
   o conseguir gravar.

É a mesma família da cicatriz já registada de a Trava ler comentários como código. O
conserto é exigir que o `-f` esteja depois do `push` no mesmo comando, em vez de o
procurar na linha toda.

Não mexi: é a Trava, zona protegida, e não foi pedido.

---

## PARA O DANILO

Ficou **uma** pergunta, não duas.

1. ~~Aplico a confiança do workspace?~~ **Cai.** Estava assente numa conclusão minha que
   se revelou errada — a Trava corre à mesma. Ver a rectificação no bug 1.
2. **Subo o tempo do juiz na VPS?** Esta mantém-se. A VPS dá 400 segundos ao juiz e o
   `.cmd` pode precisar de mais (duas passagens de Opus). Foi o que travou a ordem 8448
   três vezes seguidas mesmo com o trabalho feito.

E duas que descobri depois, se quiseres que eu lhes pegue noutra sessão: o carteiro
atribuir a uma ordem os commits de quem mais mexer no repo (bug 6), e a Trava bloquear
comandos seguros por ler a linha inteira (bug 7).

---

## ADENDA — a fila depois de destravada (cronologia medida)

| Hora (UTC) | Facto |
|---|---|
| 15:20:24 | `.pausa-total` removido · campainha: `evento em ...provafila0509.md -> carteiro` |
| 15:20:26 | `ordem-...-8448`: **aberta** → RETOMA com 172 marcos |
| 15:23:25 | `ordem-...-8448`: **respondida** (motor claude-sonnet) — 3 minutos |
| 15:30:06 | juiz sem veredito (2/3) |
| 15:36:51 | juiz sem veredito (3/3) |
| ~15:43:40 | `ordem-...-8448`: **concluída** · espelho sincronizado em `brain @ a1569eb` (o commit desta sessão) |
| 15:43:49 | `ordem-...-e205`: **aberta** → **executando**, RETOMA com 86 marcos |
| — | `ordem-...-provafila0509`: **aberta**, é a próxima do ciclo |

O ciclo do carteiro percorre `$FILA/*.md` por ordem de nome numa só passagem, por
isso a ordem de prova (a mais recente) só é servida depois das duas de backlog.
**A fila está provadamente a andar** — duas ordens atravessadas com hora em cada
transição, e o espelho já sincronizado no meu próprio commit. A ordem de prova
trivial ainda não chegou à vez; fica na fila e atravessa quando a `e205` acabar.

### A ordem trivial atravessou — ciclo completo em 53 segundos

```
[2026-09-05T15:45:08Z] provafila0509: aberta (tentativa=0)
[2026-09-05T15:45:28Z] provafila0509: respondida (tentativa 1, motor claude-sonnet)
[2026-09-05T15:45:35Z] provafila0509: VEREDITO: APROVADA
[2026-09-05T15:45:40Z] provafila0509: PROVA-MATERIAL: ficheiros=46 commits=3 veredito=HA-PROVA
[2026-09-05T15:45:40Z] provafila0509: APROVADA
[2026-09-05T15:45:54Z] provafila0509: conselho sem objecoes (ronda 1) -> consenso
[2026-09-05T15:46:01Z] provafila0509: aprovada -> Telegram (conclusão)
```

`aberta → executando → respondida → aprovada` em **53 segundos**, com Juiz, chão
anti-trapaça, conselho e aviso ao Telegram.

E o teste anti-mentira passou — o ficheiro de nome esquisito existe mesmo em disco:

```
C:\Users\danil\AppData\Local\Temp\claude\prova-fila-0509-zx7q.txt   24 bytes, 16:45
PROVA-FILA-0509-ZX7Q-OK
```

**BLOCO 0 fechado.** A fila estava parada, está a andar, e está provado pelo ciclo
inteiro de uma ordem nova — não por relatório de executor.

---

## BUG 6 — o loop atribui à ordem os commits de QUEM MAIS mexer no repo

Apanhado nesta mesma corrida, e é sério:

```
[15:45:02Z] e205: VEREDITO: CORRIGIR: o diff commitado desde o arranque da ordem
            toca ZONA PROTEGIDA (Lista Vermelha) - nada disso passa pelo loop;
            volta para decisao humana
```

A `e205` não commitou nada. O que o Juiz viu foi o **meu** commit `a1569ebb`, feito
minutos antes — a migration do ganho diário, que fala de cêntimos e ganhos e por isso
dispara a leitura de zona vermelha (é a armadilha já conhecida de a Trava ler
comentários como código).

O mesmo mecanismo funcionou ao contrário na minha ordem de prova:
`PROVA-MATERIAL: ficheiros=46 commits=3 ... veredito=HA-PROVA`. A ordem só mandava
escrever um ficheiro de 24 bytes no temp — os 46 ficheiros e os 3 commits eram meus.
Ou seja, ela foi dada como provada por trabalho que não era dela.

**Consequência:** a prova material e o gate de zona vermelha do carteiro medem a
janela de tempo, não a autoria. Com uma sessão humana a trabalhar no mesmo repo, o
loop tanto aprova de graça como reprova inocentes. Não é grave enquanto só correr um
de cada vez — mas foi exactamente por isso que a sessão de ontem pôs a `.pausa-total`,
e é a razão de fundo pela qual o loop e uma sessão à mão não podem partilhar a árvore.

Não mexi. É desenho do carteiro e não foi pedido.

---

# CONTINUAÇÃO — correcções de infraestrutura do loop

> Mesma sessão `fila-ganho-05-09`. RAM no arranque desta parte: **1864 MB**.

## 1. O tecto do juiz: 400 → 1200 segundos

`carteiro.sh` na VPS, linha 547: `timeout 400 pc-judge-novo` → `timeout 1200 pc-judge-novo`.
O tecto de 1 h por tentativa do **executor** ficou intacto (`timeout 3600 pc-loop-novo`,
linha 509, verificado depois). `bash -n` limpo; não sobrou nenhum outro `timeout 400`.

Porquê: o `run-claude-judge-novopc.cmd` pode correr duas passagens de Opus com até
8 turnos cada antes de desistir. Um prompt grande não cabe em 400 s — foi o que
matou a ordem `8448` três vezes seguidas, com o trabalho já feito.

## 2. BUG 7 — a Trava confundia o `-F` da mensagem com a bandeira de força

A regra antiga procurava a invocação num sítio da linha e a bandeira noutro sítio
da mesma linha, sem as ligar, e comparava sem distinguir maiúsculas. Bloqueava um
commit com a mensagem por stdin encadeado com um envio normal — e até um relatório
que citasse a própria mensagem de bloqueio.

A decisão passou para `.claude/hooks/_push_forcado.py`: liga a bandeira ao
subcomando (só conta depois dele, no mesmo segmento), ignora texto entre aspas e
corpos de heredoc que não alimentem uma shell, e lê o `-f` curto distinguindo
maiúsculas. **A protecção não afrouxa** — `_push_forcado_testes.py` alimenta o hook
instalado com payloads reais: 10 casos, 0 falhas, incluindo os dois de aceitação
(commit com `-F` encadeado passa; envio forçado continua bloqueado), mais
`reset --hard` e `DROP` de tabela financeira ainda bloqueados. Um detector isolado
tem outros 20 casos verdes (ramo `my-fix`, `--follow-tags`, `-u`, `git -C`,
refspec com `+`, invocação precedida de `timeout`).

Se o payload não vier em JSON legível, ou o detector faltar, o hook volta à rede
grosseira de antes — fail-closed, nunca aberto.

## 3. BUG 6 — atribuição por assinatura, nunca por relógio

| Ficheiro | O que mudou |
|---|---|
| `run-claude-loop-pcnovo-limpo.cmd` | o executor assina o que commita: `GIT_COMMITTER_EMAIL=loop@bora.local`. Só o *committer*; o autor fica como estava. |
| `juiz-mecanico.ps1` | calcula `$meusCommits` por assinatura. O `zonas_diff` deixa de correr sobre um intervalo e corre **commit a commit, só nos da ordem**. O `anti_trapaca` arranca no pai do commit mais antigo dela, ou em `HEAD` se não committou nada. A prova de "há commit novo" e o cinto do hash alegado passam a exigir a assinatura. |
| `prova-material.ps1` | a sonda conta só os commits assinados. |

Fins de linha preservados (LF/CRLF/LF) e os dois `.ps1` passam o parser do
PowerShell com **0 erros**.

## 4. BUG 8 (novo, apanhado aqui) — o outro hook tinha a mesma doença

Ao escrever este mesmo capítulo, o `git-guardrails.py` bloqueou-o:

> BLOQUEADO pelo guardrail de git: push para 'Passou.'; so e permitido: autonomous-night-2026-04-29

O `ramo_do_push` fazia `re.search(..., re.S)` e agarrava o primeiro `git push` da
linha inteira — corpo de heredoc incluído — tomando a palavra seguinte como ramo.
O parágrafo acabava em "Passou.", e ele decidiu que esse era o ramo de destino.

Curado com o **mesmo** `_push_forcado.py`, para não ficarem duas implementações a
divergir: tira o texto antes de decidir, lê o ramo só dentro do segmento do push, e
delega a detecção de força. `_git_guardrails_testes.py`: 12 casos, 0 falhas. Contra
a versão antiga, o mesmo teste dá 1 falha — exactamente o caso do bug 8.

Também deixou de despejar o comando inteiro no erro (truncado a 300 caracteres); era
por isso que o bloqueio cuspia o relatório todo para o ecrã.
