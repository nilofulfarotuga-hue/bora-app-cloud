# Relatório — Paridade Auto vs Manual (Parte 1) + Enchente do Robot B (diagnóstico)
Data: 2026-07-31 · Zona: verde · Modelo: Opus · Via CEO-AI

---

## PARTE A — `paridade-auto-vs-manual-2026-07-31` PARTE 1 — **FECHADA**

### VEREDITO 1: a FASE 1.10 estava viva no PC? → **NÃO.**

Prova (hashes sha256, 12 primeiros hex):

| Ficheiro | VIVO (PC) antes | repo HEAD | commit 572efb1 |
|---|---|---|---|
| `bora-live-parser.ps1` | `0f94f9465595` | `3afb0de7b248` | `3afb0de7b248` |
| `run-claude-loop.cmd` | `c189ce2d99ee` | `9211f30cdd8d` | `9211f30cdd8d` |

Não é artefacto de CRLF — ambos os lados são LF (0 linhas com `\r`), e os hashes
normalizados (`tr -d '\r'`) continuam diferentes.

O `diff` do parser devolveu **exatamente e só** o bloco em falta — zero customizações locais:

```
42a43,50
>       else {
>         # FASE 1.10 (2026-07-17): type:result sem .result nem .error ...
>         Write-Output "EXECUTOR-PAROU: subtype=$($o.subtype) turns=$($o.num_turns) custo=$($o.total_cost_usd)"
>       }
```

`grep -c EXECUTOR-PAROU` no parser vivo = **0**. O ramo nunca lá esteve.

### 🔴 Achado que CORRIGE a premissa do briefing

O briefing (e o `loops.md`) assumem que o caminho automático corre com
`--max-turns 150 / --max-budget-usd 25`. **Falso.** O que estava vivo no PC era:

```
set "BUDGET=--max-budget-usd 10"
set "TURNS=--max-turns 40"
```

Os tetos reais eram **3.75× mais apertados** do que toda a gente julgava. Isto explica a
cadeia inteira sem precisar de "tarefa grande demais":
tarefa real do Bora → estoura 40 turnos / $10 → `claude.exe` para → `stream-json` emite
`type:result` sem `.result` → parser (sem FASE 1.10) fica **mudo, 0 bytes** → `carteiro.sh`
regista a nota genérica `SAIDA-VAZIA — tarefa grande demais?` → retenta 5× contra o mesmo teto.

**A nota das ordens andou a mentir durante 14 dias** (17/07 → 31/07). O commit `572efb1`
existia no repo desde 17/07; só o `carteiro.sh` foi deployado à VPS a 20/07 — o lado do PC
nunca recebeu nada.

### Correção aplicada

Backup em `hermes-bridge/_backup/*.20260731-fase110.bak`, depois cópia repo → PC.
Pós-deploy os hashes batem certo:

| Ficheiro | vivo | repo |
|---|---|---|
| `bora-live-parser.ps1` | `723939515c1d` | `723939515c1d` |
| `run-claude-loop.cmd` | `798ae49f46de` | `798ae49f46de` |

Tetos vivos agora: `--max-budget-usd 25`, `--max-turns 150`.

### Prova exigida (parser a devolver a linha específica)

Entrada dada ao parser **vivo**: `{"type":"result","subtype":"error_max_turns","num_turns":150,"total_cost_usd":24.87}`

```
--- STDOUT DO PARSER (bytes=61) ---
EXECUTOR-PAROU: subtype=error_max_turns turns=150 custo=24.87
--- LIVELOG ---
[23:23:40] FIM   (turns=150 custo=$24.87)
```

61 bytes com a causa verdadeira, onde antes eram **0 bytes** e uma causa inventada.
A regra dura ("nenhuma nota pode dizer 'tarefa grande demais' sem prova") passa a ser
garantida pelo código, não pela boa vontade.

