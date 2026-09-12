# BLOCO D1+D2 — juiz com caminho mutilado + executor VPS rc=97 (2026-09-05)

Missão: fechar os dois bugs de infra do loop autónomo que ficaram por resolver da sessão
`tudo-04-09-noite` (ver `.claude/.ai/reports/TUDO-04-09-NOITE-2026-09-04.md`, ordem de
prioridade #1 e #4; memória `pc-e-vps-tem-de-ser-simetricos.md`).

---

## BUG 1 — juiz recebe caminho mutilado ("Users\danil\..." sem o "C:")

### Causa raiz encontrada (NÃO é o problema `--b64stdin` de argumentos grandes — esse já
estava resolvido desde 2026-08-01/2026-08-16)

O ficheiro **realmente em produção** não é o que está commitado em
`.claude/.ai/hermes/orquestrador-carteiro/deploy/` deste repo (esse é uma cópia "master"
desatualizada, ainda com `$Proj = 'C:\Users\danil\Desktop\projetosflutter\bora_app'`, caminho
antigo de antes da mudança de PC). O juiz que corre de facto é chamado por
`pc-judge-novo` (no container Hermes, `/opt/data/.local/bin/pc-judge-novo`) →
`danil@100.75.79.116` (esta PC, via Tailscale) →
`C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\run-claude-judge-novopc.cmd`
→ `juiz-mecanico.ps1` (mesma pasta).

Essa cópia viva já tinha o `$Proj` corrigido a 2026-08-31 ("PC NOVO... caminho real"), mas
tinha um bug diferente e mais fundo, na secção **(c) "ordem pedia criar/escrever
ficheiro"**: a regex que extrai caminhos de ficheiro do texto da TAREFA era

```
(?<![\w])(?:[A-Za-z0-9_.\-]+[/\\])+[A-Za-z0-9_.\-]+\.[A-Za-z0-9]{1,10}
```

A classe de caracteres `[A-Za-z0-9_.\-]` **não inclui `:`**. Para um caminho absoluto do
Windows como `C:\Users\danil\AppData\Local\Temp\prova-loop-0704.txt`, o `:` quebra o match
e o regex só captura a partir de `Users\danil\...` — a letra da unidade fica de fora. A
seguir, `Join-Path $Proj $pp` colava isso a `C:\BoraLocal\projetosflutter\bora_app`,
produzindo um caminho que nunca existe, e o juiz reprovava trabalho real (é exactamente o
que queimou 8 horas na ordem `9d32`, ver `TUDO-04-09-NOITE-2026-09-04.md` linhas 64-73).

### Prova ANTES do conserto (bug reproduzido ao vivo)

Criei um ficheiro de prova real e um input de juiz idêntico ao formato de produção,
apontando a um caminho absoluto `C:\Users\danil\AppData\Local\Temp\...`:

```
PROVA-JUIZ: [Test-Path Users\danil\AppData\Local\Temp\prova-loop-teste-bloco-d1.txt] -> False
VEREDITO: CORRIGIR: a ordem pedia criar/alterar o ficheiro Users\danil\AppData\Local\Temp\
prova-loop-teste-bloco-d1.txt e ele NAO existe em disco (...)
EXITCODE=2
```

