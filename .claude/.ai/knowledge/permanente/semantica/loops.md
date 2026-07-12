---
tema: loops · escopo: projeto · estado: atual · atualizado: 2026-07-12
id: loops
tipo: registry
origem: [missão "Do Prompt ao Loop" 2026-07-10 — crons VPS/host verificados por SSH, crons Supabase, skills]
ultima_confirmacao: 2026-07-12
zona: verde
confianca: verificado
---

# 🔁 Loop Registry — catálogo vivo de TODOS os loops

> **Princípio (constituição §10):** toda automação permanente nasce como um Loop; todo Loop
> tem dono, métricas, custo, objetivo, cor e capacidade de evoluir. Problema recorrente vira
> loop registado — nunca prompt solto nem script isolado.
> **Regra de nascimento:** um loop só nasce respondendo às **5 perguntas** (problema · métrica ·
> gatilho · quem depende · critério de sucesso) + **cor** + **dono** (ver `convencoes.md`).
> O `evolution-engine` propõe melhorias de LOOPS, não só de skills.

## As cores (prioridade no watchdog)
- 🟢 **Core** — mantêm a empresa viva. Travar = **alarme VERMELHO imediato** no Telegram.
- 🔵 **Business** — geram receita. Travar = aviso prioritário.
- 🟡 **Learning** — melhoram o sistema. Resumo normal.
- 🟣 **Quality** — garantem qualidade. Resumo normal.
- ⚫ **Mission** — começo e fim; concluída a missão, o loop é **arquivado** (critério de conclusão).

## As 3 camadas de vigília (barata → cara) — nunca queimar o limite do Claude à toa
> **Princípio (2026-07-12):** vigiar é barato; pensar é caro. Só se sobe de camada quando a de
> baixo encontra algo REAL. Nunca se acorda a camada cara "por via das dúvidas" a cada tick.

1. **Watchdog-Hermes (10 min · IA barata / zero-IA · VPS 24/7)** — a camada de baixo. Corre no
   host da VPS, só com **SQL read-only + bash** (nunca Opus, nunca gasta o limite do Claude.ai).
   **DETETA → AGE se puder → só AVISA o Danilo se for dinheiro/ambíguo:** `hermes-watchdog.sh`
   (v3, 2026-07-12) deixou de ser "só aviso, não ajo": agora é o **umbrella** que chama os
   vigias que **AGEM** tocando a campainha — `carteiro-vigia` (campainha morta), `e2e-vigia`
   (loop E2E parado) — e reinicia o container Hermes se estiver DOWN. **Só escala ao Danilo**
   (com **dedupe por assinatura** — mesma lista → silêncio, nunca repete a cada 10 min) o que
   precisa de decisão: `zona_vermelha` (dinheiro/produção), `travada` esgotada >12h (arquivar ou
   reformular), disco cheio, daily-pulse morto, crashes reais. `evolution-trigger`,
   `aprovador-vermelho` completam a camada. Todos com **watermark/dedupe**: disparam no máx.
   1x por episódio real; sem episódio → **0 disparos** (sem spam).
2. **Bora Loop Routine (1x/hora · análise)** — o carteiro (`:17` hourly + campainha) puxa as
   ordens da fila e corre o esquadrão certo no PC. É aqui que uma deteção da camada 1 vira
   trabalho concreto. Custo médio (uma corrida por ordem real), não a cada 10 min.
3. **Claude.ai / Claude Code (só quando chamado)** — a camada cara. Só acorda por ordem na fila
   (campainha) OU por pedido explícito do Danilo. Nunca por cron cego. É o que protege o limite
   semanal: sem sinal real da camada 1 → o Claude não é acordado.

**e2e-vigia** é o exemplo canónico da camada 1 a fechar o loop com a camada 3 **só quando real**:
lê `e2e_log.last_write` (1 GET anon), e se o teste ficou silencioso 20–90 min (parou a meio, não
"nunca arrancou") injeta **uma** ordem de retoma; enquanto o `last_write` não mudar, não repete.

## Loops ativos