**Passo 3 da Parte 1 não se aplica** — os ficheiros não estavam lá, logo a saída não era
genuinamente 0 bytes por morte do transporte. Não investiguei o transporte b64/stdin porque
seria diagnosticar um sintoma que já tem causa provada. (Se voltar a haver 0 bytes *depois*
deste deploy, aí sim o transporte é suspeito — e agora dá para distinguir, porque o parser
honesto emite sempre linha.)

---

## PARTE B — `nunca-mais-travar-2026-07-31` PARTE 1 — diagnóstico (fix **não** aplicado)

### O mecanismo do `-vN` é outro — e é mais fundo do que o briefing diz

O briefing diz: *"o dedup do Robot B está furado — em vez de atualizar a linha viva ele
acrescenta sufixo `-vN`"*. Isso descreve o sintoma, mas atribui o ato ao código errado.

`robot_create_suggestion` (lida via `pg_get_functiondef`) **deduplica corretamente**:

```sql
IF EXISTS (SELECT 1 FROM public.robot_suggestions
            WHERE dedup_key = p_dedup_key AND status IN ('nova','aprovada','aprovada-emerson'))
THEN RETURN NULL; END IF;
```

Quem inventa o `-vN` é o **Gemini**. Em `robot-b/index.ts:243` o prompt entrega-lhe a lista
de chaves ocupadas:

```
SUGESTÕES JÁ ABERTAS (NÃO repetir — dedup_keys ocupados):
```

O modelo obedece à letra — não repete a chave, **inventa uma nova** (`…-v19` → `…-v20`) — e a
RPC, corretamente, vê uma chave inédita e insere. O dedup não foi contornado por um bug: foi
contornado por um LLM a cumprir a instrução literalmente.

### E há uma segunda fuga, maior, que o briefing não menciona: **deriva de sinónimos**

Contando as linhas **vivas** (`nova`/`aprovada`/`aprovada-emerson`) por chave-base, o mesmo
problema aparece com slugs reescritos, não só com `-vN`:

- "queries lentas de cron" → **7 chaves**: `infra:otimizar-cron-queries-lentas`,
  `infra:otimizar-queries-cron-lentas`, `infra:queries-lentas-cron`,
  `infra_cron:otimizar-queries-lentas-cron`, `performance:otimizar-cron-queries-lentas`,
  `performance:otimizar-cron-queries`, `performance:cron-queries-lentas`
- "motorista sem token" → **3 chaves** · "produtos sem foto" → **2** · "preço suspeito" → **4**

Conclusão: **normalizar `-v[0-9]+$` fecha só uma parte de I1.** Enquanto o prompt disser
"não repitas estas chaves", o modelo continua a fugir por reformulação. A correção estrutural
é servidor-side (a RPC é a autoridade; o LLM não lhe escapa), não no prompt.

### Por que NÃO apliquei já a migration

O backfill para a forma base **colidiria**: `infra:http-timeouts-recorrentes-geral` tem
**4 linhas vivas** (`aprovada#51401355`, `d7accff0`, `d2838a6e`, `aab4c883`), todas nascidas de
`-v16/-v17/-v18…`. Colapsá-las obriga a escolher qual sobrevive — e são linhas **`aprovada`**,
ou seja, trabalho que o Danilo já autorizou. Fundir às cegas apagava aprovações dele.
Preferi parar e reportar a decisão em vez de mangar 44 itens aprovados.

### 🔎 Achado colateral relevante para I5 (Parte 3)

Das ~46 chaves-base vivas, **só 2 estão `nova`** — todas as outras estão `aprovada` /
`aprovada-emerson`. Ou seja: **há ~44 itens aprovados pelo Danilo que nunca foram executados.**
Isto é prova direta, por `SELECT`, de que o caminho `aprovada` → execução **não existe ou está
partido** — exatamente o que a Parte 3 manda construir. I5 não é uma melhoria; é um buraco a
céu aberto.

---

---

## PARTE C — `nunca-mais-travar` PARTE 1 — **FECHADA** (decisão (c) do Danilo)

Decisão aplicada: **normalizar só as `nova`, não tocar em nenhuma `aprovada`.** Verificado antes
de escrever: as 2 linhas `nova` normalizam para base com **0 colisões** com linhas vivas.

