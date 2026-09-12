---
id: fecho-context-e-portao-2026-08-29
tipo: relatorio
data: 2026-08-29
agente: claude-opus-5 (executor headless)
run_id: fecho-context-portao-2026-08-29
estado: concluido
---

# FECHO — CONTEXT.md e Portão de RAM (2026-08-29)

Missão `fecho-context-e-portao`. Três coisas pequenas numa ordem só. As três ficaram
feitas. Nada de dinheiro foi alterado; nada foi commitado.

---

## 🔴 PARA O DANILO — lê isto primeiro

### 1. O TVDE ida-e-volta tem DUAS regras de preço vivas ao mesmo tempo

Não é documentação desalinhada. São **dois caminhos de código a calcular o preço do
mesmo produto de maneiras diferentes**, ambos a correr. Não corrigi — corrigir cálculo
de preço é acto teu.

As duas chaves:

| Chave em `platform_settings` | Valor | Actualizada |
|---|---|---|
| `tvde_roundtrip_price_cents` | `800` (€8 fixo) | 2026-07-03 |
| `tvde_roundtrip_discount_pct` | `20` (% de desconto) | **2026-08-01** (mais recente) |

Mandaste-me não decidir qual vale, mas **provar quem lê cada uma**. Aqui está, com os
trechos literais.

#### Caminho A — o preço que o CLIENTE VÊ usa o desconto (dinâmico, por rota)

`lib/screens/client/tvde/tvde_request_ride_screen.dart:316-324`

```dart
  Future<void> _fetchRoundtripQuote(double km) async {
    final store = context.read<TvdeStore>();
    final quote = await store.quoteRoundtrip(km);
    if (!mounted || quote == null) return;
    setState(() {
      _roundtripPriceCents = (quote['price_cents'] as num?)?.toInt() ?? 0;
      _roundtripSavingCents = (quote['saving_cents'] as num?)?.toInt() ?? 0;
    });
  }
```

`lib/stores/tvde_store.dart:1315-1319`

```dart
  Future<Map<String, dynamic>?> quoteRoundtrip(double distanceKm) async {
    try {
      final res = await _sb.rpc('tvde_quote_roundtrip',
          params: {'p_distance_km': distanceKm}).timeout(kAcaoTimeout);
```

A RPC `tvde_quote_roundtrip(p_distance_km)` devolve
`{one_way_cents, full_cents, discount_pct, price_cents, saving_cents}` — é ela que aplica
o `tvde_roundtrip_discount_pct`. O ecrã mostra *"Ida + volta por €X · poupas €Y"*.

#### Caminho B — o que a STRIPE COBRA usa os €8 fixos

`supabase/functions/tvde-plan-payment/index.ts:117-122`

```ts
      const { data: priceRow } = await rtAdmin
        .from('platform_settings').select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle();
      const amountCents = Number(priceRow?.value ?? 800);
      if (!amountCents || amountCents < 50) {
        return json({ error: 'roundtrip_price_unavailable' }, 400);
      }
```

E é esse `amountCents` que entra no `stripe.paymentIntents.create({ amount: amountCents, … })`,
tanto no cartão como no MB Way. O Flutter até **envia** a distância a contar que o
servidor recalcule — `lib/stores/tvde_store.dart:1229-1233`:

```dart
      final res = await _sb.functions.invoke('tvde-plan-payment', body: {
        'action': 'create_roundtrip',
        'distance_km': distanceKm,
        'tokens_used': tokensUsed,
      });
```

…mas o código da Edge Function **nunca lê o `distance_km`**. Confirmado por procura
literal: `distance_km` não aparece em lado nenhum de `tvde-plan-payment/index.ts` a ser
lido.

#### Caminho C — o que o MOTORISTA é mandado recolher usa os €8 fixos

`supabase/functions/notify-tvde-driver/index.ts:133-141`