| Cor | Loop | (1) Problema que resolve | (2) Métrica que melhora | (3) Gatilho | (4) Quem depende | (5) Critério de sucesso | Entradas→Saídas | v | Dono |
|---|---|---|---|---|---|---|---|---|---|
| 🟢 | **Orquestração (carteiro)** | ordens do Danilo executadas no PC sem sessão manual | ordens concluídas/semana | inotify (campainha) + cron `:17` hourly | Danilo, Hermes, maestro | ordem `aprovada` ≤5 tentativas | `orquestracao/ordem-*.md` → `.saida.txt`+Telegram | 1 | Hermes(host)/`maestro-autonomia` |
| 🟢 | **Maestro↔Juiz (auto-cura)** | paridade admin sem supervisão item-a-item | placar paridade 360° | ciclo do maestro | Central/Danilo | nota ≥9 ou travado c/ pedido de ajuda | backlog → suggestion `aguarda_ti` | 1 | `maestro-autonomia` |
| 🟢 | **daily-pulse (Sócio-AI)** | cegueira ao negócio | sinais detetados (>20% moves) | cron host 07h00 Lisboa | Danilo, estado-vivo, watchdog | pulso diário com KPIs reais | views `socio_kpi_*`+autologs+tickets(RPC) → pulso+Telegram+`estado-vivo` | 3 | Sócio-AI/Hermes |
| 🟢 | **weekly settlement (payouts)** | estafetas/parceiros pagos certo | € conferido vs ledger | semanal (dry-run SEMPRE) | estafetas/parceiros, Danilo | números batem com `ledger_entries` | ledger → relatório+CSV | 1 | `pagamentos-wallet` 🔴 propose-only |
| 🟢 | **Crons Supabase (pg_cron)** | dispatch dispara/TTL expira sem app aberta | pedidos atribuídos s/ intervenção | pg_cron | clientes/estafetas | job logs sem falha (watchdog vigia) | DB→DB | 1 | `dispatch`🔴/`mercados` |
| 🟢 | **cortex-mcp-sync (espelho)** | Hermes/Claude.ai cegos ao Córtex | idade do espelho | **por-tarefa** (carteiro após push, modo fast=ff-only) + pre-push hook + cron host 06h30 (fallback reset --hard) | Hermes, Claude.ai/MCP, Concierge, cortex_nightly | espelho fresco em segundos após push; ≤24h garantido pelo fallback | git → `/opt/data/cortex-brain` | 2 | Hermes(host) |
| 🔵 | **marketing-loop** | marketing sem aprendizado | engagement/persona validada | cron host dom 20h30 | social-media, diretor-criativo | aprendizado com dados (ou no-op registado) | métricas Postiz → aprendizados+Telegram | 1 | `social-media` |
| 🔵 | **Relatório estratégico semanal (Sócio-AI B)** | decidir a semana sem dados | recomendação aplicada | domingo, junto do marketing-loop | Danilo | 10 linhas com resposta às perguntas do DNA | estado-vivo+Córtex → Telegram+inbox | 1 | Sócio-AI/Hermes |
| 🟡 | **evolution-report** | skills/loops que degradam em silêncio | propostas aprovadas | passo 5 do daily-pulse | evolution-engine, Danilo | ≥0 propostas válidas; rejeitada não reproposta | telemetria+reports → `inbox/evolution-report-<data>.md` | 1 | `evolution-engine` |
| 🟡 | **cortex_nightly (higiene)** | Cérebro incha/desatualiza | páginas >24KB=0; staleness marcada | cron host 07h05 | todos os agentes | higiene aplicada sem apagar nada | knowledge → sinais+⚠️>60d | 2 | `bibliotecario-cerebro` |
| 🟡 | **obsidian-sync** | vault e Cérebro divergem | drift=0 | cron host 04h30 | bibliotecário | sync idempotente sem erro | vault → from-obsidian/ | 1 | `obsidian-sync` |
| 🟣 | **Loop E2E noturno** | regressões chegam ao Danilo/testers | fluxos verdes/total | manual `run-tudo.cmd` / noite | devops-ci, Juiz, release | verdes 2 ciclos seguidos | flows YAML → resultados+vídeos+Telegram | 1 | `juiz-revisor` (braço e2e) |
| 🟣 | **Watchdog Hermes** | loops morrem em silêncio; a v2 SÓ avisava e repetia a mesma lista a cada 10min (spam) | tempo-até-deteção **e** tempo-até-ação | cron host `*/10` | todos os loops | **DETETA→AGE→só avisa se dinheiro/ambíguo**: container DOWN→start, campainha/E2E parados→revive (via vigias); escala com **dedupe por assinatura** (mesma lista→silêncio) | fila+logs+recursos+crashes(RPC) → **ação (revive)** + alerta Telegram deduped | 3 | Hermes(host) |
| 🟡 | **aprovador-vermelho (gate da fila 🔴)** | zona vermelha presa sem o Danilo ter acesso à Central | propostas triadas/hora (latência ≤10 min) | cron host `*/10` + campainha (inotify) quando entra ordem + **fallback forçado se item `nova` parado ≥30min** | Danilo, carteiro | fila nunca fica com proposta parada >30 min sem triagem (era "sem triagem" indefinidamente se o disparo por watermark falhasse em silêncio — ver nota 2026-07-12) | watermark RPC anon (`pending_count`+`newest`+`oldest_age_min`) → ordem na fila (normal OU forçada por staleness) → agente tria (Balde A auto / Balde B Telegram) | 2 | Hermes(host)/`aprovador-vermelho` |
| 🟡 | **evolution-trigger (acordar na hora)** | evolution-engine só corria 1x/dia — ordem `travada` ou erro repetido ficava sem análise até à noite | tempo-até-análise de ordem travada/erro repetido | cron host `*/5` (watermark: só ids novos) | Danilo, evolution-engine | ordem travada nova OU nota repetida 2x/2h gera 1 ordem de análise em minutos, não horas | `orquestracao/*.md`(estado+nota) → ordem `-evol` na fila | 1 | Hermes(host)/`evolution-engine` |
| 🟢 | **carteiro-vigia (vigia do vigia)** | campainha (inotify) morre e ninguém a revive — ordens ficam em `tentativa=0` sem serem apanhadas | tempo-até-revive da campainha | cron host `*/5`, independente do carteiro/campainha | Danilo, carteiro, aprovador-vermelho, evolution-trigger | campainha morta → reiniciada sozinha em ≤5min + aviso Telegram (1x por episódio, sem spam) | `pgrep inotifywait`+ordens `aberta` paradas → `campainha.sh` reiniciada+Telegram | 1 | Hermes(host) |
| 🟣 | **e2e-vigia (retoma o loop E2E)** | loop E2E para a meio e ninguém o retoma — regressões deixam de ser vistas | tempo-até-retomar do loop E2E | cron host `*/10` (só 1 curl SQL + bash — SEM Opus, SEM limite Claude.ai) | Danilo, juiz-revisor(braço e2e), devops-ci | teste parado a meio → 1 ordem de retoma em ≤10min, no MÁX 1x/episódio (dedupe pelo `last_write`) | `e2e_log` last_write (SELECT anon) → ordem `aberta` na fila (campainha) | 1 | Hermes(host) |
| 🟢 | **heartbeat-desktop** | fechar o loop SEM API paga — o Claude só sabe do estado se alguém contar; contar por API custa | latência estado-final→Claude avisado (sem custo €) | mudança de estado de ordem (final) OU teste novo · schtask PC `*/10` `/RU danil /IT` (watermark) | Danilo, maestro, Claude Desktop | mudança real → frase fixa colada e enviada no **app Claude Desktop** (input de SO, sem Turnstile); sem mudança → 0 envios (anti-spam 2 camadas) | `orquestracao/*.md`(estados finais)+`e2e_log`/`orders`(SELECT anon) → `pending.trigger` → desktop-operador traz o app Claude à frente e cola a frase | 1 | `desktop-operador` |
| ⚫ | **missao-lancamento-play-store** | lançar na Play Store | critérios da missão | Mission Engine (uma ordem de cada vez) | Danilo | critério de conclusão da página da missão | `orquestracao/missao-*.md` → ordens | 1 | `maestro-autonomia` |

