---
id: evolution-report-2026-07-12
tipo: relatorio
origem: [evolution-engine v1 — análise mecânica sobre telemetria + reports]
ultima_confirmacao: 2026-07-12
zona: verde
confianca: auto
---

# 🧬 Evolution Report — 2026-07-12

> Gerado por `evolution_engine.py` (deteção mecânica). Drafts = agente; gate = Juiz.
> 🟢 = draft possível após Juiz · 🔴 = SÓ PROPOSTA (dinheiro/auth — Danilo aplica).

Skills analisadas: **50** · Propostas novas: **28** · Rejeitadas (não repropostas): 0
> Atualização 2026-07-12T~16:00Z: +CASO CONCRETO 3 (loop auto-referencial do `evolution-trigger`) → EVOL-1/EVOL-2.
> Atualização 2026-07-12T~19:43Z: +CASO CONCRETO 4 (janela de prova temporal > 900s embutida numa ordem síncrona) → TPROVA-1/TPROVA-2.
> Atualização 2026-07-12T~21:xxZ: gatilho fora-de-ciclo re-disparou sobre o **mesmo** padrão
> `TIMEOUT-900s x2` já coberto pelo CASO CONCRETO 4 — sem ordem travada nova associada. Confirma
> que a causa-raiz (passo B síncrono com prova de 30 min embutida) **continua por corrigir**;
> **não gera propostas duplicadas** (TPROVA-1/2/3 já cobrem o caso). Ação pendente continua a ser
> TPROVA-2 (reescrever o passo B da missão em B1+B2) antes do próximo disparo.
> Atualização (nova corrida fora-de-ciclo, mesmo dia): **3.ª repetição** do mesmo padrão
> `TIMEOUT-900s x2`, sem ordem travada nova. Confirmado por leitura direta do ficheiro-fonte
> `.claude/.ai/hermes/orquestrador-carteiro/missoes/missao-plano-mestre-2026-07-12.md:9` — o passo
> B **ainda** mistura "powercfg + adb key fix" com "provar 30 min sem queda" na mesma tarefa
> síncrona, exatamente como diagnosticado. **Correção a uma nota anterior:** este ficheiro-fonte
> vive dentro deste repo Windows (não só no VPS) — TPROVA-2 pode ser rascunhado e aplicado aqui
> mesmo (zona 🟡, ainda assim precisa do gate do Juiz antes de editar). Nenhuma proposta nova; ação
> pendente continua TPROVA-2.

---

## 🎯 CASO CONCRETO (gatilho fora-de-ciclo) — `ordem-20260712082402-c287`

> Corrida acionada porque esta ordem entrou em **`travada`** (tentativa **5/5**, teto esgotado).
> Análise do padrão de falha + proposta. **Zona 🟡 (orquestração/loop) → SÓ PROPOSTA; draft passa
> OBRIGATORIAMENTE pelo `juiz-revisor` antes de aplicar. NÃO toca dinheiro/auth.**

**Ordem:** redesenhar o fluxo de conclusão de tarefas para ser **por EVENTO** (hook de conclusão)
em vez de ronda de 10 min (PASSO 1–4).

**Diagnóstico — falso-bloqueio + padrão de scope-bundling:**

1. **Os deliverables EXISTEM e passam.** Apesar de `estado: travada`, o trabalho foi entregue:
   `.claude/scripts/hermes-hook-conclusao.sh` (**`--selftest` → 7/7 OK, `bash -n` limpo**),
   integração no `carteiro.sh`, `SKILL.md`, `DEPLOY.md`, `loops.md` (secção nova) e dois relatórios
   no inbox (`hook-conclusao-por-evento-2026-07-12.md`, `hook-simples-2026-07-12.md`). → A ordem
   **morreu no teto de tentativas mesmo com a versão mínima concluída** — bloqueio falso.