(o ficheiro **existia mesmo** em disco — a prova é que o "C:\" some da linha `Test-Path`.)

### Conserto aplicado

Em **`C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\juiz-mecanico.ps1`**
(a cópia viva) e sincronizado em
**`.claude/.ai/hermes/orquestrador-carteiro/deploy/juiz-mecanico.ps1`** (a master deste
repo, que também ficou com o `$Proj` atualizado para `C:\BoraLocal\projetosflutter\bora_app`):

1. A regex passou a aceitar um prefixo opcional de unidade (`C:\` ou `\\servidor\partilha\`)
   antes do resto do caminho.
2. `Test-Path` passou a usar o caminho **absoluto directamente** quando o caminho extraído
   já é absoluto (`[System.IO.Path]::IsPathRooted`), em vez de sempre colar a `$Proj` via
   `Join-Path` (que não sabe lidar com dois caminhos absolutos).
3. O fallback "espelho do cortex" (`.claude\.ai\knowledge\...`) só se aplica a caminhos
   relativos — não faz sentido para um caminho absoluto fora do repo.

### Prova DEPOIS do conserto (mesma ordem, mesmo ficheiro)

```
PROVA-JUIZ: [Test-Path C:\Users\danil\AppData\Local\Temp\prova-loop-teste-bloco-d1.txt] -> True
PROVA-JUIZ: chao mecanico OK - segue para o juiz textual
EXITCODE=0
```

**APROVADA** — o juiz agora reconhece a prova real sem reabrir a ordem.

### Controlo negativo (garantir que não virou "aprova tudo")

Corri a mesma verificação para um ficheiro que **de facto não existe**
(`prova-loop-INEXISTENTE-xyz123.txt`, apagado antes do teste):

```
PROVA-JUIZ: [Test-Path C:\Users\danil\AppData\Local\Temp\prova-loop-INEXISTENTE-xyz123.txt] -> False
VEREDITO: CORRIGIR: a ordem pedia criar/alterar o ficheiro C:\Users\danil\AppData\Local\Temp\
prova-loop-INEXISTENTE-xyz123.txt e ele NAO existe em disco (...)
EXITCODE=2
```

Continua a reprovar corretamente — e agora **com o caminho completo e correto** na
mensagem (antes dizia só `Users\danil\...`), o que também torna o diagnóstico mais útil
para quem lê o log.

### Nota de risco (não corrigida nesta missão, fora do escopo dos 2 bugs pedidos)

A pasta `deploy/` deste repo é, segundo `DEPLOY.md`, suposta ser a "master" copiada para
produção — mas as cópias vivas em produção evoluíram para variantes `-novopc` /
`-pcnovo-limpo` que nunca foram trazidas de volta para este repo (`run-claude-judge-novopc.cmd`,
`run-claude-loop-novopc.cmd`, `run-claude-loop-pcnovo-limpo.cmd`, `juiz-go.ps1` só existem em
`C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\`, fora de qualquer git). Isto
é uma segunda forma da mesma armadilha "a árvore viva não é o repo" (ver memória
`arvore-viva-do-pc-nao-e-o-repo.md`). Não mexi nisso agora (fora do pedido), mas fica
registado: se uma sessão futura editar só a master do repo, a produção não muda.

---

## BUG 2 — executor da VPS devolve rc=97 desde 2026-07-15

### Causa raiz encontrada

**`rc=97` NÃO é um bug de código — é uma desativação intencional e documentada.**

```
$ ssh root@srv1786862.hstgr.cloud "cat /root/orquestracao/.vps-exec.rc"
97
```

O ficheiro `/home/hermes-exec/.vps-exec-runner.sh` (chamado por
`/root/claude-vps-exec.sh`, que por sua vez é chamado por `carteiro.sh` via `vps_exec()`)
tem, no topo, um comentário do próprio Danilo explicando a decisão
(`ordem-20260715173856-9297`, sessão `voltapc-20260715-1`, 2026-07-15):

> "o token OAuth desta VPS expira a cada ~2h apesar de 'válido 1 ano', exigindo renovação
> manual constante — hoje interrompeu a ordem 01a4 a meio. Danilo decidiu abandonar a VPS
> como executor e voltar à rota exclusiva via ponte SSH ao PC."

O script inteiro foi substituído por:
```bash
echo "[.vps-exec-runner.sh] DESATIVADO por decisao do Danilo (...)" >&2
exit 97
```
— falha rápido e alto, de propósito, para o `carteiro.sh` cair no fallback do PC sem
esperar timeout longo. É exatamente o que faz: `rc=97` propaga-se limpo até
`.vps-exec.rc`.

O token antigo (`/home/hermes-exec/.claude-vps-token`, formato
`export CLAUDE_CODE_OAUTH_TOKEN=...`) ainda existe em disco, mas tem **data de
2026-07-15** (quase 2 meses parado) — dado que o próprio problema era o token expirar
mesmo dentro de horas, este token está morto com certeza.

### Conflito com a ordem de hoje (04/09)

A ordem do Danilo de hoje ("tudo q correr no pc tem q correr na vps... e vise versa") **reverte**
a decisão de 15/07. Para cumprir isso, alguém tem de:

1. **Gerar um token OAuth novo e válido** para o Claude Code CLI como o utilizador
   `hermes-exec` na VPS — isto é feito com `claude setup-token`, que abre um fluxo de
   login (URL + confirmação) que só um humano consegue completar. **Não há forma de
   fazer isto por SSH/script sem um humano.**
2. Ou, alternativa mais robusta a longo prazo: trocar de autenticação OAuth (que expira)
   para `ANTHROPIC_API_KEY` (chave de API, sem expiração de sessão) — confirmei que
   **não existe nenhuma `ANTHROPIC_API_KEY` configurada em lado nenhum da VPS** hoje
   (procurei em `/root/*.env`, `/docker/*/.env`). Isto elimina a causa raiz (expiração),
   mas muda o modelo de custo de "plano já pago" para "cobrado por token" — é uma
   decisão de custo, não só técnica.
3. Depois de qualquer uma das duas, restaurar `.vps-exec-runner.sh` a partir do backup
   `/home/hermes-exec/.vps-exec-runner.sh.bak-voltapc-20260715180154` (conteúdo íntegro,
   confirmado por leitura — só precisa do token novo para voltar a funcionar).

**Não tentei gerar login nem trocar para API key sem confirmação — é exatamente o tipo de
ação (login humano / decisão de custo) que as regras da casa dizem para não fazer sozinho.**

### CONFIRMACAO NECESSARIA

⚠️ Para reabrir a VPS como segunda perna do loop (ordem de hoje, 04/09), preciso que o
Danilo faça UMA das duas coisas — não é dinheiro real de cliente, mas é login/custo, por
isso não avancei sozinho:

- **Opção A (grátis, mais frágil — repete o problema de julho):** login manual —
  `ssh root@srv1786862.hstgr.cloud`, depois `runuser -u hermes-exec -- claude setup-token`,
  seguir o link, colar o código. Confirma quando estiver feito que eu restauro o
  `.vps-exec-runner.sh` e testo.
- **Opção B (mais robusta, tem custo de API):** autorizas-me a criar uma
  `ANTHROPIC_API_KEY` própria para a VPS (console Anthropic) e eu configuro
  `hermes-exec` para a usar em vez de OAuth — sem expiração de 2h, mas cobrado por
  uso em vez do plano fixo.

Sem isto, o `rc=97` **fica como está** (não é um "erro" a esconder — é o kill-switch do
Danilo de 15/07, ainda válido até ele escolher A ou B).

### Prova de que NÃO forcei nem fingi

```
$ ssh root@srv1786862.hstgr.cloud "cat /root/orquestracao/.vps-exec.rc"
97
```
(inalterado — nenhuma tentativa de contornar sem autorização. `.vps-exec-runner.sh` também
inalterado; só foi **lido**, não editado.)

---

## Simetria PC/VPS — estado final

- **PC (juiz):** corrigido e provado (ver BUG 1). A ordem simples de teste passou
  `APROVADA` na cópia viva `hermes-bridge\juiz-mecanico.ps1`.
- **VPS (executor):** **continua bloqueado em rc=97**, causa raiz identificada e
  documentada, mas o desbloqueio exige uma ação humana (login OAuth ou decisão de
  custo de API key) que não posso executar sozinho. Fica marcado como
  **pendente — CONFIRMACAO NECESSARIA**, não como "corrigido".

A simetria completa (algo corre em ambos os lados com sucesso) **não foi alcançada** nesta
sessão porque a VPS depende da ação acima. O lado do PC está pronto para quando isso
acontecer.

## Ficheiros tocados

- `C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge\juiz-mecanico.ps1` (cópia
  viva — conserto real, é o que corre em produção)
- `C:\BoraLocal\projetosflutter\bora_app\.claude\.ai\hermes\orquestrador-carteiro\deploy\juiz-mecanico.ps1`
  (master do repo — sincronizada com o mesmo conserto + `$Proj` atualizado)
- Nenhum ficheiro da VPS foi alterado (só lido, por SSH, para diagnóstico).
