---
tema: loops · escopo: projeto · estado: atual · atualizado: 2026-07-10
id: loops
tipo: registry
origem: [missão "Do Prompt ao Loop" 2026-07-10 — crons VPS/host verificados por SSH, crons Supabase, skills]
ultima_confirmacao: 2026-07-10
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
| 🟢 | **daily-pulse (Sócio-AI)** | cegueira ao negócio | sinais detetados (>20% moves) | cron host 07h00 Lisboa | Danilo, estado-vivo, watchdog | pulso diário com KPIs reais | views `socio_kpi_*`+autologs → pulso+Telegram+`estado-vivo` | 2 | Sócio-AI/Hermes |
| 🟢 | **weekly settlement (payouts)** | estafetas/parceiros pagos certo | € conferido vs ledger | semanal (dry-run SEMPRE) | estafetas/parceiros, Danilo | números batem com `ledger_entries` | ledger → relatório+CSV | 1 | `pagamentos-wallet` 🔴 propose-only |
| 🟢 | **Crons Supabase (pg_cron)** | dispatch dispara/TTL expira sem app aberta | pedidos atribuídos s/ intervenção | pg_cron | clientes/estafetas | job logs sem falha (watchdog vigia) | DB→DB | 1 | `dispatch`🔴/`mercados` |
| 🟢 | **cortex-mcp-sync (espelho)** | Hermes cego ao Córtex | idade do espelho | cron host 06h30 | Hermes, Concierge, cortex_nightly | espelho ≤24h | git → `/opt/data/cortex-brain` | 1 | Hermes(host) |
| 🔵 | **marketing-loop** | marketing sem aprendizado | engagement/persona validada | cron host dom 20h30 | social-media, diretor-criativo | aprendizado com dados (ou no-op registado) | métricas Postiz → aprendizados+Telegram | 1 | `social-media` |
| 🔵 | **Relatório estratégico semanal (Sócio-AI B)** | decidir a semana sem dados | recomendação aplicada | domingo, junto do marketing-loop | Danilo | 10 linhas com resposta às perguntas do DNA | estado-vivo+Córtex → Telegram+inbox | 1 | Sócio-AI/Hermes |
| 🟡 | **evolution-report** | skills/loops que degradam em silêncio | propostas aprovadas | passo 5 do daily-pulse | evolution-engine, Danilo | ≥0 propostas válidas; rejeitada não reproposta | telemetria+reports → `inbox/evolution-report-<data>.md` | 1 | `evolution-engine` |
| 🟡 | **cortex_nightly (higiene)** | Cérebro incha/desatualiza | páginas >24KB=0; staleness marcada | cron host 07h05 | todos os agentes | higiene aplicada sem apagar nada | knowledge → sinais+⚠️>60d | 2 | `bibliotecario-cerebro` |
| 🟡 | **obsidian-sync** | vault e Cérebro divergem | drift=0 | cron host 04h30 | bibliotecário | sync idempotente sem erro | vault → from-obsidian/ | 1 | `obsidian-sync` |
| 🟣 | **Loop E2E noturno** | regressões chegam ao Danilo/testers | fluxos verdes/total | manual `run-tudo.cmd` / noite | devops-ci, Juiz, release | verdes 2 ciclos seguidos | flows YAML → resultados+vídeos+Telegram | 1 | `juiz-revisor` (braço e2e) |
| 🟣 | **Watchdog Hermes** | loops morrem em silêncio | tempo-até-deteção | cron host 2h/2h | todos os loops | alerta certo na cor certa; NUNCA age | fila+logs+recursos → alerta Telegram | 1 | Hermes(host) |
| ⚫ | **missao-lancamento-play-store** | lançar na Play Store | critérios da missão | Mission Engine (uma ordem de cada vez) | Danilo | critério de conclusão da página da missão | `orquestracao/missao-*.md` → ordens | 1 | `maestro-autonomia` |

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