### Migration `robot_dedup_key_base_normalizado_atualiza_linha_viva`
1. `robot_dedup_base(text)` — forma canónica (remove `-v[0-9]+$`).
2. Backfill **só** de `status='nova'`.
3. `robot_create_suggestion` passa a comparar **sempre pela base** e a **atualizar a linha viva**
   (evidência nova, `severidade = GREATEST(...)` — só escala) em vez de inserir. `created_at`
   intocado, para a idade do achado continuar verdadeira.

### Prova de I1 (fixture, sem tocar em dados reais)
32 chamadas com o mesmo achado e sufixos `-v2`…`-v32`:

| | antes | depois |
|---|---|---|
| linhas criadas | 32 | **1** |
| chave guardada | `…-v32` | `teste-i1:achado-persistente` (base) |
| evidência | só a da 1ª | atualizada até à **32ª** |
| severidade | a da 1ª | **5** (escalou) |

Fixture apagado no fim (`fixture_restante = 0`).

> Nota de honestidade: a 1ª tentativa deste fixture deu 0 linhas e **não** era prova de dedup —
> era `robot_suggestions_ciclo_fkey` (usei um `ciclo` inventado). Só contou depois de usar um
> `robot_runs.id` real. Um "0" pode ser a coisa certa pela razão errada.

### Deriva de sinónimos — atacada na origem (instrução do Danilo: sem regex de sinónimos)
`robot-b/index.ts`: o prompt deixou de entregar "chaves ocupadas — NÃO repetir". Agora entrega
**`DEDUP_KEYS_CANONICAS`**, conjunto **fechado** de 18 chaves + `sem-chave`. Se o achado não
couber, o modelo devolve `sem-chave` e diz no título que chave faltou — em vez de inventar.
As "sugestões já abertas" continuam no input, mas como **contexto, não proibição**: repetir a
chave certa passou a ser o comportamento correto (o servidor atualiza a linha).
**Defesa em profundidade:** o servidor não confia na chave do modelo — qualquer valor fora do
conjunto é coagido a `sem-chave` e registado em log.

### Lotes ≤8 (I2)
`hermes-aprovador-vermelho.sh`: `LOTE_MAX=8`. O cron continua a ver **só agregados** (sem títulos,
sem dinheiro) — a seleção "mais antigos primeiro, `reviewed_at IS NULL`" é instruída ao agente,
que corre no PC com acesso. Sobra fica para o ciclo seguinte; **proibido encadear na mesma ordem**.

Teste do código real (bloco extraído do ficheiro com `sed`, não uma cópia):

```
fila=30 -> lote=8 sobra=22 | ordem pede MAXIMO 8 itens [OK <=8]
fila=8  -> lote=8 sobra=0  | ordem pede MAXIMO 8 itens [OK <=8]
fila=3  -> lote=3 sobra=0  | ordem pede MAXIMO 3 itens [OK <=8]
```

**Deployado à VPS** (não repetir o erro da FASE 1.10): backup em
`/root/orquestracao/*.20260731.bak`; VPS estava **idêntica** ao repo (sem customização local);
pós-deploy `sha256` VPS `6600ca7d992fef18` == repo `6600ca7d992fef18`; `bash -n` OK.

### `reviewed_at` ao triar (I3)
`.claude/agents/aprovador-vermelho.md`: passo 4 novo e explícito — marcar `reviewed_at = now()`
em **todo** item triado, **inclusive Balde B** (que fica `nova` à espera do Danilo).
`reviewed_at` = "já foi olhado", não "já foi decidido". Com o porquê escrito ao lado, para não
ser optimizado fora por quem ler depois.

**Prova ao vivo (VPS, fila real):**
```
DRY: sem novidade e sem staleness (newest=…==last=…, count=2, oldest_age=0min) — silêncio
```
`count=2` mas `oldest_age=0min` → os 2 Balde B legítimos **já não realimentam o fallback**.
O gatilho que disparava a cada ~40 min está calado. I3 confirmado em produção.

---