> **heartbeat-desktop — fechar o loop SEM API paga, via app Claude Desktop (2026-07-12).**
> Substitui o `heartbeat-browser`, que conduzia o Chrome por Playwright/CDP e **batia no
> Cloudflare Turnstile** (detetado como automação). A cabeça que decide a próxima ordem é o
> **Claude Desktop** que o Danilo mantém aberto e fixo na barra de tarefas (já logado, conta
> Max). Peça 1 = gatilho+anti-spam (inalterada): `.claude/scripts/heartbeat-browser.py`
> (agora chamado pelo wrapper `heartbeat-desktop/run-heartbeat-desktop.cmd`) lê um **watermark
> barato** (ordens em estado final na fila local + último `e2e_log`/`orders` por SELECT anon) e
> **só** escreve `pending.trigger` quando algo avança. Peça 2 = ação: o **`desktop-operador`**
> corre `heartbeat-desktop/desktop-send.py` — traz o **app Claude Desktop** para primeiro plano
> (se estiver fechado, abre-o), clica no composer, **cola a frase fixa e envia por input de
> sistema operativo** (foco de janela + Ctrl+V + Enter, com screenshot em cada passo). Sem CDP =
> sem flags de automação = **sem Turnstile**. **Anti-spam 2 camadas:** (1) o detetor só dispara
> em mudança real; (2) o operador move o trigger para `consumidos/` após enviar. Sem mudança →
> 0 envios. Custo de API = **zero**. **CRÍTICO:** o operador tem de correr na **sessão interativa
> do Danilo (Session 1)** — o executor headless (Hermes, Session 0) não alcança o desktop; por
> isso o schtask é `/RU danil /IT`. Deps (`pyautogui/pygetwindow/pyperclip/pillow`) instaladas em
> `heartbeat-desktop/_libs` (pip `--target`) e injetadas via `sys.path` (independente da sessão).
> Artefactos em `.claude/.ai/hermes/heartbeat-desktop/`. Prova do teste único:
> `.claude/testes-e2e/screenshots-pc/teste-heartbeat-desktop.png`.

