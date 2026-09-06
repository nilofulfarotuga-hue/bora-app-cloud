---
id: inventario-vps-2026-07-13
tipo: relatorio
origem: [pedido direto — levantamento de estado da VPS, complementa inventario do banco]
ultima_confirmacao: 2026-07-13
zona: verde (só leitura — nada ativado)
confianca: auto
---

# Inventário de estado — VPS + PC (2026-07-13, ~21h UTC)

**Regra seguida:** só inventariar. Nada foi ativado, reativado, desativado ou editado nesta
tarefa — todos os comandos foram de leitura (`crontab -l`, `ls`, `grep`, `Get-ScheduledTask`).

## 1 — Crontab da VPS (`crontab -l`, utilizador root)

| Linha | Estado | Recomendação | Motivo |
|---|---|---|---|
| `*/10 hermes-voice-guard.sh` | ✅ ativo | manter | guarda de voz do Hermes, sem relação com o spam de hoje |
| `*/5 hermes-heartbeat.sh` | ✅ ativo | manter | heartbeat base do agente |
| `30 4 obsidian-sync.sh` | ✅ ativo | manter | sync diário do vault, unidirecional, sem custo |
| `*/2 hermes-gateway-watchdog.sh` | ✅ ativo | manter | watchdog do gateway, alta frequência mas leve |
| `0 7 hermes-daily-pulse.sh` (CRON_TZ Lisboa) | ✅ ativo | manter | Sócio-AI Fase A, read-only; desde hoje também corre `evolution_engine.py --dry-run` 1×/dia (ver linha evolution-trigger abaixo) |
| `30 6 cortex-mcp-sync` (docker exec sync-brain.sh) | ✅ ativo | manter | sync do Cérebro para o espelho do container |
| `5 7 cortex-nightly` (export_signals + cortex_nightly.py) | ✅ ativo | manter | consolidação noturna do Cérebro |
| `17 * carteiro.sh` (`orq-fallback`) | ✅ ativo | manter | rede de segurança horária caso a campainha (inotify) falhe |
| `30 20 * * 0 marketing-loop-weekly.sh` | ✅ ativo | manter | loop semanal de marketing, domingo à noite |
| `*/10 hermes-watchdog.sh` (`watchdog-loops`) | ✅ ativo | manter, mas **observar** | subiu de 2h/2h→10min em 2026-07-11 ("automação total"); não está entre os 3 crons acusados de spam nesta sessão, mas é o de maior frequência ainda ativo — vale confirmar que não está a gerar ordens sintéticas como o evolution-trigger antigo |
| `0 21 * * 0 hermes-relatorio-semanal.sh` | ✅ ativo | manter | Sócio-AI Fase B, semanal |
| `*/10 hermes-aprovador-vermelho.sh` | ❌ **DESATIVADO** (comentário `# DESATIVADO 2026-07-13 protecao-total`) | **manter desligado por agora** | ver secção 2 — função de roteamento continua válida, mas o script não ganhou lógica de backoff; reativar `*/10min` reproduziria o mesmo spam (15 corridas seguidas sem informação nova, confirmado em `aprovador-vermelho-2026-07-13-15a-corrida.md`) |
| `*/5 hermes-e2e-vigia.sh` | ❌ **DESATIVADO** (mesmo comentário) | **manter desligado** | função (tocar a campainha para reviver o loop E2E parado) está hoje coberta pelo `hermes-carteiro-vigia.sh` (CASO 2 — genérico, reage a estagnação real em vez de sondar a fila a cada 10min) + pelo schtask `BoraE2E_LoopNoturno` no PC, que já corre sozinho e com sucesso (ver secção 3) |
| `hermes-evolution-trigger.sh` | ⚫ **REMOVIDO da crontab** (nem comentado — já não está na lista) | **não repor** | causa raiz do spam de ordens `-evol` (loop autorreferencial, documentado em `evolution-engine-religado-2026-07-13.md`); o motor foi redesenhado para ser **reativo**: 1× dia via `hermes-daily-pulse.sh --dry-run` (não persiste, não gera ordem) + execução real só em sessão manual/missão legítima. Repor o cron replicaria exatamente o incidente que motivou o religamento de hoje |
| `*/5 hermes-carteiro-vigia.sh` | ✅ ativo | manter | reforçado hoje (`Jul 13 19:11` no disco) com CASO 1.5 — deteta `.pausa-rate-limit` expirada e retoma sozinho; **já está deployado e vivo na VPS**, ao contrário do que constava como pendência em `reengenharia-loop-resiliencia-2026-07-13.md` (essa nota está desatualizada — o deploy aconteceu depois) |

