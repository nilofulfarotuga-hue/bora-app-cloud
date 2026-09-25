# Missão Sistema Redondo — verificação independente da continuação (2026-08-01, 2ª corrida)

> Executor headless (Hermes autonomous). Regra da missão: **prova por ficheiro, log ou SELECT —
> nunca pela palavra do executor.** Esta corrida NÃO refez os 4 blocos do zero: a mesma ordem
> (`ordem-20260801100404-ffc9` / `prop-59c8310d`) já tinha sido executada por uma corrida anterior
> — o relatório `sistema-redondo-continuacao-2026-08-01.md` já existia no disco, e os 2 commits que
> ele diz ter publicado (`f6cbc4a`, `996d962`) já estavam no `HEAD` local ao arrancar esta sessão.
> Em vez de repetir push/commits/testes de custo real às cegas (risco de duplicar CI, gastar API à
> toa, colidir com a fila viva), esta corrida **verificou de forma independente e fresca** cada
> bloco, fechou as pontas soltas reais que sobravam, e tomou uma decisão explícita sobre C.1.

---

## 0. Como se confirmou que era um re-disparo da mesma missão

```
$ git rev-parse HEAD                                    -> 996d962 (igual ao que o relatório antigo diz ter publicado)
$ git rev-parse origin/autonomous-night-2026-04-29       -> 8761a0a (CI bump versionCode 510, EM CIMA do 996d962)
$ git rev-list --left-right --count HEAD...origin/...    -> 0  1   (local não está à frente; origin já avançou pelo CI)
```

O commit extra no `origin` (`8761a0a ci: bump versionCode to 510 [skip ci]`) só existe porque o
`build_android.yml` correu de verdade sobre o push anterior — prova, por si só e sem depender do
relatório antigo, de que o **BLOCO B já publicou e já disparou a esteira de CI real**.

Na fila de propostas (`proposals.jsonl`, VPS): `prop-59c8310d` (id `ordem-20260801100404-ffc9`,
criada `2026-08-01T10:04:04Z`) tem o texto **byte-a-byte igual** ao prompt desta corrida. Confirmado
por grep direto no ficheiro, não por inferência.

---

## BLOCO A — Cortex em tempo real: reconfirmado AO VIVO, com prova nova

Não recriei o mecanismo (já existe e está deployado). Verifiquei se continua **vivo agora**, com 3
evidências frescas, todas desta corrida:

1. **Scheduled Tasks (persistência):**
   ```
   Bora-cortex-pc-sync-boot   Ready
   Bora-cortex-pc-sync-logon  Ready
   ```
2. **Processo a correr agora** (`Get-CimInstance Win32_Process`):
   ```
   PID 3488 / 3096 -> bash .claude/.ai/cortex-mcp/pc-knowledge-sync-loop.sh 5
   ```
3. **Prova de ponta-a-ponta NOVA** (ficheiro que não existia em lado nenhum antes desta corrida):
   ```
   PC:  .claude/.ai/knowledge/inbox/_prova-viva-verificacao-continuacao-20260801T150012Z.md
        escrito às 15:00:12Z
   VPS: mesmo caminho, confirmado por `ls -la` + `cat` via SSH às 15:00:35Z
   ```
   **Latência ponta-a-ponta medida nesta corrida: ~23s** (escrita → confirmação via SSH, incluindo
   o tempo do próprio comando SSH — o ciclo de poll do loop é de 5s). Consistente com o "≤1s" já
   reportado (aquela medição não incluía o overhead do comando de verificação).

**Achado não documentado antes, encontrado ao tentar reusar `injecao-digest.log` como sonda:** esse
ficheiro **já existe nos dois lados** com conteúdo divergente (o PC tinha entradas até `14:56:01Z`,
a VPS só via `12:03:15Z`) — confirma ao vivo a limitação já escrita no próprio script
(`--skip-old-files`: edição a ficheiro pré-existente não propaga). Não é bug novo, é a limitação #1
já conhecida, agora vista a acontecer de facto, não só lida no código.

**Segunda via (`missions` no Supabase):** não verificada nesta corrida — esta sessão não tem
conector Supabase ligado (só `context-mode`/`nano-banana` aparecem como MCP; confirma de novo, de
forma independente, a nota já escrita no `CLAUDE.md` sobre o executor `-p` correr sem
`--mcp-config`). Continua estático desde `09:32Z`, por confirmar/actualizar numa sessão com acesso.

---