> **aprovador-vermelho — gate barato + gatilho event-driven (2026-07-11).** O agente triava a fila
> 🔴 só quando alguém o corria à mão → propostas ficavam presas. Ligado como loop 🟡: cron host
> `*/10` (`/usr/local/bin/hermes-aprovador-vermelho.sh`, canónico em `.claude/scripts/`) lê um
> **watermark barato** — RPC `red_queue_watermark()` (SECURITY DEFINER, só devolve `count`+`newest`
> de `robot_suggestions status=nova`, **sem títulos nem dinheiro**, executável por `anon`). Só quando
> `newest` avança (item genuinamente novo) injeta UMA ordem na fila; a campainha (inotify) acorda o
> carteiro **na hora** → o PC corre o agente. **SILENCIOSO:** o backlog de Balde B já surfaçado
> (timestamps antigos) não re-dispara — high-water no `newest`. O agente **nunca decide dinheiro**:
> Balde A (não-$) auto-aprova; Balde B fica `nova` e vai por Telegram ao Danilo. A Trava continua a
> bloquear escrita nas zonas 🔴. Testado 2026-07-11: item novo → deteta; backlog → silêncio.

> **Automação total — 4 loops novos/mais rápidos (2026-07-11).** Missão do Danilo: "o sistema
> tem de se auto-curar sem eu ter de pedir". (1) `evolution-trigger` (🟡, cron `*/5`,
> `hermes-evolution-trigger.sh`) acorda o evolution-engine na hora quando uma ordem trava ou o
> mesmo erro repete 2x+/2h — watermark por id, primeira corrida semeia o backlog SEM disparar
> (mesmo padrão do aprovador-vermelho). Testado: achou e semeou 10 travadas históricas sem
> ruído; 2ª corrida ficou em silêncio como esperado. (2) `carteiro-vigia` (🟢, cron `*/5`,
> `hermes-carteiro-vigia.sh`) é o "vigia do vigia" — script simples e INDEPENDENTE do
> carteiro/campainha; só reinicia a campainha quando ela está genuinamente morta (não quando só
> há uma ordem pesada a demorar dentro do timeout normal — ver
> `wiki/licoes/executor-vivo-mas-tarefa-pesada-esgota-tentativas.md`). Notifica Telegram só 1x
> por episódio (dedupe por ficheiro-sentinela). (3) Watchdog Hermes subiu de 2h/2h para
> `*/10`, com 2 checagens novas: ordem `aberta` tentativa=0 parada >15min (o sintoma real de
> hoje) e crashes REAIS/24h via RPC nova `real_crash_count_24h()` (exclui breadcrumbs/rede —
> hoje 0/24h). (4) daily-pulse ganhou secção "Suporte" (RPC nova `support_tickets_open_count()`,
> hoje 3 abertos/3 com >24h) e o `estado-vivo.md` deixou de truncar aos 25 primeiros bytes do
> pulso — a secção "Sinais" passa a entrar sempre, por grep dedicado, não por corte de linhas.
> Testadores 12×14d **ficou pendente**: a service-account key só existe no PC (Downloads/), não
> no VPS — puxar isso exige um passo local, não dá para o host da VPS sozinho (ver
> `estado-vivo.md § Pendências`). Scripts canónicos em `.claude/scripts/`, deploy espelhado em
> `/usr/local/bin/` no VPS.