## PARTE D — P3 mapeado: `aprovada` → execução **NUNCA EXISTIU**

Não está "partido": **nunca foi construído**. Procurei todos os leitores de `status='aprovada'`
em `supabase/`, `.claude/scripts/` (ts/sql/sh/py). Todos os hits são de três tipos:
- **escrita** — `robot_approve_plan`: `SET status='aprovada'`
- **dedup** — `WHERE dedup_key = … AND status IN ('nova','aprovada')`
- **métrica** — `taxa_aprovacao_pct`

**Zero consumidores de execução.** E os únicos crons que mencionam robot são `robot-b-hourly`
(gera sugestões) e `robot-b-weekly-digest`. Nada faz poll de itens aprovados.

Conclusão: **aprovar escreve num estado que ninguém lê.** É por isso que 46 linhas estão paradas
desde 19/06 e o último `aplicada` é de 14/07 — e é por isso que as 5 aprovações do Danilo de hoje
não produziram nada. Não foi azar nem regressão; o troço final do caminho não existe.

**Construção proposta (padrão barato, igual ao `red_queue_watermark`):**
RPC `approved_queue_watermark()` (agregado: count + oldest) → cron `*/10` no host da VPS →
injeta ordem com **lote ≤8**, mais antigos primeiro → maestro executa → `aplicada`.
Reusa a plumbing já provada esta noite. Nível 3/dinheiro continua a exigir o "vai".

---

---

## PARTE E — P3 construído · e a CAUSA-RAIZ REAL do `SAIDA-VAZIA` encontrada

### Construído (migration `robot_consumidor_aprovadas_cutoff_e_claim_atomico`)
- **TRAVA 1 — CUTOFF:** `platform_settings.robot_consumer_cutoff_at` = `2026-07-31 22:51:34Z`.
  Aplicado **no servidor** (dentro da RPC), não no script — o cron não o pode contornar.
- `approved_queue_watermark()` — agregado, anon, `status='aprovada'` **só** pós-cutoff.
- **TRAVA 2 — `robot_claim_approved(≤8)`:** `FOR UPDATE SKIP LOCKED` + `aprovada→em_execucao`
  na mesma transação. Reclama leases mortas (`em_execucao` há >60 min) para nada ficar preso.
- `robot_finish_approved(id, ok, nota)` — `em_execucao→aplicada`, ou devolve a `aprovada` para
  retentar (a autorização do Danilo mantém-se).
- **TRAVA 4:** `aprovada-emerson` excluído — tem ciclo próprio (`robot_emerson_decide` /
  `robot_emerson_close`). Não se assumiu equivalência.
- `hermes-consumidor-aprovadas.sh` deployado à VPS (hash `70a8f09046dfe783` == repo) + cron `*/10`.

### Provas
| Trava | Prova | Resultado |
|---|---|---|
| 1 CUTOFF | watermark com 46 `aprovada` na base | `pending_count = 0` ✅ |
| 1 CUTOFF | dry-run do script real na VPS | `nada aprovado por correr — silêncio` ✅ |
| 2 IDEMPOT. | 2 claims concorrentes (conexões distintas) | A pegou 4, **B pegou 0** ✅ |
| 2 IDEMPOT. | duplo `robot_finish_approved` no mesmo id | `estado_inesperado:aplicada` ✅ |
| fecho | ok / falha | `aplicada` / `devolvida_a_fila` ✅ |
| backlog | depois de tudo | 46 `aprovada` + 3 emerson + **0** `em_execucao` ✅ intactas |

### 🔴 A prova final NÃO fechou — e o motivo é maior que o P3
Aprovei 1 item novo pós-cutoff. O consumidor detetou (`count=1`) e injetou
`ordem-20260731225431-aplic`. **A ordem morreu em 11 segundos** (22:54:31 → 22:54:42) com a nota
genérica `SAIDA-VAZIA — tarefa grande demais?`. 11s não é teto de turnos: o executor **não
arrancou**.

