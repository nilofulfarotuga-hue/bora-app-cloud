---
name: daily-pulse
description: Pulso diário do negócio (Sócio-AI Fase A) — lê as views KPI read-only (v_kpis_diarios, v_funil_checkout, v_drivers_online_agora) + os autologs de email/WhatsApp do Hermes e devolve um resumo PT com 1 leitura + sinais acionáveis. Read-only, sob demanda (sem cron nesta fase). Triggers: "pulso diário", "daily pulse", "como está o negócio", "KPIs de hoje", "resumo do dia".
metadata:
  type: reporting
  category: socio-ai
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Daily Pulse — o pulso do negócio (Sócio-AI Fase A)

Dá ao Robô B os **olhos** que o `SOCIO_AI_PLANO.md` pediu: em vez de "estou cego ao negócio",
respondo "GMV de ontem, funil, estafetas" **sem chutar**. Nesta Fase A corre **sob demanda**
(o cron das 07h é Fase B — documentado, NÃO ativar aqui).

## O que é (e o que NÃO é)
- **É:** leitura agregada read-only + síntese com **1 recomendação**. Zero escrita, zero risco.
- **NÃO é:** dashboard, nem toca pricing/tokens/Stripe. Só lê as 3 views + os 2 autologs.

## Passos (executar por esta ordem)

1. **KPIs + funil + estafetas** — correr as queries de `queries.sql` via MCP Supabase
   (`execute_sql`, projeto `ojykpzwqrtusfeakzrna`). As views já existem (migration
   `socio_ai_faseA_kpi_views`). São `service_role` — o MCP lê; a app **não**.

2. **Comparação** — comparar hoje vs ontem e vs média dos últimos 7 dias. Marcar qualquer
   KPI que mexeu **> 20%** (para cima ou para baixo) como **sinal**.

3. **Autologs do Hermes** (se o VPS estiver alcançável) — contar envios de email/WhatsApp
   das últimas 24h e sinalizar erros:
   ```bash
   ssh -i ~/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud \
     'tail -n 200 /opt/data/email-autolog.jsonl /opt/data/whatsapp-autolog.jsonl 2>/dev/null'
   ```
   Se os ficheiros não existirem ainda (sistema por ativar), dizer "sem autolog ainda".

4. **NORTE** — ler `docs/estrategia/NORTE.md`. Se ainda tiver linhas `<<DANILO PREENCHE>>`,
   **não prometer movimento de KPI** — dizer que falta a régua e pedir para preencher.

5. **Evolution-report** (Fase 5, 2026-07-10 — modo análise, SEM aplicar nada) — correr
   `python .claude/skills/evolution-engine/scripts/evolution_engine.py` e contar as
   propostas novas do relatório `inbox/evolution-report-<data>.md`. Só contagem no resumo;
   as propostas seguem a governança própria (Juiz / Danilo). Falhou → "evolução: sem dados".

6. **Síntese PT** (formato fixo abaixo). Curto. 1 recomendação, não um menu.

## Formato de saída (fixo)
```
📊 PULSO — {data}
• Pedidos: {entregues}/{criados} entregues  (ontem: {ontem})
• GMV: €{gmv} hoje · €{gmv_semana} nos últimos 7 dias
• Conversão checkout: {conv}%  ({seta vs média})
• Estafetas: {online} online · {pendentes} à espera de aprovação
• Comms: {n_email} emails / {n_wa} WhatsApp respondidos (24h){, erros: X}
• Evolução: {n_propostas} propostas de skills no inbox (evolution-report)

🔎 Sinal do dia: {a coisa que mais mexeu, 1 frase}
✅ Recomendação: {1 ação concreta — "eu faria X porque Y"}
```

## Regras
- **Read-only absoluto.** Se alguma query falhar, reportar o erro, não improvisar números.
- **Não fabricar** metas nem tendências sem dados — dados pequenos (lançamento) são normais;
  dizer "amostra pequena" em vez de inventar significância.
- Handoff ao `bibliotecario-cerebro` só se descobrir um facto novo de negócio.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