2. **Causa-raiz (padrão reincidente):** as tentativas 1–4 atacaram o **pacote inteiro** (script +
   deploy VPS + lançador de missão + integração total) — grande demais para convergir dentro de 5
   tentativas. Só na tentativa que reduziu ao **mínimo** (o Danilo mandou "faz só o mínimo") é que
   passou — mas o contador já estava no teto. Padrão: **ordem com escopo empacotado → esgota o teto
   de 5 antes de convergir**, quando uma decomposição *mínimo-primeiro* teria passado à 1.ª/2.ª.

**Propostas (ambas 🟡 propose-only → Juiz; nenhuma auto):**

| # | Proposta | Tipo | Evidência | Ação |
|---|---|---|---|---|
| C287-1 | **Regra de decomposição "mínimo-primeiro"** no `maestro-autonomia`/carteiro: ordem que junte `código + deploy + integração` nasce dividida — parte 1 = núcleo verificável (com self-test); deploy/integração = partes seguintes. Evita morte-no-teto por escopo. | governança do loop | c287 empancou 4× no pacote inteiro; passou ao 1.º corte mínimo | Draft de regra em `loops.md`/SKILL do maestro → **Juiz** → Danilo |
| C287-2 | **Guarda anti-falso-bloqueio no fecho:** antes de marcar `travada` no teto, o hook/juiz verifica se há deliverable a passar self-test; se sim → `concluída` (ou continuação mínima), não `travada`. Exatamente o que o próprio hook desta ordem já esboça (continuação em vez de alarme). | governança do loop | ordem entregue + a passar 7/7, ainda assim `travada` | Draft → **Juiz** → Danilo |

**Nota operacional (não-aplicada):** `c287` parece um **falso-bloqueio** — recomenda-se ao
`maestro-autonomia`/Danilo **verificar os deliverables e fechar/continuar** em vez de a deixar morta
no teto. **Não fecho a ordem** (é ato de orquestração/Córtex, fora do meu mandato de propor).

---

## 🎯 CASO CONCRETO 2 (gatilho fora-de-ciclo) — `ordem-...-aprv` + `ordem-...-e2e`

> Corrida acionada por DUAS ordens que entraram em **`travada`** ao mesmo timestamp
> (`2026-07-12T10:10:03Z`): `ordem-20260712101003-aprv` (autor `hermes-aprovador-vermelho` cron */10)
> e `ordem-20260712101003-e2e` (autor `hermes-e2e-vigia` cron */10). Ambas **zona 🟢/🟡 (governança
> de loop)**. **SÓ PROPOSTA; draft passa OBRIGATORIAMENTE pelo `juiz-revisor`. NÃO toca dinheiro/auth.**

**Sintomas partilhados (evidência dura):**

1. **Contador ultrapassou o teto:** ambas as ordens têm `tentativa: 5` com `teto_tentativas: 3`
   (5 > 3). O teto **não é um hard-stop** — o cron `*/10` re-dispara a ordem e incrementa a tentativa
   mesmo depois de o teto ter sido esgotado. Duas ordens independentes com o mesmo overshoot → bug de
   enforcement, não coincidência.
2. **São vigias recorrentes, não deliverables convergentes.** Um watchdog `cron */N` dispara em
   ciclo; um disparo que "não consegue agir" devia **ficar em standby até ao próximo tick**, não
   acumular tentativas rumo a uma morte `travada`. Modelá-los como ordem-deliverable-com-teto é um
   **erro de categoria** (distinto do scope-bundling do c287).
3. **Impossibilidade estrutural para o executor headless** (causa de "falha" que nunca converge):
   - `aprv`: a tarefa manda **"Auto-aprova Balde A"**, mas as RPCs de aprovação/reject exigem **JWT
     de admin** (o MCP/executor headless não o tem → ver `project_aprovador_vermelho_central`), e a
     política do loop headless é **só propor** na fila 🔴. Logo a ação pedida é impossível → "falha"
     em ciclo → teto → `travada`.
   - `e2e`: a tarefa manda **"verifica se o loop noturno ainda corre no PC ... retoma-o"**, o que
     exige **visibilidade/controlo dos processos do PC local**. Um executor cloud/headless não tem
     janela para os processos locais → não consegue verificar nem retomar → "falha" → `travada`.