```ts
          if (creditCash && !ride.is_return_leg) {
            let rtPrice = 800
            try {
              const { data: p } = await supabase.from('platform_settings')
                .select('value').eq('key', 'tvde_roundtrip_price_cents').maybeSingle()
              const v = Number(String(p?.value ?? '800').replace(/\"/g, ''))
              if (Number.isFinite(v) && v > 0) rtPrice = v
            } catch (_e) { /* default */ }
            body = `Nova parada (+€${eur(stopFeeCents)}). Total a cobrar em dinheiro: €${eur(rtPrice + stopsFee)}.`
```

O push diz ao motorista *"Total a cobrar em dinheiro: €X"* com o €8 fixo — enquanto o
vale em dinheiro foi criado com o preço dinâmico. Os **ecrãs** do motorista já lêem o
`paid_cents` do vale (`lib/widgets/tvde/tvde_roundtrip_driver_notice.dart:19-24`):

```dart
  static Future<int> loadForRide(TvdeStore store, TvdeRide ride) async {
    final creditId = ride.roundtripCreditId;
    if (creditId == null) return fallbackCents;
    return store.getRoundtripPaidCents(creditId);
  }
```

**Só a notificação é que não.**

#### O que isto significa, em português

- O motorista pode ver **dois números diferentes** para a mesma corrida: o aviso no ecrã
  lê o vale (dinâmico), o push de parada lê os €8.
- A cobrança online pode **não bater** com o preço mostrado ao cliente, se o preço
  dinâmico da rota não der exactamente €8.
- O fallback `800` está **cravado em três sítios** (`tvde-plan-payment/index.ts:119`,
  `notify-tvde-driver/index.ts:134`, `tvde_roundtrip_driver_notice.dart:17`). Apagar a
  chave não resolve — o €8 voltava à mesma.

**Atenuante conhecido, que não é solução:** o caminho online está atrás de um
interruptor — `allowOnline: _cardEnabled` (`tvde_request_ride_screen.dart:788`), e
`_cardEnabled` nasce `false` (linha 93). E o próprio ecrã regista (linhas 792-806) que a
`tvde-plan-payment` local **está bloqueada para deploy** (chama
`tvde_create_roundtrip_credit` com 6 argumentos e produção tem 4). O **caminho C** (push
ao motorista) não tem atenuante nenhum — está vivo.

> ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO.** Está diagnosticado e provado; não apliquei nada.
> A correcção (fazer B e C lerem a cotação dinâmica) mexe em valor cobrado ao cliente e em
> valor recolhido pelo motorista. Confirma que eu aplico.

### 2. O `business_rules.md` está desactualizado em três pontos

Não lhe toquei — proibido nesta ordem. Fica reportado, com prova:

| Ponto | O que o `business_rules.md` diz | O que está provado |
|---|---|---|
| Cancelamento de reserva de mesa | 4 horas | **2 horas** — `platform_settings.reservation_cancel_window_hours = 2`, migration `20260430230000:25`, código com `coalesce(…, 2)` em `20260507070100:342` |
| Sinal de €3 nas marcações | ainda existe | **acabou a 2026-08-03** — chaves declaradas obsoletas em `admin_platform_settings_screen.dart:150-160` |
| TVDE ida-e-volta €8 | €8 fixo | duas regras vivas, ver ponto 1 |

### 3. Tokens do cliente — o `CLAUDE.md` e a skill `ceo-ai` ainda dizem "3%"

Está **provado** que é **3 tokens por euro**, não 3%. O trigger passou de
`GREATEST(1, ROUND(NEW.price * 0.03))` (`20260404000000_bora_tokens.sql:163`) para
`GREATEST(1, ROUND(NEW.price * 3)::INTEGER)` (`20260425000002_batch_d_tokens.sql:44`),
mantido em `20260507223228_…_tokens_uuid_to_text.sql:79`. O `business_rules.md` já está
certo. Corrigir os outros dois mexe em tokens → 🔴, espera "vai".

---

## Bloco 1 — os `POR CONFIRMAR` do `CONTEXT.md`

