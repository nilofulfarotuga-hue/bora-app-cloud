---
tema: loops · escopo: projeto · estado: atual · atualizado: 2026-07-11
id: loops
tipo: registry
origem: [missão "Do Prompt ao Loop" 2026-07-10 — crons VPS/host verificados por SSH, crons Supabase, skills]
ultima_confirmacao: 2026-07-11
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
| 🟣 | **Watchdog Hermes** | loops morrem em silêncio | tempo-até-deteção | cron host `*/10` (subido de 2h/2h 2026-07-11) | todos os loops | alerta certo na cor certa; NUNCA age | fila+logs+recursos+crashes(RPC) → alerta Telegram | 2 | Hermes(host) |
| 🟡 | **aprovador-vermelho (gate da fila 🔴)** | zona vermelha presa sem o Danilo ter acesso à Central | propostas triadas/hora (latência ≤10 min) | cron host `*/10` + campainha (inotify) quando entra ordem | Danilo, carteiro | fila nunca fica com proposta parada >10 min sem triagem | watermark RPC anon → ordem na fila → agente tria (Balde A auto / Balde B Telegram) | 1 | Hermes(host)/`aprovador-vermelho` |
| 🟡 | **evolution-trigger (acordar na hora)** | evolution-engine só corria 1x/dia — ordem `travada` ou erro repetido ficava sem análise até à noite | tempo-até-análise de ordem travada/erro repetido | cron host `*/5` (watermark: só ids novos) | Danilo, evolution-engine | ordem travada nova OU nota repetida 2x/2h gera 1 ordem de análise em minutos, não horas | `orquestracao/*.md`(estado+nota) → ordem `-evol` na fila | 1 | Hermes(host)/`evolution-engine` |
| 🟢 | **carteiro-vigia (vigia do vigia)** | campainha (inotify) morre e ninguém a revive — ordens ficam em `tentativa=0` sem serem apanhadas | tempo-até-revive da campainha | cron host `*/5`, independente do carteiro/campainha | Danilo, carteiro, aprovador-vermelho, evolution-trigger | campainha morta → reiniciada sozinha em ≤5min + aviso Telegram (1x por episódio, sem spam) | `pgrep inotifywait`+ordens `aberta` paradas → `campainha.sh` reiniciada+Telegram | 1 | Hermes(host) |
| ⚫ | **missao-lancamento-play-store** | lançar na Play Store | critérios da missão | Mission Engine (uma ordem de cada vez) | Danilo | critério de conclusão da página da missão | `orquestracao/missao-*.md` → ordens | 1 | `maestro-autonomia` |

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

> **Orquestração (carteiro) — nota de robustez (2026-07-10).** Ordens pesadas ficavam presas
> (`aberta→…→travada`, saída 0 bytes). Causa-raiz: o `pc-loop` passava a tarefa em base64 como
> **argumento** de linha de comando do ssh remoto; no Windows, arg grande (≥~1 KB) faz o
> `run-claude-loop.cmd` **nunca correr** → o executor nem arranca → ssh pendura até ao `timeout` → 0 bytes.
> Fix: passar o b64 por **STDIN** (`pc-loop | ssh "run-claude-loop.cmd --b64stdin"`). Hardening extra:
> `timeout 320→900s`, `--max-turns 20→40`, `--max-budget-usd 5→10`, e log **`SAIDA VAZIA`** no carteiro.
> Diagnóstico rápido: transporte OK (`ssh "echo PONG"`) mas `%TEMP%\bora_loop_task.txt` velho + 0
> `claude.exe` no PC = o `.cmd` não arranca (arg grande). Ver `wiki/licoes/ponte-loop-nao-devolve-output.md`.

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