**Nota:** `/root/crontab_new.txt` é um ficheiro de rascunho **obsoleto** encontrado na VPS — ainda
tem `aprovador-vermelho-loop` e `evolution-trigger` ativos e **não** tem o fix de rate-limit do
carteiro-vigia. Não é a crontab viva (`crontab -l` já confere, foi lido diretamente do
crond), mas é um risco silencioso: se alguém correr `crontab /root/crontab_new.txt` por engano,
repõe o spam. Sinalizado, não apagado (fora do escopo desta tarefa só-leitura).

## 2 — Agentes do `exercito.md` dependentes de gatilho na VPS

| Componente | Estado | Recomendação | Motivo |
|---|---|---|---|
| `aprovador-vermelho` (agente 🟡, 30.º) | 🟡 **dormente** (cron desligado) | **função ainda existe, mas execução automática deve continuar parada** | A triagem (Balde A leitura-pura vs Balde B dinheiro) continua correta por desenho — mas o problema nunca foi a lógica de bloqueio, foi a **cadência**: os mesmos 5 itens Balde B (`268aad47`, `abeca5d7`, `85d8911b`, `d9df69ed`, `bea503a3`, todos dispatch/dinheiro) foram reconfirmados **15 vezes seguidas** sem novidade, a cada ~6min no fim. Isso não é "triagem a bloquear demais" — é ausência de backoff no `hermes-aprovador-vermelho.sh`. Reativar sem essa correção reproduz o mesmo padrão. Pendência já escalada ao `maestro-autonomia` (ver `project_aprovador_vermelho_central.md`) |
| `evolution-engine` (agente 🟡, 27.º) | ✅ religado hoje, **desenho reativo correto** | nenhuma ação — já está no estado desejado | Deixa de depender de cron; lê relatórios em `inbox/` quando invocado + 1×/dia dry-run barato via daily-pulse. Ver `evolution-engine-religado-2026-07-13.md` |
| `maestro-autonomia` (agente 🟡, 26.º) | ⚪ sem gatilho de cron próprio (correto por desenho) | nenhuma ação | Corre dentro de sessões/missões, não como daemon; não apareceu órfão em nenhum grep |
| `hermes-autoheal.sh` (mecanismo de auto-cura Fase 5, maestro↔Juiz) | ❓ **órfão** — existe em `/usr/local/bin/`, mas grep não encontrou **nenhum** script (cron ou outro) que o invoque | **investigar antes de decidir** | Não está na crontab e nenhum outro script no host o chama. Pode ser por desenho (RPC `maestro_record_juiz_evaluation` corre inline dentro da sessão do Juiz, não via shell na VPS) — mas vale o Danilo confirmar, porque hoje **nada** dispara este ficheiro |
| `hermes-hook-conclusao.sh` | ❓ **órfão** — mesma situação, sem caller encontrado em `/usr/local/bin/` nem `/root/orquestracao/` | **investigar** | Nome sugere hook de fim-de-ordem do carteiro; pode estar registado como git hook (não coberto por este grep) — não confirmado nesta sessão |
| Braços do Juiz (`e2e-test-builder`, `checkout-fixer`) | ⚪ sem cron próprio (correto) | nenhuma ação | Invocados pelo `juiz-revisor` dentro da sessão, nunca por cron |

## 3 — Schtasks / processos de fundo do PC