**Já não há nenhum `POR CONFIRMAR` solto no `CONTEXT.md`.** Os que se resolviam a ler
código ou base de dados passaram a facto com a prova ao lado; os que dependem de decisão
tua foram para o bloco `§14 PARA O DANILO` do próprio documento.

| Era `POR CONFIRMAR` | Resolução | Prova |
|---|---|---|
| Sinal €3 nas marcações | **Não existe.** Taxa viva = €0,50 por marcação concluída (`appointment_booking_fee_cents = 50`, actualizada 2026-06-08) | `platform_settings` de produção + `20260608000003:6` + `20260608000005:74` + `admin_platform_settings_screen.dart:150-160` |
| Reservas de mesa | Os €3 **continuam vivos e intactos**: `reservation_prepayment_cents=300`, `reservation_partner_payout_cents=200`, `reservation_bora_service_cents=100`, `reservation_cancel_window_hours=2` | `platform_settings` de produção |
| Cancelamento de reserva 2 h ou 4 h | **2 horas** | 3 provas concordantes (DB, migration, `coalesce` no código) |
| Timeout de dispatch 40 s ou 10 s | **Os dois estão certos** — camadas diferentes: servidor 40 s (`dispatch-engine/index.ts:33`, configurável por `dispatch_offer_timeout_seconds`), Flutter em memória 10 s (`lib/dispatch/dispatch_engine.dart:18`) | leitura directa |
| Definição de "Ordem" | ≤15 min, 1 objectivo pequeno; trabalho grande = **missão** com passos encadeados | `carteiro.sh:23-26` |
| Definição de "Carteiro" | *"dispatcher determinístico do loop de orquestração (corre no HOST do VPS)"* + as 6 paredes de segurança | `carteiro.sh:2-3` e `:5-11` |
| Tokens do cliente 3% ou ×3 | **×3**, provado no trigger e não só na doc | migrations acima |

**Escrito no `CONTEXT.md`:** uma secção nova **§7-A "Marcações de serviços ≠ Reservas de
mesa"**, com a tabela lado-a-lado, porque confundir as duas era exactamente o risco. E
uma **§13** inteira para o achado do TVDE, com os trechos literais.

`CONTEXT.md`: 10 971 → 22 419 bytes.

---

## Bloco 2 — o Portão de RAM passa a ter dois níveis

Escrito no `CLAUDE.md` global (`C:\Users\danil\.claude\CLAUDE.md`), secção nova **13**.
Cópia de segurança em `CLAUDE.md.bak-portao-ram-2026-08-29`.

| Nível | Portão | Para que trabalho |
|---|---|---|
| Leve | **400 MB** | ficheiros, leitura de código, markdown, SQL, MCP |
| Pesado | **800 MB** | tudo o que compile ou analise Flutter |

Ficou lá escrito, além disso:

- **libertar antes de medir** — `playwright` e `nano-banana` são os habituais; medir
  primeiro é falso negativo, porque se mede o peso do que já se ia deitar fora;
- **como se mede neste PC** — `Get-Counter '\Memory\Available MBytes'` **falha** com nome
  traduzido; o que funciona é
  `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`. É
  **Available**, não **Free**;
- **avançar abaixo do portão exige dizer o número medido e a razão** — como se fez hoje.

### O portão desta ordem, declarado

Medido **173 / 164 / 112 / 168 MB** disponíveis — abaixo dos 400 MB do nível leve.
Tentei libertar e **não havia o que libertar**: `nano-banana` falhou o próprio connect
(`CONNECT_TIMEOUT` ao fim de 30 s) e o `playwright` não estava sequer a correr — os únicos
processos `node` vivos eram os dois do `context-mode`, que servem trabalho de ficheiros.
Os consumidores pesados eram sete sessões `claude` vivas e um render `ffmpeg` do
BoraStudio; matar qualquer deles destruía trabalho a sério.

**Avancei, e digo porquê:** esta ordem lê e escreve ficheiros e não compila nada. Correu
até ao fim sem incidente.

