# FECHO — `nunca-mais-travar` + `paridade-auto-vs-manual`
Data: 2026-08-01 · Zona: verde · Via CEO-AI · Relatório de detalhe: `paridade-e-enchente-2026-07-31.md`

---

## A JANELA DE AVARIA (o facto central da noite)

**27/07 → 31/07 — 4 dias**, escondida atrás de uma nota que culpava o tamanho da tarefa.

A 22/07 a ordem `aa42` passou à 1.ª: a CLI vinha do npm global e o caminho fixo do
`run-claude-loop.cmd` resolvia. A **27/07** a app Claude passou a gerir a CLI em
`%APPDATA%\Claude\claude-code\<versão>\` e a pasta npm desapareceu. O `.cmd` abortava com
`exit /b 4`, **0 bytes**, e o `carteiro.sh` escrevia:

> `SAIDA-VAZIA — executor não devolveu texto (tarefa grande demais? dividir em passos menores)`

Ninguém procurou o binário porque a nota culpava o tamanho da tarefa. **Uma nota errada não é
um detalhe cosmético: é um diagnóstico errado que custa dias.** É a lição central desta missão.

---

## VEREDITO DOS INVARIANTES

### I1 — Nenhum achado repetido gera linha nova · ✅ **PROVADO**
Migration `robot_dedup_key_base_normalizado_atualiza_linha_viva`: `robot_dedup_base()` (remove
`-vN`), backfill **só das `nova`** (decisão (c) do Danilo — 0 colisões verificadas antes), e
`robot_create_suggestion` passa a **atualizar a linha viva** (evidência nova, severidade só
escala, `created_at` intocado).

**Prova:** 32 chamadas do mesmo achado com sufixos `-v2`…`-v32` →

| | antes | depois |
|---|---|---|
| linhas criadas | 32 | **1** |
| chave | `…-v32` | forma base |
| evidência | a da 1.ª | atualizada até à **32.ª** |

Origem atacada como mandado (sem regex de sinónimos): `robot-b/index.ts` deixou de entregar
"chaves ocupadas — NÃO repetir" e passa `DEDUP_KEYS_CANONICAS` (18 chaves + `sem-chave`).
Defesa em profundidade: o servidor coage qualquer chave fora do conjunto a `sem-chave`.

### I2 — Ordem ≤ o que o executor aguenta · ✅ **PROVADO**
`LOTE_MAX=8` no `hermes-aprovador-vermelho.sh`. Testado com o código real extraído por `sed`:
`fila=30 → lote=8, sobra=22`. Deployado à VPS, `sha256` VPS == repo, `bash -n` OK.

### I3 — Item já triado nunca reabre o fallback · ✅ **PROVADO AO VIVO**
`reviewed_at` obrigatório ao triar (inclusive Balde B) no agente `aprovador-vermelho`, com o
porquê escrito ao lado. Dry-run na VPS com a fila real:
`count=2, oldest_age=0min — silêncio`. O gatilho que disparava a cada ~40 min está calado.

### I4 — `travada` não-vermelha nunca notifica · ✅ **PROVADO EM PRODUÇÃO**
> Esta secção foi escrita quando a prova ainda era sintética. **Fechada em produção na Ronda
> Final §2** — travada real provocada por `mv` atómico, arquivo escrito, zero Telegram. E lá
> apareceu um furo que esta secção não via: `missao_travada_ou_silencio()` notificava em ambos
> os ramos. O texto abaixo fica como estava, para o Córtex guardar o caminho e não só o destino.
`hermes-hook-conclusao.sh`: continuações esgotadas → linha em `ordens-arquivadas.tsv`
(daily-pulse), **sem Telegram**. Telegram fica reservado a zona vermelha e missão concluída.
Autoteste do hook: **7 OK, 0 falhas**. Endurecido com `mkdir -p` + aviso — sem isso uma pasta
em falta fazia a ordem desaparecer sem rasto (trocar "Telegram a mais" por "esquecimento
silencioso" seria pior).
**Honestidade:** provado por autoteste, **não** por uma travada real provocada em produção.

### I5 — Aprovação → execução automática · ✅ **PROVADO PONTA-A-PONTA**
Era o buraco maior: o caminho **nunca existiu** (todos os leitores de `status='aprovada'` eram
escrita, dedup ou métrica; zero consumidores). 46 linhas paradas desde 19/06, último `aplicada`
a 14/07.

Construído: `approved_queue_watermark()` · `robot_claim_approved(≤8)` com `FOR UPDATE SKIP
LOCKED` · `robot_finish_approved()` · `hermes-consumidor-aprovadas.sh` + cron `*/10`.

**Prova (a que faltava desde a 1.ª mensagem):** item aprovado às 05:42:12 →
cron injetou `ordem-20260801054224-aplic` → executor correu sozinho → ficheiro
`_prova-i5-fecho.txt` com `I5 OK 2026-08-01T05:46:29Z` → sugestão em **`aplicada`**.
**Sem ninguém mandar prompt.**

**As 49 antigas intactas:** 46 `aprovada` (19/06→29/07) + 3 `aprovada-emerson`, zero executadas,
zero em `em_execucao`. `aplicada` subiu 12→13 (só o item de prova).

**Travas confirmadas em produção:** cutoff (watermark=0 com 46 na base) · idempotência (2 claims
concorrentes: A pegou 4, **B pegou 0**; e as tentativas seguintes reclamaram vazio) ·
`aprovada-emerson` excluído (tem ciclo próprio `robot_emerson_decide`/`_close`).

---

## AUTENTICAÇÃO — resolvida

Token em `HKLM`, **108 caracteres** (≠1024, não truncado pelo `setx`). O `hermes` herda-o após
`Restart-Service sshd`. Sonda provada nas **duas direcções**:

- **ok:** devolveu a sentinela `SONDA-AUTH-OK` por corrida real → o executor produz texto.
- **sem_auth:** forçado limpando a variável num contexto de teste → `CLI-SEM-AUTH: …`.
  O estado dispara mesmo; não é carimbo.

> ### ⛔ CORREÇÃO — o furo do `auth status` não se materializou
> Temi (e o Danilo levantou) que `auth status` mentisse com a auth vinda de env var. **Não
> mente** nesta versão: devolve `"loggedIn": true, "authMethod": "oauth_token"`. O bypass que
> pus no preflight é defensivo, não corretivo — mantive-o porque é inócuo (uma auth genuinamente
> má continua apanhada a jusante pela mensagem literal do executor, que é ground truth).

---

## PARIDADE PARTE 2 — implementada

**2.1 Tetos = pausa, não falha.** `EXECUTOR-PAROU` deixa de ser `travada`+Telegram: marca
`pausa_teto: 1`, gera continuação **silenciosa**, e o hook usa teto **generoso**
(`MAX_CONT_PAUSA=8`) em vez de 2. Teto absoluto mantido (backstop contra loop infinito) e
registado quando atingido.

**2.2 O Juiz deixa de matar.** Sem `VEREDITO`, re-tenta-se **só o juiz** (até 3x) — a tarefa
**não volta a correr**. Se falhar na mesma e o executor tiver produzido trabalho: ordem fecha
**`concluida` + `revisao: pendente`**, entra em `revisao-pendente.tsv` (daily-pulse), **zero
Telegram**. Nunca `travada`.

**Provado necessário nesta sessão:** a ordem de prova fez o trabalho todo à 1.ª e mesmo assim
correu **3 vezes** (~4 min cada) porque o juiz não devolvia veredito. Também matou `a1d2` e
`6244` a 22/07.

**2.3 Zona vermelha:** inalterada. Continua a ser a única coisa que pára e chama o Danilo.

### 🔎 Causa-raiz do juiz mudo — encontrada (não é rate-limit nem modelo)
`ordem-…-aplic.veredito.txt` contém:
```
'PONTE' não é reconhecido como um comando interno
'Só' não é reconhecido como um comando interno
```
O prompt do juiz é passado ao `pc-judge` **como argumento cru por cmd.exe**, e as linhas do
próprio prompt são executadas como comandos. O `pc-loop` já usa `--b64stdin`; o `pc-judge` não.
**A correção do transporte do `pc-judge` NÃO foi feita** — ver "por fazer".

---

## PASSO 3 — Trava de segredos: escrita e testada, **por ligar**

`.claude/scripts/protege-segredos.sh` (não em `.claude/hooks/` — essa pasta recusou a escrita;
a Trava a proteger-se, comportamento correto). Bloqueia `sk-ant-oat01-…`, `sk-ant-api…`, e
`CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY` **com valor real**. Não bloqueia o nome sozinho —
senão nem esta missão se documentava.

**4/4 testes:** bloqueia token em conteúdo (exit 2) · bloqueia chave API em comando (exit 2) ·
deixa passar o nome da variável (exit 0) · deixa passar texto normal (exit 0).

**`.claude/settings.json` recusou a edição** (zona protegida — permissão negada, não a forcei).
Diff exacto a aplicar, no array `hooks.PreToolUse`, a seguir ao bloco do `protege-banco.sh`:

```json
    },
    {
      "matcher": "Edit|Write|MultiEdit|Bash|PowerShell",
      "hooks": [
        {
          "type": "command",
          "command": "bash /c/Users/danil/Desktop/projetosflutter/bora_app/.claude/scripts/protege-segredos.sh"
        }
      ]
    }