**Propostas (todas 🟡 governança-de-loop, propose-only → Juiz; nenhuma auto; complementam C287-1/2):**

| # | Proposta | Tipo | Evidência | Ação |
|---|---|---|---|---|
| AE2E-1 | **Classe de ordem "vigia/cron recorrente" ≠ deliverable.** Ordem cujo autor é um `cron */N` watchdog ganha ciclo-de-vida próprio: **sem morte-no-teto**; disparo que não pode agir → `standby` (aguarda próximo tick), nunca `travada`. | governança do loop | 2 vigias `*/10` mortas em `travada` no mesmo tick | Draft de regra em `loops.md`/carteiro → **Juiz** → Danilo |
| AE2E-2 | **Hard-stop no teto (corrige overshoot 5>3).** O contador de tentativas NUNCA pode exceder `teto_tentativas`; quando o cron re-dispara uma ordem já no teto, **não incrementa** — dedupe/skip da ordem existente. | governança do loop | ambas com `tentativa:5` e `teto:3` | Draft no carteiro/gerador de ordens → **Juiz** → Danilo |
| AE2E-3 | **Capability-gate antes de retry.** Ordem cujo sucesso exige capacidade que o executor headless não tem (JWT admin; visibilidade do PC local) é **roteada/deferida ao ator certo** (Danilo/painel para o `aprv`; watchdog local, não cloud, para o `e2e`), não retentada até morrer. | governança do loop | `aprv` precisa JWT admin; `e2e` precisa o PC local | Draft → **Juiz** → Danilo (estende C287-2) |

**Nota operacional (não-aplicada):** ambas parecem **falso-bloqueio por incompatibilidade
executor↔tarefa**, não trabalho por fazer. Recomenda-se ao `maestro-autonomia`/Danilo **fechar/deferir
estas duas ordens** e reencaminhar as tarefas ao ator com a capacidade certa. **Não fecho as ordens**
(ato de orquestração/Córtex, fora do meu mandato de propor). *(Script mecânico não re-corrido neste
executor — `python` indisponível no ambiente headless; deteção mecânica é a da corrida diária acima.)*

---

## 🎯 CASO CONCRETO 3 (gatilho fora-de-ciclo) — LOOP AUTO-REFERENCIAL do `evolution-trigger`