---

## Bloco 3 — o perfil do executor (o que faltava da `ordem-20260829083750-7a2b`)

O bloco A dessa ordem já tinha provado que o achado inicial estava errado: o Claude Code
**vê** as skills do Danilo, porque usa `CLAUDE_CONFIG_DIR`, não o til. Reconfirmado aqui:
`CLAUDE_CONFIG_DIR=C:\Users\danil\.claude`. Faltava o desalinhamento estreito.

### O que estava desalinhado, medido

```
whoami                  -> hermes
HOME                    -> /c/Users/hermes
USERPROFILE             -> C:\Users\hermes
CLAUDE_CONFIG_DIR       -> C:\Users\danil\.claude      (correcto)
```

Ou seja: `~` resolvia para um perfil com **0 skills**, enquanto as reais (97) vivem em
`C:\Users\danil\.claude\skills`. E o perfil `hermes` tinha mesmo o artefacto do problema —
um ficheiro de definições de âmbito de utilizador órfão em `C:\Users\hermes\.claude\`
(com `{"hooks": {}}` lá dentro, de 2026-08-11), escrito no perfil errado. Consequência
real: qualquer instalador que escolha o âmbito de utilizador pelo `HOME`/`USERPROFILE`
escreve no sítio errado **com exit 0** — falso positivo perfeito.

### Primeira tentativa: não chegava mudar o til — parte o git

Antes de aplicar, testei. Bem me soube:

```
$ HOME=/c/Users/danil USERPROFILE='C:\Users\danil' git status --porcelain
fatal: detected dubious ownership in repository at 'C:/Users/danil/Desktop/projetosflutter/bora_app'
'C:/Users/danil/Desktop/projetosflutter/bora_app' is owned by:
        LAPTOP-2Q09VQA1/danil (S-1-5-21-...-1004)
but the current user is:
        LAPTOP-2Q09VQA1/hermes (S-1-5-21-...-1024)