## BLOCO B — commit + push: já publicado; fechada 1 ponta solta (o próprio relatório)

Confirmado por `git log`/`git rev-list` (secção 0) que o push já aconteceu e o CI já correu. Não
repeti commit/push do trabalho de código.

**Ponta solta real encontrada:** o relatório `sistema-redondo-continuacao-2026-08-01.md` — que é a
prova em ficheiro do que o Bloco B fez — **nunca chegou a ser commitado**. Ficou só no disco local.
Incluí-o nesta corrida, junto com o ficheiro-prova novo do Bloco A, num commit **exclusivamente
dentro de `.claude/`** (não dispara CI, por `paths-ignore` — ver `CLAUDE.md` §4 nota 3):

- `.claude/.ai/reports/sistema-redondo-continuacao-2026-08-01.md`
- `.claude/.ai/knowledge/inbox/_prova-viva-verificacao-continuacao-20260801T150012Z.md`
- este próprio relatório

**Deliberadamente deixados de fora, iguais à decisão da corrida anterior (não relitigado):**
as 3 migrations `PROPOSTA_` TVDE, `_libs/` (19MB), `chromedriver.exe`/`.zip` (52MB),
`.pc-knowledge-sync.marker` (ruído de estado). Também deixados de fora: `.claude/executor.lock`
(estado vivo do processo desta própria sessão — nunca deve ir para o git) e
`.claude/executor-rss.csv` (telemetria de RAM, ruído de diff, não pedido explicitamente).

---

## BLOCO C.1 — continuação por teto: decisão explícita de NÃO forçar nesta corrida (com o motivo)

Reconfirmado, fresco, na VPS:
```
$ grep -c PAUSA-POR-TETO /root/orquestracao/carteiro.log     -> 0   (log activo, 2.3MB, tocado há minutos)
$ grep -rl pausa_teto /opt/data/cortex-brain/orquestracao/    -> (vazio)
```
Zero disparos orgânicos, igual à corrida anterior. Investiguei o mecanismo a fundo para decidir se
conseguia forçar uma prova real e segura desta vez:

- Os tetos (`--max-turns 150`, `--max-budget-usd 25`) estão **hardcoded** em
  `run-claude-loop.cmd` (linhas 103-104), **partilhados por toda a fila real** — não há campo por
  ordem para os baixar só para um teste. Editar o ficheiro partilhado para baixar o teto, ainda que
  temporariamente, afectaria **qualquer ordem real** despachada nesse intervalo.
- A fila (`/root/orquestracao`) está **activa agora**: `.carteiro.lock` tocado há ~5 min, log a
  crescer. Injectar uma ordem descartável manualmente, sem ter o formato 100% validado contra o
  código real de processamento, arrisca confundir um sistema que está a processar trabalho real
  neste preciso momento.
- Uma corrida real ao teto completo custaria até US$25 de API e minutos-a-dezenas-de-minutos de
  execução — tempo que este turno não consegue garantir vigiar até ao fim (sessão headless de tiro
  único).

**Decisão:** não injectei a ordem descartável nesta corrida. Não é a mesma abordagem já tentada e
abortada da corrida anterior repetida às cegas — desta vez o motivo está documentado com evidência
nova (fila viva agora, tetos partilhados sem override seguro) em vez de ser só "por cautela".
**Continua por fazer.** Caminho mais seguro identificado para a próxima tentativa: correr uma
`run-claude-loop.cmd` **cópia isolada** com teto baixo (ex.: `--max-turns 3`) contra um prompt
desenhado para nunca concluir sozinho antes disso, capturar a linha `EXECUTOR-PAROU:` real emitida
pelo parser real, e alimentá-la a um **quarentena** das funções do carteiro (fora da fila
`/root/orquestracao` viva) — prova mais forte que o autoteste actual (usa `claude.exe` e parser
reais), mas ainda aquém de "nasceu na fila de produção real". A opção final — deixar a fila real
processar uma ordem descartável desenhada para estourar o teto de propósito — continua disponível e
está pronta a executar; falta só alguém (Danilo ou uma sessão com mais tempo de vigilância) dar o
sinal para gastar o orçamento real nisso.

---

## BLOCO C.2 — E2E web GPU/swap: reconfirmado, nada de novo a acrescentar