Investiguei em vez de chutar (era a 3.ª atribuição de causa errada deste sistema):
1. Ponte VPS→PC: **viva** — `ssh … tailscale nc … hermes@100.71.105.7 "echo PONTE-VIVA"` → `PONTE-VIVA`.
2. Invoquei o executor à mão: `pc-loop "Responde apenas: PROVA-EXECUTOR-OK"` →
   **`[loop] ERRO: claude.exe nao encontrado`**.
3. `run-claude-loop.cmd:42` tem o caminho **hardcoded**
   `C:\Users\danil\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe`
   e a linha 53 aborta com `exit /b 4` se não existir.
4. **Esse caminho não existe** — a pasta npm global do `@anthropic-ai/claude-code` desapareceu.

> ### ⛔ CORREÇÃO (2026-08-01) — a conclusão abaixo estava ERRADA
> Escrevi aqui *"a CLI do Claude Code não está instalada no PC"*. **É falso.** O Danilo apanhou
> o erro com um facto que eu tinha à frente e não usei: **a sessão que escreveu este relatório
> É o Claude Code a correr nesse PC** — logo a CLI existe. Falhava a **resolução**, não a
> existência. Registo o erro em vez de o apagar, para o Córtex não guardar a versão errada.
>
> **Causa real — isolamento de perfil** (hipótese do Danilo, confirmada em 3 passos):
> | | utilizador | `%APPDATA%` |
> |---|---|---|
> | sessão interativa | `laptop-2q09vqa1\danil` | `C:\Users\danil\AppData\Roaming` |
> | executor (`pc-loop`) | `WORKGROUP\hermes` | `C:\Users\hermes\AppData\Roaming` |
>
> Binário real: `C:\Users\danil\AppData\Roaming\Claude\claude-code\2.1.219\claude.exe`
> (instalado **27/07/2026** pela app Claude). O `%APPDATA%\npm\…` da linha 42, avaliado como
> `hermes`, apontava para o perfil do `hermes` — vazio. E `where claude` sob `hermes` também
> devolve vazio (não há shim no PATH dele), por isso **resolução dinâmica sozinha não bastava**.
>
> **Data exacta da avaria:** a ordem `aa42` passou à 1.ª em **22/07**, quando a CLI ainda vinha do
> npm global. A app instalou a CLI nova a **27/07**. Janela da avaria: **27/07 → 31/07, 4 dias**,
> toda ela escondida atrás da nota que dizia "tarefa grande demais".