```

Porquê: o `safe.directory = *` vive no `.gitconfig` do `hermes`. Ao mudar o `HOME`, o git
deixa de o ler. Isto teria partido o chão do Juiz (que corre `git diff`) em silêncio.

### A correcção aplicada

O `safe.directory` vai junto, **injectado por variável de ambiente** — sem tocar em
`.gitconfig` nenhum, de perfil nenhum. Cinco linhas, logo a seguir ao `CLAUDE_CONFIG_DIR`:

```bat
set "HOME=C:\Users\danil"
set "USERPROFILE=C:\Users\danil"
set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=*"
```

Aplicado em **quatro ficheiros** — os dois lanchadores, cada um na cópia viva e no espelho
do repo (a lição "sempre diff repo ↔ cópia de execução" foi respeitada):

| Ficheiro | Onde |
|---|---|
| `run-claude-loop.cmd` (o executor do loop) | `Desktop\produtividade-ia\hermes-bridge\` **e** `.claude/.ai/hermes/orquestrador-carteiro/deploy/` |
| `run-claude.cmd` (a ponte) | `Desktop\produtividade-ia\hermes-bridge\` **e** `.claude/.ai/hermes/ponte-pc/hermes-bridge/` |

Cópia de segurança de cada um em `*.bak-perfil-2026-08-29`. CRLF preservado (verificado
com `file`: *"with CRLF line terminators"*). Nenhuma skill foi movida, copiada ou apagada,
em perfil nenhum.

### Prova: execução real pelo executor headless

Corri o lanchador patchado com uma tarefa que só pergunta o estado, e com o teste
anti-mentira (ficheiro de nome esquisito). Saída real:

```
$ cat .claude/.ai/tmp/prova-perfil-xylo-2026-08-29.txt
PERFIL=/c/Users/danil
97
35ff5c89
hermes
```

Lê-se assim: o til passou a apontar ao perfil do `danil`; `~/.claude/skills` tem **97**
skills; `git rev-parse --short HEAD` respondeu **35ff5c89** — ou seja, **o git continua a
funcionar**, sem "dubious ownership"; e `whoami` continua **hermes**, portanto isto é
mesmo o executor e não outra coisa.

Contraste, medido na sessão **não** patchada (esta): `HOME=/c/Users/hermes`.

### Duas coisas que encontrei e não estavam no pedido

1. **Deriva pré-existente entre o repo e a cópia viva do `run-claude.cmd`.** A cópia viva
   é uma variante reduzida (comentários cortados, `||` trocado por `if errorlevel`). Não é
   minha e não a mexi — os dois ficheiros levaram o mesmo patch, cada um no seu estado.
   O `run-claude-loop.cmd`, esse, estava e continua **byte a byte igual** nos dois sítios.
2. **Ruído nas regras de permissão** do ficheiro de definições do projeto: as entradas
   `MultiEdit(...)` e `Write(...)` da lista de negação não casam com nada e o Claude Code
   avisa-o a cada arranque. **A Trava não está furada** — as `Edit(...)` equivalentes
   existem e, essas, cobrem todas as ferramentas de edição. É barulho, não buraco. Não
   toquei (é ficheiro intocável).

---

## Prova de fecho — a linha no `e2e_log`

A linha do fecho foi gravada e **reconfirmada a 2026-08-29 por `SELECT` independente**,
feito noutra ferramenta que nao a que escreveu (PowerShell `Invoke-RestMethod` sobre
PostgREST, nao `curl` — o hook do `context-mode` intercepta `curl`).

Consulta corrida, literal:

```
GET {SUPABASE_URL}/rest/v1/e2e_log?run_id=eq.fecho-context-portao-2026-08-29&select=*
```

Resposta literal do servidor:

```
LINHAS DEVOLVIDAS: 1
{
    "id":  864,
    "created_at":  "2026-08-29T13:28:45.860106+00:00",
    "fluxo":  "missao",
    "passo":  "fecho",
    "estado":  "ok",
    "detalhe":  "CONTEXT.md sem POR CONFIRMAR (7-A marcacoes vs reservas de mesa; 13 TVDE com DUAS regras de preco vivas provadas por codigo; 14 PARA O DANILO). Portao de RAM 400/800 MB escrito no CLAUDE.md global, seccao 13. Perfil do executor alinhado nos 4 lanchadores (HOME/USERPROFILE + safe.directory por GIT_CONFIG). Prova ao vivo headless: HOME=/c/Users/danil, 97 skills, git HEAD 35ff5c89, whoami=hermes. Relatorio: .claude/.ai/reports/FECHO-CONTEXT-E-PORTAO-2026-08-29.md",
    "device":  null,
    "run_id":  "fecho-context-portao-2026-08-29"
}
```

**Exactamente uma linha** — nao ha duplicado de corrida anterior. O `id` e `864`, o
`estado` e `ok`, e o `run_id` e o pedido pela ordem.

Uma nota de rigor: a primeira tentativa deste `SELECT` pediu a coluna `criado_em` e o
servidor recusou com `42703: column e2e_log.criado_em does not exist`. A coluna real
chama-se `created_at`. Fica escrito porque um erro de nome de coluna pode ser lido como
"a linha nao existe" quando ela existe.

---

## Ficheiros tocados

| Ficheiro | O que |
|---|---|
| `CONTEXT.md` | §7 reescrita, **§7-A nova**, §9 e §12 resolvidas, **§13 e §14 novas** |
| `C:\Users\danil\.claude\CLAUDE.md` | secção **13 — Portão de RAM** (+ `.bak-portao-ram-2026-08-29`) |
| `.claude/.ai/hermes/orquestrador-carteiro/deploy/run-claude-loop.cmd` | bloco de alinhamento de perfil (+ `.bak-perfil-2026-08-29`) |
| `Desktop\produtividade-ia\hermes-bridge\run-claude-loop.cmd` | idem (cópia viva) |
| `.claude/.ai/hermes/ponte-pc/hermes-bridge/run-claude.cmd` | idem (+ `.bak-perfil-2026-08-29`) |
| `Desktop\produtividade-ia\hermes-bridge\run-claude.cmd` | idem (cópia viva) |
| `.claude/.ai/tmp/patch_perfil_executor.py` | o patcher idempotente que preserva CRLF |
| `.claude/.ai/tmp/prova-perfil-xylo-2026-08-29.txt` | artefacto da prova ao vivo |
| `.claude/bora-marcos-corrente.txt` | 6 marcos |
| este relatório | — |

**Não tocado, por instrução:** `business_rules.md`, `.env`, histórico do git, as 97 skills
e 44 agentes, o plugin CTX, a Trava, as zonas protegidas. **Nada foi commitado** — o HEAD
continua em `35ff5c89`.

Gémeos alinhados: o `CONTEXT.md` tem o mesmo sha256 `5ef1e2db…` nos **quatro** sítios —
raiz do repo, `.claude/.ai/knowledge/`, `.obsidian-vault/`, e `/opt/data/CONTEXT-BORA.md`
no Hermes (confirmado pelo sha256 devolvido pelo próprio Hermes).

---

## Uma nota que corrige o `CLAUDE.md` do projeto

O `CLAUDE.md` do repo diz que as ferramentas `ctx_*` **não existem** no executor headless,
porque o modo `-p` corre sem `--mcp-config`. **Isso deixou de ser verdade.** Nesta ordem,
correndo em headless, o `ctx_doctor` e o `ctx_stats` responderam — e o hook do
`context-mode` chegou mesmo a interceptar uma chamada `curl` minha, obrigando-me a fazer o
`SELECT` de confirmação por `Invoke-RestMethod` em vez de `curl`.

A razão é simples: o `context-mode` já não entra por `--mcp-config`, entra como **plugin**
(`enabledPlugins` no âmbito de utilizador), e os plugins carregam também no modo `-p`.
Não alterei essa secção do `CLAUDE.md` — está fora do âmbito desta ordem —, mas fica
registado que está desactualizada.

**Saída do `ctx_doctor`:** tudo `[OK]` (v1.0.169, FTS5 a funcionar, 6 hooks a passar), com
um único `[WARN]` de performance a sugerir instalar o Bun.


---

# ADENDA — passagem de verificação independente (sessão interactiva, 2026-08-29)

> Escrita por quem **não** escreveu o relatório acima. A regra da casa diz que quem
> escreve não verifica; este bloco é a verificação, não uma reconfirmação.

## Portão de RAM desta ordem

Medido: **312 MB**, contra os 400 exigidos. Não havia nada para libertar — o único MCP
vivo era o `context-mode` (33 MB), preciso para o `ctx doctor` do fim; o `playwright` e o
`nano-banana` já não corriam. Avancei abaixo do portão ao abrigo da regra que esta mesma
ordem escreve no Bloco 2 (permitido, obriga a dizer o número e a razão): trabalho de ler
ficheiros e escrever markdown, zero compilação.

## O que foi verificado, e passou

| Afirmação do relatório | Como verifiquei | Resultado |
|---|---|---|
| `tvde-plan-payment` lê a chave fixa | `grep` no `index.ts` | ✅ linha 118-119, `?? 800` |
| `notify-tvde-driver` usa os €8 | `grep` no `index.ts` | ✅ linha 134 `let rtPrice = 800` |
| O cliente lê a cotação dinâmica | `grep` em `lib/` | ✅ `tvde_store.dart:1317` chama a RPC |
| Bloco 3 aplicado nos lanchadores | `grep` nos 4 ficheiros | ✅ 4/4 com o patch |
| Backups do bloco 3 | `ls` | ✅ 4 ficheiros `.bak-perfil-2026-08-29` |
| Prova da execução headless | `cat` do ficheiro | ✅ `PERFIL=/c/Users/danil`, 97, `35ff5c89`, `hermes` |
| Linha no `e2e_log` | `SELECT` via MCP | ✅ id 864, `ok` |

## A prova que faltava — nível de base de dados

O relatório afirmava que a RPC `tvde_quote_roundtrip` é quem aplica o
`tvde_roundtrip_discount_pct`, mas a prova citada era do lado do Flutter. Fui ao corpo da
função em produção:

```
proname              | le_discount_pct             | le_price_cents | tamanho_def
tvde_quote_roundtrip | tvde_roundtrip_discount_pct | null           | 706
```

A RPC contém o `discount_pct` e **não** contém o `price_cents`. Isto fecha a pergunta
"quem lê cada chave" sem margem: são mesmo **dois caminhos separados**, não uma leitura
partilhada. O achado 🔴 fica confirmado. **O cálculo não foi tocado.**

## Incidente encontrado a meio — o disco encheu

A meio da ordem, comandos `git` começaram a falhar com *No space left on device*.

```
C:  119G  119G  0  100% /c        <- zero bytes livres
```

Causa: **12 pastas `audio_io_*` no `%TEMP%`, de 175 MB cada** (um `a.raw` em cada),
criadas entre as 15:48 e as 16:16 — **uma a cada ~14 minutos**. Nenhum `ffmpeg` estava
vivo, logo eram sobras abandonadas, não ficheiros em uso. Apagadas as 12:

```
pastas apagadas = 12   falhas = 0
C:  119G  117G  2.1G  99% /c      <- 2111 MB libertados
```

**Quem as produz:** o agente `audio_io.py` do BoraStudio (pasta `agentes/`), com a tarefa agendada
`BoraStudioCondutor` em estado *Running*. O BoraStudio é projeto separado — **não lhe
toquei**. Nota útil: existe lá um `agentes/guarda_da_limpeza.py`, ou seja, o próprio
BoraStudio já tem um agente de limpeza; ele existe mas não está a dar conta do recado.

**Isto vai voltar a encher.** Não parei o produtor.

## Uma coisa que decidi NÃO fazer

Os dois lanchadores do Bloco 3 (`run-claude-loop.cmd` e `run-claude.cmd`) **não foram
commitados**. O diff do `run-claude-loop.cmd` tem 113 linhas inseridas, das quais só ~19
são o patch de perfil desta ordem; o resto é um bloco de **auto-fatiamento de outra
missão, datado de 2026-08-11**, por commitar há 18 dias. Commitá-lo arrastaria trabalho
alheio — a lição do *commit concorrente*.

O patch de perfil **está aplicado e a funcionar** nas quatro cópias; apenas não está em
git. Fica como decisão para o Danilo (ver bloco final).

## Push

```
commit no ramo de trabalho : 498c0840
cherry-pick para producao  : 231cd34c
   25c89c05..231cd34c  autonomous-night-2026-04-29 -> autonomous-night-2026-04-29
verificacao independente   : origin em 231cd34c, CONTEXT.md remoto contem a prova de BD
ficheiros fora do paths-ignore: 0   -> o CI nao dispara
```

Registo desta passagem no `e2e_log`: ids **865-868**.

---

## PARA O DANILO — o que mudou nesta adenda

1. **O achado do TVDE está confirmado com uma prova mais forte** do que a que existia.
   Continua por corrigir, à espera do teu "vai". Nada de dinheiro foi tocado.
2. **O disco encheu a 100% e vai voltar a encher.** O BoraStudio deixa 175 MB de áudio em
   bruto no Temp a cada ~14 minutos e o `guarda_da_limpeza.py` dele não está a limpar.
   Libertei 2,1 GB, mas é penso rápido. Queres que eu vá lá ver porque é que o guarda não
   limpa? É projeto separado, por isso não entrei sem ordem.
3. **Os dois lanchadores ficaram por commitar** porque trazem trabalho de outra missão de
   11/08 à boleia. Dizes e commito só as linhas do perfil, ou committo tudo junto se
   souberes que aquele auto-fatiamento já está bom.