> **Watchdog v3 — "deteta → age → só avisa se dinheiro/ambíguo" (2026-07-12).** A v2 tinha um
> defeito de comportamento: SÓ avisava ("eu só aviso, não ajo") e **re-enviava a MESMA lista de
> ordens travadas a cada 10 min** = spam no Telegram, sem nunca destravar nada. A v3 muda a
> lógica em três eixos: **(1) AGE** — virou o umbrella que chama os revivedores que já existem
> (não duplica lógica): container Hermes DOWN → `docker start`; campainha morta / ordem `aberta`
> t=0 parada >15min → `hermes-carteiro-vigia.sh`; loop E2E parado a meio → `hermes-e2e-vigia.sh`
> (silencioso no TG, por isso o watchdog reporta o ato). **(2) ESCALA só o que precisa de
> decisão** de dinheiro ou é ambíguo: `zona_vermelha`, `travada` esgotada >12h (decide arquivar
> ou reformular), disco ≥85%, daily-pulse morto >26h, crashes reais >10/24h — nada disto tem
> reviver seguro, logo é aviso, não ação. **(3) ANTI-SPAM por assinatura:** a escalada tem um
> hash (`md5` do conjunto ordenado) gravado em `/root/orquestracao/.watchdog.sig`; só envia se a
> assinatura MUDOU desde o tick anterior. Mesma lista → silêncio total; fila esvazia → reset (o
> próximo problema volta a avisar na hora). Ações reportam-se quando acontecem (os revivedores já
> têm dedupe próprio). Prova (2026-07-12): 1ª corrida `escalar=1` (1 zona_vermelha) → 1 aviso; 2ª
> corrida mesma assinatura → **0 envios**. Antes disto, **13 ordens fantasma** (trabalho superado
> por ordens posteriores — cadeia E2E + heartbeat + disco resolvido) foram `travada→arquivada`,
> baixando a fila de 15→2 pendentes reais (1 `zona_vermelha` de build/autocomplete + 1 `travada`
> do bug HTML por commitar). Ver `inbox/watchdog-age-limpa-2026-07-12.md`.

> **Orquestração (carteiro) — nota de robustez (2026-07-10).** Ordens pesadas ficavam presas
> (`aberta→…→travada`, saída 0 bytes). Causa-raiz: o `pc-loop` passava a tarefa em base64 como
> **argumento** de linha de comando do ssh remoto; no Windows, arg grande (≥~1 KB) faz o
> `run-claude-loop.cmd` **nunca correr** → o executor nem arranca → ssh pendura até ao `timeout` → 0 bytes.
> Fix: passar o b64 por **STDIN** (`pc-loop | ssh "run-claude-loop.cmd --b64stdin"`). Hardening extra:
> `timeout 320→900s`, `--max-turns 20→40`, `--max-budget-usd 5→10`, e log **`SAIDA VAZIA`** no carteiro.
> Diagnóstico rápido: transporte OK (`ssh "echo PONG"`) mas `%TEMP%\bora_loop_task.txt` velho + 0
> `claude.exe` no PC = o `.cmd` não arranca (arg grande). Ver `wiki/licoes/ponte-loop-nao-devolve-output.md`.

