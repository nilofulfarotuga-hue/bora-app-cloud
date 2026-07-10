---
tema: estado-vivo · escopo: projeto · estado: atual · atualizado: 2026-07-10
id: estado-vivo
tipo: foto
origem: [missão "Do Prompt ao Loop" F2 2026-07-10 — reescrito pelo daily-pulse]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 📸 Estado Vivo do Bora (gémeo digital lite)

> **ÚNICA página do Cérebro que se REESCREVE** (exceção documentada à regra de append —
> decisão da missão 2026-07-10). Quem precisa da "foto da empresa" lê ESTA página.
> **Foto operacional ao minuto:** o daily-pulse reescreve `/opt/data/estado-vivo.md` na VPS
> toda noite (o Hermes lê essa via `estado`); esta página no repo é a estrutura canónica +
> último snapshot commitado pelo lado do PC.

## Snapshot 2026-07-10 (retoma da missão noturna)
- **Build/track:** CI publica no track fechado (`alpha`) via GitHub Actions; 1.ª build auto = 383. Último: ver Actions.
- **Testadores (12×14d):** operação em curso (`OPERACAO_12_TESTADORES.md`) — progresso só via UI do Play Console (PENDENTE fonte automática).
- **Pedidos/receita (pulso 2026-07-10):** 1 pedido ontem, 1 entregue, GMV €36.44 · TVDE: 1 corrida, 0 completas.
- **⚠️ Saúde:** **44 crashes em 7 dias (5 ontem)** — sinal prioritário do pulso (risco Play Store).
- **Tickets de suporte abertos:** 3 (chatbot em shadow-mode) — fonte automática PENDENTE (query PC/MCP).
- **Erros/cron failures 24h:** watchdog novo (cron 2h) vigia carteiro/campainha/daily-pulse/espelho; pg_cron do Supabase = checagem do lado PC/MCP (VPS sem service key, por design).
- **Custo de IA do dia (lite):** VPS ~0€ (modelos grátis); PC/API por heurística (`loops.md` §Loop Economy).
- **Ordens:** fila livre após `ordem-20260710101114-ef7d` aprovada; 2 travadas de 2026-07-09 à espera do Danilo.
- **Último deploy:** Edge Functions — ver `admin_audit_log`; app — commit `36bceb9` (TVDE tokens + nota motorista).

## Campos fixos (o daily-pulse preenche todos, por esta ordem)
build atual e track · testadores ativos (12×14d) · pedidos/receita da semana · tickets
abertos · erros/cron failures 24h · custo estimado de IA do dia · ordens ativas/travadas ·
último deploy.