```

---

---

## RONDA FINAL (2026-08-01, pós-token) — os 3 itens fechados

### 1 · Transporte do `pc-judge` · ✅ FECHADO

> **⛔ CORREÇÃO 5** — o meu diagnóstico anterior ("o prompt do juiz é executado por cmd.exe")
> estava **incompleto e a apontar ao sítio errado**. O `'PONTE'`/`'Só'` é ruído cosmético do
> cabeçalho do `.cmd`. A causa real estava na **linha 10 do `run-claude-judge.cmd`: o MESMO
> caminho npm morto que eu corrigi no executor e esqueci no juiz.** Desde 27/07 o juiz abortava
> sempre em `claude.exe nao encontrado`.
>
> **Agravante que o escondeu:** a mensagem começava por `[juiz]`, e o `clean()` do `carteiro.sh`
> filtra as linhas `^\[juiz\]` — o erro era **apagado antes de chegar ao diagnóstico**. Por isso
> passa agora a emitir `CLI-NAO-ENCONTRADA` (não filtrado).

Corrigido: resolução dinâmica pelo `resolve-claude-exe.ps1` (mesmo helper do executor) ·
erro não-filtrado · suporte `--b64stdin` no `.cmd` e no `pc-judge` (o executor já o usava desde
2026-07-10; o juiz ficou para trás e o prompt dele leva TAREFA + 50 linhas de saída).

**Prova (juiz real, não autoteste):**
- `--b64`: `VEREDITO: CORRIGIR: falta caminho do ficheiro, conteúdo do teste e prova de execução`
- `--b64stdin` com prompt >3KB: `VEREDITO: CORRIGIR: a ordem pedia criar/alterar o ficheiro
  tmp/prova.txt e ele NAO existe em disco` (o chão mecânico verificou o disco)
- Em produção: a ordem de paridade fechou com `VEREDITO: APROVADA` à 1.ª tentativa.

### 2 · I4 com travada REAL em produção · ✅ FECHADO
Encontrei o furo que faltava: `missao_travada_ou_silencio()` notificava em **ambos** os ramos,
independentemente da zona — o meu fix anterior só cobria o hook. Corrigido (história do f523 de
2026-07-13 preservada no comentário, não apagada).

Ordem descartável `ordem-20260801061033-i4test` injetada por **`mv` atómico** já com
`tentativa: 5`. Contraste no mesmo caminho de código:

```
22:54:57  ...aplic:  travada (sem missão) -> Telegram                       ← antes
05:59:43  ...aplic:  travada (sem missão) -> Telegram                       ← antes
06:12:01  ...i4test: travada -> ARQUIVO (daily-pulse). SEM Telegram (I4).   ← depois
```
Linha escrita em `travadas-arquivadas.tsv`. Artefactos de teste arquivados e removidos da fila.

**Ressalva honesta:** provei **arquivo + zero Telegram**. A *continuação* não foi observada neste
caminho — a ordem morre na verificação de teto ANTES de execução, que não passa pelo hook. A
continuação está provada por autoteste (T3), não em produção.

### 3 · Prova comparativa da paridade · ✅ FECHADO
Tarefa idêntica (auditoria multi-passo das Edge Functions) pelos dois caminhos:

| | caminho A (interactivo) | caminho B (ordem pelo loop) |
|---|---|---|
| `total_funcoes` | 53 | **53** ✅ |
| `funcoes_sem_verify_jwt_declarado` | 24 | **24** ✅ |
| `ficheiros_com_verify_jwt` | 0 | 29 |

Os dois números substantivos batem certo. B fechou **`aprovada` à 1.ª tentativa**, sem
continuações, sem travar.

> **⛔ CORREÇÃO 6** — na linha em que divergem, **o loop estava certo e eu errado**: o meu
> comando interactivo procurou `verify_jwt` em `deno.json`/`config.toml`, que não existem, e deu
> 0. O loop deu 29, que fecha certo (53−24=29). A paridade não só se verificou como o caminho
> automático produziu o melhor resultado.

**Nota lateral:** são **53** Edge Functions locais. O `CLAUDE.md` diz 44 e a skill CEO-AI diz
"43 deployed / 38 locais" — ambos **stale**.

---

---

## AUDITORIAS PÓS-FECHO (2026-08-01) — as duas valeram mais que o resto

O Danilo mandou auditar o **padrão**, não o caso. Tinha razão: as duas encontraram bugs vivos.

### Auditoria 1 · O caminho npm morto noutros sítios · 🔴 **HAVIA UM TERCEIRO**

Varridos todos os `.cmd`/`.ps1`/`.sh`/`.py` do repo, do PC (`hermes-bridge`), da VPS
(`/root/orquestracao`, `/usr/local/bin`) e do container (`/opt/data/.local/bin`), ignorando
`.bak`. Resultado:

| ficheiro | estado |
|---|---|
| `run-claude-loop.cmd` | 🟢 corrigido (FASE 1.11) |
| `run-claude-judge.cmd` | 🟢 corrigido (ronda final) |
| **`run-claude.cmd`** (ponte partilhada) | 🔴 **linha 22, caminho npm morto — encontrado agora** |

`run-claude.cmd` **não tem chamador vivo** na cadeia de orquestração (só documentação o
menciona), mas continua invocável à mão e morreria exactamente da mesma forma. Pior: emitia o
erro com o prefixo `[ponte]`, **também filtrado pelo `clean()`** — mesmo mecanismo de
silenciamento do juiz. Corrigido: resolução dinâmica pelo helper partilhado + `CLI-NAO-ENCONTRADA`.

**A lição não é "havia um terceiro" — é que o mesmo bug sobreviveu em 2 sítios durante 4 dias
porque só se corrigiu onde ele doía.** Qualquer invocação do `claude.exe` passa agora pelo mesmo
`resolve-claude-exe.ps1`; havendo um quarto ficheiro no futuro, herda a resolução ou fica órfão
de propósito.

### Auditoria 2 · O `clean()` comia diagnóstico · 🔴 **CONFIRMADO**

O filtro era `grep -vE '^\[ponte\]|^\[loop\]|^\[juiz\]|Permission deny rule|matches no known tool'`
— descartava a **linha inteira** por prefixo. Contagem real do que isso comia:

| prefixo | linhas vivas | quantas são `ERRO` |
|---|---|---|
| `[ponte]` | 2 | **2 / 2** |
| `[juiz]` | 4 | **4 / 4** |
| `[loop]` | 5 | **4 / 5** |

**Um filtro de ruído que comia quase só diagnóstico.** Foi por aqui que o juiz morto passou
4 dias despercebido: o erro `claude.exe nao encontrado` **existia e era emitido** — e era apagado
antes de chegar ao diagnóstico. Mesma classe de bug da nota "tarefa grande demais": esconde a
causa e manda procurar no sítio errado.

Reescrito em `awk`: linha com prefixo de ponte só é descartada **se não contiver `ERRO`**. Os dois
padrões de ruído genuíno (`Permission deny rule`, `matches no known tool`) continuam filtrados.

**Teste:**
```
entrada                                        -> saída
[juiz] ERRO: claude.exe nao encontrado         -> PASSA ✅
[ponte] ERRO: falha a descodificar base64      -> PASSA ✅
[loop] auth via CLAUDE_CODE_OAUTH_TOKEN …      -> filtrado (informativo) ✅
Permission deny rule (.claude): …              -> filtrado ✅
VEREDITO: APROVADA                             -> PASSA ✅
CLI-NAO-ENCONTRADA: …                          -> PASSA ✅
```

### Item 3 · `CLAUDE.md` corrigido
44 → **53** funções locais (contadas 2026-08-01), com a nota de que **24 não declaram
`verify_jwt`** — vale auditar quais deviam ser públicas. A skill CEO-AI continua stale
("43 deployed / 38 locais"): não lhe toquei, exige aprovação do Danilo.

### Item 4 · Backup do `pc-judge`

> **⛔ CORREÇÃO 7** — escrevi que o `pc-judge` tinha ficado **sem backup**. **Falso.** Existe
> `/opt/data/.local/bin/pc-judge.bak-20260717T080751Z` e contém exactamente a versão
> pré-alteração (`run-claude-judge.cmd --b64 $B64`).
>
> O que de facto aconteceu: o `cp` que eu tentei **hoje** falhou com *permission denied* — a
> pasta `/opt/data/.local/bin` não aceita **ficheiros novos**, só sobrescrita dos existentes.
> Concluí daí "não há backup" sem verificar se já existia um. Verificar antes de afirmar era um
> comando; afirmei primeiro.
>
> **Consequência prática:** rollback do `pc-judge` é possível (`cp pc-judge.bak-20260717T080751Z
> pc-judge` — sobrescrita, que é permitida). O que **não** é possível é criar backups novos
> nessa pasta; qualquer alteração futura precisa de guardar a versão anterior noutro sítio.

---

## O QUE FICOU POR FAZER (sem arredondar)

1. **Ligar a Trava de segredos** — o guard está pronto e testado (4/4); falta colar o diff acima
   em `.claude/settings.json` (a permissão negou-me a edição e não forcei).
   **Até lá não há proteção nenhuma contra colar o token num ficheiro.**
2. **Continuação por teto em produção** — o `pausa_teto` + `MAX_CONT_PAUSA=8` estão
   implementados e passam no autoteste T3, mas **nunca vi uma continuação nascer de um
   `EXECUTOR-PAROU` real**. Só acontece quando uma tarefa estourar mesmo os 150 turnos/$25.
3. **Backups novos em `/opt/data/.local/bin`** — a pasta só permite sobrescrita, não criação.
   Rollback do `pc-judge` está garantido (`.bak-20260717T080751Z`), mas alterações futuras
   precisam de guardar a versão anterior fora dessa pasta.
4. **Skill CEO-AI stale** — continua a dizer "43 deployed / 38 locais". O `CLAUDE.md` já está
   corrigido (53); a skill exige aprovação do Danilo, não lhe toquei.
5. **24 Edge Functions sem `verify_jwt`** — movido para entrada PRÓPRIA por ordem do Danilo
   (é segurança, não resto desta missão): `SEGURANCA-edge-functions-sem-verify-jwt-2026-08-01.md`.

---

## LIMITAÇÕES CONHECIDAS (registadas para não se perderem)

**L1 · `/opt/data/.local/bin` não aceita ficheiros novos.** Só permite sobrescrever os que já
existem. Consequência prática: **não dá para criar backups novos nessa pasta**. O rollback do
`pc-judge` está garantido pelo `.bak-20260717T080751Z` que já lá estava, mas **qualquer alteração
futura a `pc-loop`/`pc-judge` tem de guardar a versão anterior noutro sítio** (ex.: copiar para
`/root/orquestracao/` na VPS antes de escrever). Descoberto quando o `cp` de hoje falhou com
*permission denied* — e foi daí que tirei a conclusão errada da ⛔ CORREÇÃO 7.

**L2 · A continuação por teto real nunca foi vista nascer.** O `pausa_teto: 1` +
`MAX_CONT_PAUSA=8` estão implementados e passam no autoteste T3 do hook, mas só se provam a sério
quando uma tarefa estourar **genuinamente** os 150 turnos / $25 e o parser emitir
`EXECUTOR-PAROU`. Não é forçável com um fixture honesto: injetar a linha à mão testaria o meu
regex, não o caminho. **Fica como "implementado, por provar" até acontecer sozinho** — e quando
acontecer, o log do carteiro dirá `PAUSA-POR-TETO -> criei continuação n/8`.

---

## AUDITORIA 1 — nota de rodapé (correção de uma correção)

Uma pesquisa que tinha ficado em background devolveu resultados **depois** de eu ter escrito a
auditoria. Trouxe `login.cmd` na lista, e eu anunciei que a conclusão "sem chamador vivo" estava
errada. **Estava a corrigir-me a mais:** o `login.cmd` só menciona o `run-claude.cmd` num
comentário `REM`. A conclusão original mantém-se — `run-claude.cmd` não tem chamador vivo.

**Mas a pesquisa apanhou uma coisa nova, de outra forma:** `login.cmd:15` invoca `claude` **nu**,
a contar com o PATH. E o PATH não tem `claude` — nem sequer para o `danil` (`where claude` não
devolve nada; a CLI vive em `%APPDATA%\Claude\claude-code\<versão>\` sem shim). Ou seja, o
`login.cmd` também está partido, pelo mesmo motivo de fundo e sem o saber. **Não o corrigi** —
está fora do que foi mandado auditar e é o script que o Danilo usa para autenticar à mão; mexer
nele sem ele saber seria mudar o caminho de recuperação por baixo dos pés.
5. **Backlog de 49 aprovações em quarentena** — intacto de propósito. Precisa de re-triagem
   humana: 8x paridade-admin de 01-02/07, 9x infra_cron desde 19/06, 4x "reatribuir pedidos
   presos" (perigoso — os pedidos de hoje são outros), 1x teste-circuito.
6. **`/ctx doctor` e `/ctx stats`** — não corridos: os tools MCP do context-mode não estão
   expostos nesta sessão.
7. **Nada commitado.** As 5 migrations `PROPOSTA_*` de TVDE continuam fora, por caminho
   explícito, como ordenado.

---

## ERROS DESTA MISSÃO (mantidos, não apagados)

> **⛔ CORREÇÃO 1** — escrevi "a CLI do Claude Code não está instalada no PC". **Falso.** O
> Danilo derrubou-o com um facto que eu tinha à frente: a sessão que escreveu o relatório *era*
> o Claude Code nesse PC. Falhava a **resolução** (isolamento de perfil `danil` vs `hermes`),
> não a existência.

> **⛔ CORREÇÃO 2** — dei o furo do `auth status` como provável. Não se materializou nesta
> versão da CLI (ver acima).

> **⛔ CORREÇÃO 3** — a 1.ª sonda lia `claude auth status` por SSH direto: fonte e ambiente
> diferentes do executor. Furo apanhado pelo Danilo. Reescrita para provar por **corrida real**
> pelo caminho do executor.

> **⛔ CORREÇÃO 4** — o meu 1.º fixture de dedup deu "0 linhas" e quase o dei como prova: era
> `robot_suggestions_ciclo_fkey`, não o dedup. Um "0" pode ser a coisa certa pela razão errada.

---

## Ficheiros tocados

**Repo:** `carteiro.sh` · `run-claude-loop.cmd` · `resolve-claude-exe.ps1` (novo) ·
`hermes-hook-conclusao.sh` · `hermes-aprovador-vermelho.sh` · `hermes-consumidor-aprovadas.sh`
(novo) · `hermes-sonda-auth.sh` (novo) · `protege-segredos.sh` (novo) ·
`supabase/functions/robot-b/index.ts` · `.claude/agents/aprovador-vermelho.md` ·
2 ficheiros de missão em `orquestracao/missoes/`

**VPS** (hash verificado == repo): `carteiro.sh` · `hermes-hook-conclusao.sh` ·
`hermes-aprovador-vermelho.sh` · `hermes-consumidor-aprovadas.sh` · `hermes-sonda-auth.sh` ·
2 crons novos (`*/10` consumidor, `25 7` sonda)

**PC:** `run-claude-loop.cmd` · `bora-live-parser.ps1` · `resolve-claude-exe.ps1`

**DB:** 2 migrations aplicadas (dedup base + consumidor com cutoff/claim)