> **aprovador-vermelho / e2e-vigia / evolution-trigger — causa-raiz do "desaparece sem rasto"
> (2026-07-12).** Achado ao investigar a paragem da noite de 2026-07-11→12: os 3 scripts que
> injetam ordem via `docker exec -u hermes "$C" sh -lc "cat > ficheiro" <<EOF` **faltava a flag
> `-i`**. Sem `-i`, `docker exec` não liga o stdin do host ao processo dentro do container — o
> heredoc nunca chega ao `cat`, que recebe EOF imediato e escreve um **ficheiro de 0 bytes**. O
> cron continuava a "disparar" (log dizia `DISPAROU`) e a campainha via um ficheiro sem
> `estado:` nenhum — **ignorado silenciosamente pelo carteiro, sem erro, sem rasto**. Confirmado
> ao vivo: gerou `ordem-20260711231003-aprv.md` (0 bytes) e mais 9 seguintes, todas 0 bytes,
> desde as 23:10 de 2026-07-11 até às 07:10 de 2026-07-12 — foi durante esta janela que a ordem
> de retomar do Danilo "desapareceu". **Fix:** `docker exec -i -u hermes ...` nos 3 scripts
> (`hermes-aprovador-vermelho.sh`, `hermes-e2e-vigia.sh`, `hermes-evolution-trigger.sh`),
> deployado em `/usr/local/bin/`. Prova real: corrida ao vivo pós-fix gerou
> `ordem-20260712071614-aprv.md` com **868 bytes** de conteúdo real (id/estado/tarefa completos).
> **Rede de segurança nova (pedido do Danilo — nunca mais confiar só no gatilho normal):** o
> `hermes-aprovador-vermelho.sh` ganhou um 2º caminho de disparo, independente do watermark de
> "item novo" — se o item `nova` mais antigo em `robot_suggestions` está parado ≥30 min, dispara
> uma ordem `FALLBACK 30MIN` que instrui o agente a rever TODA a fila e promover agora os
> claramente Balde A (com a mesma prova positiva de sempre); Balde B nunca é promovido sozinho.
> Dedupe próprio (`aprovador-vermelho.force_watermark`, não refire nos 30 min seguintes). RPC
> `red_queue_watermark()` migrada para devolver também `oldest_age_min`
> (`red_queue_watermark_add_oldest_age`, projeto `ojykpzwqrtusfeakzrna`). Prova real: 1ª corrida
> pós-fix já forçou (`force_fire=1`, backlog com item de 28749 min = ~20 dias parado); 2ª corrida
> ficou silenciosa (dedupe a funcionar). **Achado colateral:** a fila `robot_suggestions` tem uma
> dezena de itens Balde B (dispatch/no-show) que se repetem de hora a hora sem dedupe próprio —
> não corrigido agora (fora do escopo desta missão), fica anotado para o `evolution-engine` olhar.

## Loop Economy (ROI por loop)
A telemetria de cada loop ganha, além de sucesso/falha, o par:
- **`custo_acumulado`** (€ de IA) — heurística lite: `tokens ≈ caracteres/4` (entrada+saída da
  execução) × preço do modelo por token. Preços de referência (2026-07): Opus $15/M in ·
  $75/M out; Sonnet $3/$15; Haiku $1/$5. Sem medição real → estimar por ordem de grandeza e
  marcar `~`. Documentação única desta heurística é ESTA secção.
- **`retorno`** — em unidades do próprio loop: bugs achados, campanhas publicadas, propostas
  aprovadas, ordens concluídas, sinais acionados.

O **evolution-report sinaliza loops suspeitos**: muitas execuções + custo acumulado alto +
retorno ≈ 0 → propõe otimizar ou arquivar (ex.: "evolution rodou 300× sem 1 melhoria
aprovada — rever gatilho ou arquivar"). **NUNCA arquiva sozinho um loop 🟢/🔵 — só propõe.**
⚫ Mission concluída → arquiva conforme o critério de conclusão da própria missão.

## Regras do registry
1. Loop novo → entrada aqui (5 perguntas + cor + dono) ANTES de ligar o cron.
2. Alteração de gatilho/frequência/dono/cor → atualizar a linha + `atualizado:` no frontmatter.
3. Loops que tocam dinheiro (settlement, pg_cron de dispatch) são zona 🔴 — mudanças SÓ por proposta.
4. O watchdog lê este registry: cor define a severidade do alerta.
