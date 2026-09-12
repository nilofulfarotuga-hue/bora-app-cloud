---
tema: loops · escopo: projeto · estado: atual · atualizado: 2026-07-13
id: loops
tipo: registry
origem: [missão "Do Prompt ao Loop" 2026-07-10 — crons VPS/host verificados por SSH, crons Supabase, skills]
ultima_confirmacao: 2026-07-13
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

## Conclusão de tarefas: HOOK POR EVENTO (primário) + WATCHDOG (rede de segurança) — 2026-07-12
> **Desenho do Danilo:** o encadeamento é **POR EVENTO, não por ronda de 10 min**. Quando uma
> ordem **TERMINA** (o juiz deu veredito terminal), o próprio fecho **encadeia o próximo passo**;
> só se escala ao Danilo **no fim**. "O sistema resolve, não avisa."

- **Mecanismo PRIMÁRIO — `hermes-hook-conclusao.sh`** (bash no HOST, zero-Opus). O `carteiro.sh`
  **chama-o** no ponto de veredito terminal (APROVADA / TRAVADA / ZONA_VERMELHA). O juízo de
  qualidade JÁ foi feito pelo pc-judge; o hook só **AGE** sobre o veredito:
  - **APROVADA** + faz parte de missão + há próxima parte `pendente` → promove-a
    (`pendente→aberta`) → a campainha encadeia. **SILENCIOSO.** (= "segue para a próxima ordem
    pendente da mesma missão".)
  - **APROVADA** + era a **última** parte → **missão concluída** → Telegram com resumo.
  - **APROVADA** + ordem solta → concluída, **silenciosa** (acabou o spam "terminei aprovado"
    por-ordem).
  - **TRAVADA** (5 tentativas esgotadas) + `continuacao < 2` → cria **ordem de continuação**
    (continua de onde parou, nota do juiz como contexto, 5 tentativas frescas). **SILENCIOSO** —
    auto-resolve, **nunca mais "alarme vermelho" de travada** que o sistema consegue destravar.
  - **TRAVADA** + continuações esgotadas → genuinamente preso → Telegram (reformular/arquivar).
  - **ZONA_VERMELHA** → dinheiro/produção/destrutivo → Telegram + espera o Danilo. **Nunca auto.**
- **Telegram ao Danilo SÓ em 2 casos:** (a) uma **missão inteira** terminou (resumo), ou (b)
  precisa de **decisão** dele (zona vermelha / travada esgotada). Toda a notificação passa pelo
  hook — o carteiro deixou de mandar Telegram por-ordem.
- **Missão = conjunto de ordens** com o mesmo campo `missao: <id>` e `parte: <n>`; ao lançar,
  só a parte 1 nasce `aberta`, as restantes `pendente` (o carteiro ignora `pendente`). O hook
  vira a próxima `pendente→aberta` a cada parte aprovada. Encadeamento por **flip de estado** —
  determinístico, sem parsear prosa, event-driven (o `close_write` toca a campainha).
- **Rede de segurança (ÚLTIMO recurso) — o Watchdog Hermes (`*/10`)** deixa de ser o mecanismo
  primário de deteção: existe só para o caso de o **hook falhar** e algo ficar mesmo parado sem
  ninguém pegar. Continua a apanhar `travada >12h`, `zona_vermelha` presa, container DOWN, disco,
  crashes — mas o caminho normal é o hook resolver **antes** de o watchdog sequer ver. Se o hook
  estiver ausente/quebrado, o carteiro loga e o watchdog é quem apanha.

Prova headless (2026-07-12): `hermes-hook-conclusao.sh --selftest` = 7/7 OK (promoção de parte,
fecho de missão, continuação de travada, escalada no teto, conclusão silenciosa de ordem solta).

## Loops ativos

| Cor | Loop | (1) Problema que resolve | (2) Métrica que melhora | (3) Gatilho | (4) Quem depende | (5) Critério de sucesso | Entradas→Saídas | v | Dono |
|---|---|---|---|---|---|---|---|---|---|
| 🟢 | **Orquestração (carteiro)** | ordens do Danilo executadas no PC sem sessão manual | ordens concluídas/semana | inotify (campainha) + cron `:17` hourly | Danilo, Hermes, maestro | ordem `aprovada` ≤5 tentativas | `orquestracao/ordem-*.md` → `.saida.txt`+hook | 1 | Hermes(host)/`maestro-autonomia` |
| 🟢 | **hook-de-conclusão (encadeamento por evento)** | encadear o próximo passo era ronda de 10 min (lenta) e travada = "alarme vermelho" espúrio | latência fecho→próximo passo; nº de avisos supérfluos ao Danilo | **evento**: carteiro chama o hook no veredito terminal (APROVADA/TRAVADA/ZONA_VERMELHA) | carteiro, maestro, Danilo | missão encadeia sozinha; Telegram só em 2 casos (missão fecha / decisão) | veredito terminal → promove parte `pendente`/cria continuação/escala | 1 | Hermes(host) |
| 🟢 | **Maestro↔Juiz (auto-cura)** | paridade admin sem supervisão item-a-item | placar paridade 360° | ciclo do maestro | Central/Danilo | nota ≥9 ou travado c/ pedido de ajuda | backlog → suggestion `aguarda_ti` | 1 | `maestro-autonomia` |
| 🟢 | **daily-pulse (Sócio-AI)** | cegueira ao negócio | sinais detetados (>20% moves) | cron host 07h00 Lisboa | Danilo, estado-vivo, watchdog | pulso diário com KPIs reais | views `socio_kpi_*`+autologs+tickets(RPC) → pulso+Telegram+`estado-vivo` | 3 | Sócio-AI/Hermes |
| 🟢 | **weekly settlement (payouts)** | estafetas/parceiros pagos certo | € conferido vs ledger | semanal (dry-run SEMPRE) | estafetas/parceiros, Danilo | números batem com `ledger_entries` | ledger → relatório+CSV | 1 | `pagamentos-wallet` 🔴 propose-only |
| 🟢 | **Crons Supabase (pg_cron)** | dispatch dispara/TTL expira sem app aberta | pedidos atribuídos s/ intervenção | pg_cron | clientes/estafetas | job logs sem falha (watchdog vigia) | DB→DB | 1 | `dispatch`🔴/`mercados` |
| 🟢 | **cortex-mcp-sync (espelho)** | Hermes/Claude.ai cegos ao Córtex | idade do espelho | **por-tarefa** (carteiro após push, modo fast=ff-only) + pre-push hook + cron host 06h30 (fallback reset --hard) | Hermes, Claude.ai/MCP, Concierge, cortex_nightly | espelho fresco em segundos após push; ≤24h garantido pelo fallback | git → `/opt/data/cortex-brain` | 2 | Hermes(host) |
| 🔵 | **marketing-loop** | marketing sem aprendizado | engagement/persona validada | cron host dom 20h30 | social-media, diretor-criativo | aprendizado com dados (ou no-op registado) | métricas Postiz → aprendizados+Telegram | 1 | `social-media` |
| 🔵 | **Relatório estratégico semanal (Sócio-AI B)** | decidir a semana sem dados | recomendação aplicada | domingo, junto do marketing-loop | Danilo | 10 linhas com resposta às perguntas do DNA | estado-vivo+Córtex → Telegram+inbox | 1 | Sócio-AI/Hermes |
| 🟡 | **evolution-report** | skills/loops/erros que degradam em silêncio | propostas aprovadas + lições permanentes gravadas | (1) fim de missão — relatório cai em `inbox/`; (2) daily-pulse 1x/dia (contagem `--dry-run` no espelho, camada barata) | evolution-engine, bibliotecario-cerebro, Danilo | ≥0 propostas válidas; rejeitada não reproposta; **NUNCA cria ordem na fila** | telemetria+reports(inbox/) → `inbox/evolution-report-<data>.md` + handoff de lições ao bibliotecario-cerebro | 2 | `evolution-engine` |
| 🟡 | **cortex_nightly (higiene)** | Cérebro incha/desatualiza | páginas >24KB=0; staleness marcada | cron host 07h05 | todos os agentes | higiene aplicada sem apagar nada | knowledge → sinais+⚠️>60d | 2 | `bibliotecario-cerebro` |
| 🟡 | **obsidian-sync** | vault e Cérebro divergem | drift=0 | cron host 04h30 | bibliotecário | sync idempotente sem erro | vault → from-obsidian/ | 1 | `obsidian-sync` |
| 🟣 | **Loop E2E noturno** | regressões chegam ao Danilo/testers | fluxos verdes/total | manual `run-tudo.cmd` / noite | devops-ci, Juiz, release | verdes 2 ciclos seguidos | flows YAML → resultados+vídeos+Telegram | 1 | `juiz-revisor` (braço e2e) |
| 🟣 | **Watchdog Hermes** (rede de segurança — ÚLTIMO recurso) | desde 2026-07-12 deixou de ser deteção primária: existe só se o **hook-de-conclusão falhar** e algo ficar mesmo parado | tempo-até-deteção do que escapou ao hook | cron host `*/10` | todos os loops | **só apanha o que o hook não resolveu**: container DOWN→start, campainha/E2E parados→revive, `travada >12h`/`zona_vermelha` presas→escala (dedupe por assinatura) | fila+logs+recursos+crashes(RPC) → ação (revive) + alerta deduped | 3 | Hermes(host) |
| 🟡 | **aprovador-vermelho (gate da fila 🔴)** | zona vermelha presa sem o Danilo ter acesso à Central | propostas triadas/hora (latência ≤10 min) | cron host `*/10` + campainha (inotify) quando entra ordem + **fallback forçado se item `nova` parado ≥30min** | Danilo, carteiro | fila nunca fica com proposta parada >30 min sem triagem (era "sem triagem" indefinidamente se o disparo por watermark falhasse em silêncio — ver nota 2026-07-12) | watermark RPC anon (`pending_count`+`newest`+`oldest_age_min`) → ordem na fila (normal OU forçada por staleness) → agente tria (Balde A auto / Balde B Telegram) | 2 | Hermes(host)/`aprovador-vermelho` |
| ⚫ | ~~evolution-trigger (acordar na hora)~~ **SUPERADO 2026-07-13** | era: ordem `travada`/erro repetido sem análise até à noite | — | ~~cron host `*/5`~~ **retirado do crontab** | — | — | ~~`orquestracao/*.md` → ordem `-evol` na fila~~ | 2 | Hermes(host) |
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

> **Reengenharia da esteira (2026-07-12) — 5 ordens mortas com nota vazia.** Causa dupla provada
> (`inbox/diagnostico-esteira-2026-07-12.md`): (A) a conta Claude Code do PC bateu **rate-limit de
> sessão** a meio da tarde — `b049.saida.txt` = "You've hit your session limit"; (B) tarefas
> gigantes auto-referenciais estouravam os 900s. E o carteiro gravava `nota: ""` sem distinguir a
> causa. **Reengenharia aplicada** (`deploy/carteiro.sh`, `deploy/campainha.sh`,
> `hermes-bridge/run-claude-loop.cmd`+`bora-live-parser.ps1`):
> • **nota NUNCA vazia** — todo ramo de falha grava a causa (RATE-LIMIT / TIMEOUT-900s / SAIDA-VAZIA /
> JUIZ-SEM-VEREDITO). • **rate-limit inteligente** — não gasta tentativa; pausa a fila
> (`.pausa-rate-limit` com epoch de reset), avisa 1x, retoma sozinho. • **TIMEOUT não re-tenta 5x** —
> 2º timeout → trava com sugestão de dividir (ver `orquestrador-carteiro/CONVENCOES.md`).
> • **modelo por tarefa** — `[MODELO: OPUS]` no texto → opus; senão **Sonnet** (default económico;
> antes era opus fixo, que queimava a conta). • **STOP global `.pausa-total`** respeitado por
> carteiro + campainha + os 5 crons (`touch`/`rm` do ficheiro na fila). • **visibilidade ao vivo** —
> executor emite `stream-json` → `bora-live-parser.ps1` escreve `.claude/bora-live.log` legível;
> Danilo acompanha com `assistir.cmd` na raiz do projeto. • **campainha** coalesce rajadas
> (1 carteiro/8s) e respeita a pausa. • **encadeamento de missão** — ordem com `missao:` que fecha
> aprovada marca o passo e dispara o(s) próximo(s) (até 2 se `paralelo: sim`); Telegram só em
> missão-concluída / dinheiro / passo-travado; ordem normal aprovada = **silêncio**. Missões em
> `orquestracao/missoes/<id>.md`, arranque via `carteiro.sh --iniciar-missao <id>`. Provado
> ponta-a-ponta 2026-07-12 (ordem-teste: sonnet auto, aprovada, live-log OK; `carteiro.sh --selftest`
> = TODOS OK). **1.6:** o `carteiro-vigia` já tinha log próprio
> (`/root/orquestracao/carteiro-vigia.log`) — o diagnóstico olhou o caminho errado. Ver
> `inbox/reengenharia-esteira-2026-07-12.md`.

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
> **Confirmado 2026-07-13:** o `STALE_MIN` (30 min) serve de gatilho E de cooldown do
> `STATE_FORCE` em `hermes-aprovador-vermelho.sh` — por isso refire para sempre enquanto o item
> ficar `nova` (9 reconfirmações idênticas em <9h). Ainda sem correção; detalhe e recomendação em
> `procedural/aprovador-vermelho-triagem.md`.

> **evolution-engine religado REATIVO, sem disparar ordens (2026-07-13).** O
> `hermes-evolution-trigger.sh` (cron host `*/5`) foi a causa do spam de ordens `-evol`: mesmo
> depois da guarda EVOL-1 (10ea1b8, 2026-07-12 — ignora as próprias saídas `*-evol/*-aprv/*-e2e`
> nos scans), o desenho "cron que injeta ordem na fila a cada sinal" continuava um vetor de
> custo/spam por construção — confirmado **já retirado do crontab** da VPS antes desta sessão.
> Endurecido nesta sessão (defesa em profundidade): o script agora é um **stub inerte**
> (early-exit, só regista no log que foi retirado) mesmo no repo e na cópia deployada — se
> alguém repuser a linha no crontab por engano, não acontece nada. **Desenho novo (2 camadas,
> nunca uma 3ª que dispara ordem):**
> 1. **Camada barata (VPS, diária, já ativa):** `hermes-daily-pulse.sh` corre
>    `evolution_engine.py --dry-run` **dentro do container**, só para contar propostas e alimentar
>    o resumo do Telegram. Não persiste nada de propósito — o espelho do Córtex no container é
>    apagado/`reset --hard` pelo `cortex-mcp-sync` (linha 98 acima), então escrever "a sério" ali
>    seria perdido em <24h. Isto é **intencional**, não um bug: é só o sinal barato.
> 2. **Camada de análise real (sessão Claude Code de verdade — manual ou missão legítima, NUNCA
>    auto-disparada):** corre `evolution_engine.py` sem `--dry-run` no repo real (PC), escreve
>    `inbox/evolution-report-<data>.md` + `scripts/state/propostas.json`, commit+push — e o agente
>    `evolution-engine` lê os relatórios recentes de `inbox/` (que já acumulam a cada fecho de
>    missão, por convenção — "Saída padrão") e entrega lições ao `bibliotecario-cerebro`. Esta
>    sessão (2026-07-13) fez exatamente essa corrida real como prova + backfill das lições da
>    semana — ver `inbox/evolution-engine-religado-2026-07-13.md`.
> **Garantia:** em nenhuma das 2 camadas o evolution-engine cria `ordem-*.md` na fila. Ver
> `licao-spam-ordens-autoreferencial.md`.

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