> Corrida acionada por `ordem-20260712155505-evol` (motivo: "ordens travadas novas:
> [ordem-20260712155007-evol]"). Ao seguir a cadeia descobre-se um **loop de realimentação**:
> a ordem-gatilho aponta para OUTRA ordem `-evol`, que aponta para outra, e assim sucessivamente.
> **Zona 🟡 (governança/orquestração de loop) → SÓ PROPOSTA; draft passa OBRIGATORIAMENTE pelo
> `juiz-revisor` antes de aplicar. NÃO toca dinheiro/auth.**

**Diagnóstico — o gatilho come a própria cauda (root cause, distinto do C287/AE2E):**

1. **Evidência dura:** o Córtex tem **~30+ ordens `-evol`** criadas a cada ~5 min desde ~13:30 de
   2026-07-12 (`...132007-evol` → `...132504` → `...133011` → … → `...155007` → `...155505` →
   `...160008`), TODAS `estado: travada`, `tentativa: 5`, `teto_tentativas: 3`. Cada uma cita a
   `-evol` anterior como "ordem travada nova". Cadeia ininterrupta, 1 nova por tick do cron `*/5`.
2. **Mecanismo (em `.claude/scripts/hermes-evolution-trigger.sh`, linhas 49–56):** o scan de
   "travadas novas" **NÃO exclui as ordens `-evol` que o próprio trigger gera** (criadas em
   `estado: aberta`, linha 89). Quando uma `-evol` não converge e cai em `travada`, no tick seguinte
   ela é uma "travada nova" → o trigger dispara **outra** `-evol` (linha 78) e adiciona a anterior ao
   watermark. Cada `-evol` dispara exatamente 1 sucessora → **cadeia auto-perpetuante** que nunca
   drena. O `evolution-engine` "corre", mas nunca resolve nada — só alimenta o gerador.
3. **Porque caem em `travada`:** mesmo overshoot `5>3` do AE2E-2 — o executor produz o relatório mas
   não marca a ordem `concluída`, o cron re-tenta até ao teto e passa a `travada`. Ou seja: **AE2E-2
   (hard-stop no teto) + este EVOL-1 (anti-auto-referência) juntos** matam o loop pela raiz.

**Propostas (🟡 governança-de-loop, propose-only → Juiz; nenhuma auto):**

| # | Proposta | Tipo | Evidência | Ação |
|---|---|---|---|---|
| EVOL-1 | **Guarda anti-auto-referência no `evolution-trigger`:** o scan de "travadas novas" ignora as ordens que o próprio trigger (e vigias-cron pares) geram — `*-evol`, `*-aprv`, `*-e2e`. Assim a saída do gatilho nunca realimenta o gatilho. | governança do loop | ~30+ `-evol` em cadeia, 1/tick */5, todas `travada` | **Draft abaixo** → **Juiz** → deploy VPS |
| EVOL-2 | **Coalescer disparos `-evol`:** se já existir uma ordem `-evol` `aberta`/em-curso na fila, não criar outra — atualizar/anexar motivo à existente (dedupe por tipo). Evita enxame mesmo sem falha. | governança do loop | 128 páginas no Córtex, maioria spam `-evol` | Draft → **Juiz** → deploy VPS |

**Draft EVOL-1 (patch mínimo — NÃO aplicado; aguarda Juiz + deploy):**

```diff
   e=$(grep -m1 '^estado:' "$f" | sed 's/estado: *//' | tr -d '\r')
   [ "$e" = "travada" ] || continue
   id=$(basename "$f" .md)
+  # ANTI-LOOP: não disparar sobre ordens que o próprio trigger (ou vigias-cron pares)
+  # geram — senão a saída -evol que fica 'travada' realimenta o gatilho a cada tick.
+  case "$id" in *-evol|*-aprv|*-e2e) continue ;; esac
   grep -qxF "$id" "$STATE" && continue
   travadas_novas="$travadas_novas $id"
```

**Nota operacional (não-aplicada):** o script canónico está no repo mas corre em `/usr/local/bin/`
**no host do VPS** — o fix só trava o loop **depois de deployado lá** (fora do alcance deste executor
headless). Até lá o cron `*/5` continua a gerar `-evol`. Recomenda-se ao Danilo/Hermes: (1) aplicar
EVOL-1 após o Juiz e deployar no VPS; (2) marcar as ~30 ordens `-evol` `travada` como
`cancelada`/`concluída` para limpar o backlog e o watermark. **Não fecho as ordens nem edito o
script canónico** (green-zone → gate do Juiz obrigatório; e o fecho é ato de orquestração/Córtex).

---

## 🎯 CASO CONCRETO 4 (gatilho fora-de-ciclo) — `ordem-20260712194301-missao-plano-mestre-2026-07-12-B`

> Corrida acionada por uma ordem **travada nova** + erro repetido **≥2×/2h**:
> `⏱️ TIMEOUT-900s x2 — tarefa grande demais; DIVIDIR em passos menores (convencoes.md). Não re-tento
> a mesma coisa.` **Zona 🟡 (governança/orquestração de loop) → SÓ PROPOSTA; draft passa
> OBRIGATORIAMENTE pelo `juiz-revisor` antes de aplicar. NÃO toca dinheiro/auth.**

**Diagnóstico — janela de prova temporal contínua embutida numa ordem síncrona (root cause distinto
do C287/AE2E/EVOL-1..2):**

1. **Evidência dura — a própria missão pede uma espera embutida.** `ordem-...-B` é o passo B de
   `.claude/.ai/hermes/orquestrador-carteiro/missoes/missao-plano-mestre-2026-07-12.md` (linha 9):
   > "Estabilidade adb/USB: desligar USB selective suspend (AC+DC) no esquema de energia ativo via
   > powercfg; fixar a autorizacao adb dos 2 telemoveis (incluindo N75LTG5X5DSKDMV4) via adb
   > kill-server/start-server reusando o adbkey; **provar 30 min sem queda**. Relatorio curto em
   > inbox/."
2. **`CONVENCOES.md` (linhas 7–12) é claro e vigente:** "1 ordem = 1 objetivo ≤15 min de trabalho
   real"; ao estourar os **900s** o carteiro marca `⏱️ TIMEOUT-900s`; ao 2.º timeout **TRAVA com
   sugestão de dividir** — nunca re-tenta a mesma coisa. É exatamente o que está a acontecer aqui.
3. **Por que "dividir em passos menores" (a correção-padrão do C287) NÃO resolve sozinho neste
   caso:** o passo B mistura duas naturezas de trabalho diferentes na mesma ordem síncrona —
   (a) **ação rápida** (powercfg + adb kill-server/start-server, cabe folgado em 900s) e
   (b) **janela de observação contínua de 30 min** ("provar 30 min sem queda"), que por definição
   excede os 900s do teto duro. Ao contrário do scope-bundling do C287 (código+deploy+integração —
   decomponível em sub-tarefas *sequenciais* que cada uma cabe em 900s), aqui **nenhuma decomposição
   em sub-tarefas síncronas cabe**, porque uma delas exige presença/observação ininterrupta maior que
   o teto de execução. Re-tentar a ordem inteira do zero (o que "TIMEOUT x2" indica estar a
   acontecer) nunca converge — desperdiça tentativas rumo a `travada`.
4. **Confirmado: não coberto pelas propostas já em vigor.** Grep em `loops.md` e nas propostas C287/
   AE2E/EVOL deste mesmo relatório não encontra o padrão "prova/observação temporal contínua > 900s
   embutida numa única ordem". É uma classe de bloqueio nova.
5. *(Limitação do executor: a ordem `-B` vive em `orquestracao/` no host Hermes/VPS, fora deste repo
   Windows — mesma limitação já registada no CASO CONCRETO 2. `python
   .claude/skills/evolution-engine/scripts/evolution_engine.py --dry-run` não foi re-corrido; a
   análise mecânica de referência é a da corrida diária no topo deste relatório.)*

**Propostas (🟡 governança-de-loop, propose-only → Juiz; nenhuma auto):**

| # | Proposta | Tipo | Evidência | Ação |
|---|---|---|---|---|
| TPROVA-1 | **Regra da "prova assíncrona"** em `CONVENCOES.md`: uma ordem NUNCA embute uma espera/observação contínua > 900s dentro da própria execução. Separar em (a) ordem A' = aplica a mudança + arranca um marcador/log de observação em background (ex. `adb logcat`/heartbeat leve para ficheiro) e fecha `concluída` logo após aplicar; (b) ordem B' = passo seguinte, agendado só depois de decorrido o intervalo, que LÊ o marcador/log e confirma "sem queda" sem bloquear a sessão do executor. | governança do loop | passo B pede "provar 30 min sem queda" na mesma ordem síncrona; `TIMEOUT-900s` ≥2×; `CONVENCOES.md`:7-12 confirma teto ≤15min/900s | Draft de regra em `CONVENCOES.md` → **Juiz** → Danilo |
| TPROVA-2 | **Reescrever o passo B da missão** `missao-plano-mestre-2026-07-12.md` (linha 9) separando em **B1** (powercfg + adb key fix — fecha rápido, cabe em 900s) e **B2** (verificar estabilidade após decorrido o intervalo, lendo o log deixado por B1 — nova ordem, `depende: B1`). Evita que esta mesma ordem volte a bater no teto quando a missão for (re)disparada. | correção pontual da missão | texto exato da linha 9 já mistura ação+prova-30min; TIMEOUT-900s×2 já ocorreu | Draft de patch ao texto do passo → **Juiz** → Danilo aplica na missão |
| TPROVA-3 | **Generalizar em `loops.md` (`permanente/semantica/loops.md`):** classe reutilizável "ordem com prova temporal" — qualquer tarefa futura que peça "provar/observar N min sem falha" deve nascer já dividida em (aplicar) + (verificar depois), nunca numa ordem síncrona só. Evita que o mesmo padrão reapareça noutras missões (ex.: qualquer prova de estabilidade pós-mudança). | governança do loop / registry | padrão novo, não coberto por C287 (scope-bundling) nem AE2E (vigia-cron) nem EVOL (auto-referência) | Draft de entrada no registry `loops.md` → **Juiz** → Danilo |

**Nota operacional (não-aplicada):** `ordem-...-B` parece **estruturalmente impossível de fechar como
está escrita** — não é falta de esforço do executor, é o desenho da ordem que pede uma espera maior
que o teto de execução. Recomenda-se ao `maestro-autonomia`/Danilo **não voltar a re-disparar a
ordem tal-e-qual** (nunca vai convergir) e, em vez disso, aplicar TPROVA-2 (reescrever o passo B em
B1+B2) antes do próximo disparo desta missão. **Não fecho nem edito a ordem, a missão ou
`CONVENCOES.md`/`loops.md`** — são atos de orquestração/Córtex e edição de convenções, fora do meu
mandato de propor (zona 🟡 → gate do Juiz obrigatório antes de qualquer aplicação).

---

## 🧹 Higiene do Cérebro — 0 páginas >60d (5 piores)


## 🔁 Loops (Loop Economy)

Telemetria de loops (custo_acumulado × retorno) ainda sem dados — o economy check dispara a partir do 1.º ciclo com os pares preenchidos em `loops.md`. Regra: muitas execuções + custo alto + retorno ≈ 0 → propor otimizar/arquivar (🟢/🔵 NUNCA auto).

| Capacidade | Zona | Alvo | Evidência | Ação recomendada |
|---|---|---|---|---|
| Detetar padrão | 🟢 | `(skill nova?) tópico 'tokens'` | 13 reports com 'tokens' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'autocomplete'` | 11 reports com 'autocomplete' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'continente'` | 11 reports com 'continente' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'bugs'` | 9 reports com 'bugs' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'campaign'` | 9 reports com 'campaign' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'plan'` | 8 reports com 'plan' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'redlist'` | 6 reports com 'redlist' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'bug1'` | 4 reports com 'bug1' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'investigation'` | 4 reports com 'investigation' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'reservas'` | 4 reports com 'reservas' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'paragem'` | 4 reports com 'paragem' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'verde'` | 4 reports com 'verde' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'updater'` | 4 reports com 'updater' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'bug4'` | 3 reports com 'bug4' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'cliente'` | 3 reports com 'cliente' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'autonomous'` | 3 reports com 'autonomous' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'tudo'` | 3 reports com 'tudo' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'phase1'` | 3 reports com 'phase1' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'exec'` | 3 reports com 'exec' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'finalize'` | 3 reports com 'finalize' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'glovo'` | 3 reports com 'glovo' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico '3of5'` | 3 reports com '3of5' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico '4of5'` | 3 reports com '4of5' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'validacao'` | 3 reports com 'validacao' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'phase0'` | 3 reports com 'phase0' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |
| Detetar padrão | 🟢 | `(skill nova?) tópico 'pvpr'` | 3 reports com 'pvpr' no nome e nenhuma skill correspondente | avaliar skill nova com draft (agente redige, Juiz avalia) |

*Estado de propostas em `.claude/skills/evolution-engine/scripts/state/propostas.json` — marcar `"estado": "rejeitada"` para não repropor.*
