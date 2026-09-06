# Sessão 5F-α — Prompt original (sumário)

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL (aprovação granular)
**Pré-requisito:** 5F completo (commit `14c0462`)

## Objectivo

Notificações urgência admin — classificação `critical|medium|normal`
no momento da escalação Robô A → `robot_crosstalk`. Em 5F-α
**realtime apenas** (admin app aberta). Push real adiado para
5F-β (`pg_net` + FCM + email Resend).

## Tarefas

1. ALTER `robot_crosstalk` ADD COLUMN `urgency`
2. Tool `agent_ask_robot_b` estendida: param `p_urgency`
3. RPC `agent_ask_robot_b` aceita `p_urgency` (manter design 5F)
4. RPC `admin_list_crosstalk` filtro `p_urgency` + ORDER BY
   críticas primeiro
5. Skill `ASK_ROBOT_B` playbook v2: instruções classificação
6. `AdminCrosstalkScreen`: badges 🔴/🟡/🟢, filtro, banner topo
   se há críticas

## Decisão arquitectural

Detecção urgência fica no Gemini (chatbot v8):
- Sem trigger DB
- Classificação contextual (não keyword-only)
- Realtime AdminCrosstalkScreen funciona

## Decisões críticas resolvidas em audit (5F-α A4)

1. **GRANT `agent_ask_robot_b`** — Opção A: manter
   `authenticated + service_role`. Plano original dizia
   "service_role only" mas chatbot v7 usa user JWT.
2. **Banner crítico** — Opção 2: empilhado **acima** do
   banner observador 5F (não substitui).
3. **PROTECÇÃO TOTAL** — aprovação granular B1 → B2 → B3.

## Resultado

Ver `05f_alpha_audit.md` e `05f_alpha_report.md`.

---

*Resumo do prompt original — versão completa em conversa Claude Code.*