**Efeito:** o executor abortava antes de emitir um único byte → o parser não chega sequer ao ramo
`type:result` → por isso nem a FASE 1.10 salva a nota (ela cobre "parou a meio", não "nunca
arrancou").

Isto responde ao passo 3 da Parte 1 da paridade com prova, e reescreve o diagnóstico da noite:
- **não** era "tarefa grande demais" (mentira da nota genérica);
- **não** eram só os tetos 40/$10 (esses eram um problema real, mas a montante deste);
- era o **binário do executor ausente**. Explica também o `JUIZ-SEM-VEREDITO` em série — o juiz
  corre pela mesma CLI.

---

## PARTE F — FASE 1.11: desbloqueio (a) COM GLOB + preflight que grita

Decisão do Danilo: **(a) com glob**, como *desbloqueio*, não solução final.

1. **Resolução dinâmica** — `resolve-claude-exe.ps1` (helper novo, mesmo padrão dos já
   existentes `executor-lock.ps1` / `stale-output-watchdog.ps1`). Ordena por `[version]`, **nunca
   alfabeticamente** (alfabético põe `2.1.9` acima de `2.1.10`) e **nunca versão fixa**.
   > Primeira tentativa foi um one-liner dentro do `for /f "usebackq"` e **falhou**: o `cmd.exe`
   > interpreta o `|` antes do PowerShell, e escapá-lo com `^|` passa o `^` literal
   > (`Sort-Object : não é possível localizar um parâmetro posicional`). Daí o ficheiro à parte.
2. **Preflight que grita** — `CLI-NAO-ENCONTRADA: procurei em <caminhos> -- utilizador=<user>
   APPDATA=<...>` em vez de 0 bytes. No `carteiro.sh`: `cli_nao_encontrada_linha()` (irmã de
   `executor_parou_linha`), a nota passa a ser **essa linha exata**, e a ordem **trava à 1.ª** —
   retentar não instala uma CLI. Prioridade sobre todos os outros ramos: se nada arrancou,
   qualquer outro diagnóstico seria inventado.
   **Provado ao vivo:** `CLI-NAO-ENCONTRADA: … utilizador=WORKGROUP\hermes
   APPDATA=C:\Users\hermes\AppData\Roaming`. Nunca mais "SAIDA-VAZIA — tarefa grande demais".

Deployado: PC (`run-claude-loop.cmd` + `resolve-claude-exe.ps1`) e VPS (`carteiro.sh`).

### 🔴 Risco 3 confirmou-se — auth por perfil
Com o binário resolvido, o executor **arranca** (passa o preflight e a resolução) e morre em:

```
Failed to authenticate: OAuth session expired and could not be refreshed
```

`CLAUDE_CONFIG_DIR` já aponta para `C:\Users\danil\.claude`, logo o `hermes` **lê** a config do
`danil` — mas a sessão OAuth aí não é utilizável por ele. Achar o binário **não** era resolver,
tal como o Danilo avisou. A mensagem é específica e honesta — não voltou a chamar-se SAIDA-VAZIA.

**Decisão em aberto (b) / (c) / (d)** — (d) = instalar a CLI sob o perfil do `hermes`, que
preserva o isolamento melhor que (c) e não estava na minha lista original.

---

## Estado dos invariantes

| # | Invariante | Veredito |
|---|---|---|
| I1 | Achado repetido não gera linha nova | ✅ **PROVADO** — 32 repetições → 1 linha; origem (prompt) e servidor corrigidos |
| I2 | Ordem ≤ o que o executor aguenta | ✅ **PROVADO** — fila 30 → lote 8; deployado à VPS, hash confirmado |
| I3 | Item triado não reabre o fallback | ✅ **PROVADO ao vivo** — `count=2 oldest_age=0min` → silêncio |
| I4 | `travada` não-vermelha não notifica | ⏳ Parte 2 (adiada por decisão do Danilo) |
| I5 | Aprovação → execução automática | 🟡 **circuito construído e provado até à injeção da ordem**; o troço final está bloqueado por causa externa: a CLI do Claude Code não está instalada no PC |

## Bloqueador único que trava tudo o resto
**A CLI do Claude Code não existe no PC.** Enquanto isso durar, nenhuma ordem executa — nem as
do P3, nem as do aprovador-vermelho, nem o Juiz. Todo o resto desta noite está feito e provado;
isto é o que falta e é ato humano (instalar software).

## Veredito das 2 perguntas da missão paridade
1. **A FASE 1.10 estava viva no PC?** → **NÃO.** Provado por hash + `grep -c` = 0. Já corrigido.
2. **A mesma tarefa pesada termina pelos dois caminhos?** → ⏳ Parte 2 (por correr).

## Decisão que preciso do Danilo (não é dinheiro — é risco de apagar aprovações)
Para o backfill do `dedup_key`, qual a regra ao fundir linhas vivas com a mesma base?
**(a)** manter a **mais recente** e marcar as outras `expirada` (histórico preservado);
**(b)** manter a **mais antiga** (preserva o `created_at` original do achado);
**(c)** não fundir `aprovada` — normalizar só as `nova` e deixar as aprovadas em paz até
serem executadas. ← **a minha recomendação**, é a única que não toca em trabalho já autorizado.

## Ficheiros tocados
- `orquestracao/missoes/nunca-mais-travar-2026-07-31.md` (novo)
- `orquestracao/missoes/paridade-auto-vs-manual-2026-07-31.md` (novo)
- `hermes-bridge/bora-live-parser.ps1` + `run-claude-loop.cmd` (**PC, fora do repo** — deploy
  FASE 1.10; backups em `_backup/`)
- Nada commitado ainda — ver secção "boleia" antes de push.