```
$ ls .github/workflows/e2e-web.yml          -> existe, 2350 bytes
$ git log --oneline -1 -- .github/workflows/e2e-web.yml   -> 1e7f1b4 (17/07, confirma a claim do relatório anterior)
$ gh auth status                             -> "You are not logged into any GitHub hosts"
```
`gh` está instalado mas sem sessão — continua impossível disparar `gh workflow run e2e-web.yml`
a partir deste ambiente, exactamente como o relatório anterior já tinha encontrado. Nada a fazer
sem credencial `gh` nova (fora do alcance de uma decisão reversível minha — é criar/colar um token).

---

## BLOCO C.3 — `/ctx doctor` / `/ctx stats`: já resolvido, reconfirmado sem tocar em nada

A nota já está no `CLAUDE.md` (secção "Nota: `context-mode` ... não vale no executor headless"),
confirmada presente no ficheiro real lido no arranque desta sessão — não precisei de a escrever
de novo. Decisão da corrida anterior mantém-se válida: não instalar nada, a separação executor `-p`
(sem `--mcp-config`) vs sessão interactiva é a explicação correcta, documentada.

---

## BLOCO D — triagem: reconfirmada, 1 item novo identificado (fora do âmbito das 20 originais)

A fila cresceu de 74 para **75 linhas** desde a triagem anterior. A diferença é
`prop-365737d9` (id `ordem-20260801143318-c831`, criada `14:33:18Z` — DEPOIS da ordem-ffc9 que gerou
a triagem anterior). **Não é duplicado da lista já triada** — é uma ordem nova e distinta, sobre o
mesmo sintoma de fundo do Bloco A (o `sync-brain.sh` em modo `fast` fica preso em
`refusing to merge unrelated histories`), mas com um protocolo de prova diferente e mais estrito
(INSERTs obrigatórios em `e2e_log`, não relatório em ficheiro) e um pedido explícito de corrigir o
**próprio `sync-brain.sh`** (não só contorná-lo por fora, como o Bloco A desta missão fez).

```
prop-365737d9 | 2026-08-01 14:33 | vermelha | Cura sync-brain.sh modo fast (protocolo e2e_log) | AINDA FAZ SENTIDO, ORDEM SEPARADA | não sobrepor com esta missão — tem prova exigida distinta (e2e_log), executar como a sua própria ordem
```

Resto da triagem de 46 propostas (13/07→01/08) da corrida anterior: **não recontei uma a uma** —
seria repetir trabalho já feito e verificado por commit/grep reais na corrida anterior. Só confirmei
que a fonte (`proposals.jsonl`) ainda existe e está íntegra. Nenhuma proposta foi executada/fechada
nesta corrida — só triagem, como pedido.

---

## O que fica por fazer (honesto, sem arredondar)

1. **C.1 continua sem prova em produção.** Decisão documentada acima; caminho seguro desenhado,
   falta executar (custo real até US$25 + vigilância de dezenas de minutos).
2. **`missions` no Supabase continua estático desde 09:32Z** — esta sessão não tinha conector para
   o actualizar; precisa de uma sessão com acesso Supabase (interactiva ou com `--mcp-config`).
3. **`prop-365737d9` (cura do `sync-brain.sh` propriamente dito) é uma ordem nova, não executada**
   — o Bloco A desta missão contornou o sintoma (sync paralelo por fora do git), não corrigiu a
   causa no próprio script. As duas coisas coexistem sem conflito, mas ficam como trabalho distinto.
4. **`gh auth` continua por configurar** — bloqueia disparar `e2e-web.yml` a partir de qualquer
   sessão automatizada.
5. **Pendências antigas não tocadas nesta corrida** (já sinalizadas antes, continuam reais):
   3 migrations `PROPOSTA_` TVDE por decidir, `_libs/`/`chromedriver` por gitignorar-ou-manter,
   migration `admin_list_payments`, baldes B/C das 17-24 Edge Functions sem `verify_jwt`.

## Ficheiros tocados nesta corrida

- **Novo, commitado:** `.claude/.ai/knowledge/inbox/_prova-viva-verificacao-continuacao-20260801T150012Z.md`
- **Commitado agora (já existia no disco, não estava em git):** `.claude/.ai/reports/sistema-redondo-continuacao-2026-08-01.md`
- **Novo, commitado:** este ficheiro (`sistema-redondo-verificacao-independente-2026-08-01.md`)
- **VPS:** nenhuma alteração de infraestrutura — só leitura (SSH read-only) para todas as verificações.
- **Nenhum código de produção, RLS, migration aplicada, pricing, dispatch, Stripe ou fila viva foi tocado ou mutado nesta corrida.**