| Tarefa (PC) | Estado | Último resultado | Próxima execução | Recomendação |
|---|---|---|---|---|
| `Bora-heartbeat-desktop` | ✅ **Running** agora | — (em execução) | 22:16 | manter — endurecida hoje (`ExecutionTimeLimit` 72h→5min, `RestartCount=3`), ver `reengenharia-loop-resiliencia-2026-07-13.md` |
| `BoraAutoLimpezaRAM` | ✅ ativa, `*/15min` | `0` (sucesso) | 22:15 | manter — nova hoje, testada ao vivo 3×, nunca matou processo `claude` legítimo |
| `BoraE2E_LoopNoturno` | ✅ ativa, horária | `0` (sucesso) | 22:38 | manter — cobre autonomamente o papel que o `hermes-e2e-vigia.sh` (VPS) fazia por spam |
| `BoraTesteFechadoMonitor` | ✅ ativa, diária | `0` (sucesso) | amanhã 09:03 | manter |
| `BoraE2E_MonitorProva` | ⚪ **dormente/esgotada** — trigger único, já disparou 1× (2026-07-11 23:59:59), sem `NextRunTime`, `LastTaskResult=1` (falhou ou não fez nada) | `1` | nenhuma (trigger consumido) | **decisão do Danilo**: parece uma tarefa de "prova" pontual, provavelmente obsoleta desde que `BoraE2E_LoopNoturno` assumiu o papel permanente; seguro remover se confirmado, não reativar sem entender por que falhou |

## 4 — Outros watchers / timers

- **systemd timers da VPS** (`systemctl list-timers`): os 17 listados são todos **stock Ubuntu**
  (apt, logrotate, fstrim, man-db, sysstat, dpkg-backup, fwupd) — nenhum específico do Bora/Hermes
  corre via systemd; tudo o que é nosso vive em crontab. Nada parado aqui que devesse estar ativo.
- **Containers docker** (`docker ps`): `cortex-mcp` (4 dias), `hermes-agent-fvnc-hermes-agent-1`
  (8 dias), `searxng` (7 dias), `traefik-traefik-1` (2 semanas) — todos `Up`, nenhum reiniciado
  recentemente, nenhum crash-loop visível.
- **`/etc/cron.d/`**: só ficheiros de sistema (`sysstat`, `e2scrub_all`, `docker-image-prune`) —
  nada nosso aqui, confirma que tudo do Bora vive na crontab do root.

## Resumo da pergunta central

Sobre os 3 itens comentados hoje para parar spam (`evolution-trigger`, `aprovador-vermelho`,
`e2e-vigia`): a causa raiz nos 3 casos foi a mesma — **cron de alta frequência (`*/5` ou `*/10min`)
a empurrar trabalho para uma fila processada em série**, entupindo o `carteiro.sh` (confirmado em
`diagnostico-executor-headless-2026-07-13.md`: 82 ficheiros `-aprv`/`-e2e` acumulados, RAM do PC a
0.42 GB livres). O ajuste da zona vermelha (gate `zona_vermelha()`) e o religamento do
evolution-engine **não removem essa causa raiz** para os outros dois:
- `evolution-trigger` → certo manter fora, já foi redesenhado (não é mais cron, é reativo).
- `aprovador-vermelho` → certo manter fora até o `hermes-aprovador-vermelho.sh` ganhar backoff
  (a pendência já está escalada, não é decisão nova desta tarefa).
- `e2e-vigia` → certo manter fora, função redundante com `carteiro-vigia` + `BoraE2E_LoopNoturno`.

Nenhum dos três deveria voltar tal como estava configurado.

---

INVENTARIO VPS COMPLETO - 6 parados/dormentes (aprovador-vermelho-cron, e2e-vigia-cron,
evolution-trigger-cron, hermes-autoheal.sh-orfao, hermes-hook-conclusao.sh-orfao,
BoraE2E_MonitorProva-esgotada), 0 recomendados reativar tal como estavam (2 pendentes de
investigação antes de qualquer decisão: hermes-autoheal.sh e hermes-hook-conclusao.sh).
