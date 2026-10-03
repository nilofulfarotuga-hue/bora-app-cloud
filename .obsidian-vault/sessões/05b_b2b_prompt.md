# 05b_b2b — Skills info-only mercado + PARTNER_REJECTED (Fase A audit)

**Sessão:** 5B-β2b/7 (ÚLTIMA de 5B antes de 5D)
**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — STOP após A7
**Estado:** ✅ COMPLETA Fase B (luz verde D1–D5 aprovada) · **5B FECHADO**

---

## Objectivo da sessão

4 skills + 1 tool (read_only/escalate; **NÃO** write_shadow):

- `ITEM_UNAVAILABLE` (read_only)
- `ITEM_ADDED` (read_only)
- `PRICE_DIFFERENCE` (read_only)
- `PARTNER_REJECTED_ORDER` (escalate)
- Tool nova `agent_explain_event` para logging em `support_agent_actions`

## Resultados Fase A

Audit detalhado: `.claude/.ai/reports/20260502_megafinal/05b_b2b_audit.md`

### Confirmações

- 16 skills active (1 escalate / 8 read_only / 7 write_shadow)
- support-chatbot **v5** ACTIVE (sha `dc9a63df…7a5b6d04`)
- `support_agent_actions.shadow_status` aceita **`'not_applicable'`** ✅
- HUMAN_REQUEST (5A-1) usa `[HANDOFF_HUMAN]` marker + `allowed_tools=[]` —
  PARTNER_REJECTED_ORDER segue mesmo pattern
- 534 RAG chunks intactos

### Correcção crítica detectada

**Playbook ITEM_UNAVAILABLE** do prompt original assume "Bora NÃO faz
substituições". **Regras reais BR §3.x dizem o OPOSTO**: estafeta troca
por produto de preço parecido se cliente não responder no chat.

Playbook adaptado conforme regras reais.

### Confirmação fórmula ITEM_ADDED

Markup +15% non-partner é aplicado: `i.price * 1.15 * i.quantity`
(`pricing_service.dart` `_nonPartnerMarkupRate = 0.15`).

## Decisões pendentes

| # | Item | Proposta |
|---|---|---|
| D1 | Playbook ITEM_UNAVAILABLE | Adaptar à BR §3.x real (estafeta substitui) |
| D2 | Mecanismo escalate PARTNER_REJECTED | `[HANDOFF_HUMAN]` (sem tool nova) |
| D3 | shadow_status info-only logs | `'not_applicable'` |
| D4 | Numeração BR | §36.13/14/15 |
| D5 | Scope agent_explain_event | 3 skills info-only apenas |

## Plano Fase B (após luz verde)

- B1: 1 migration seed 4 skills (sem DDL)
- B2: support-chatbot v6 (TOOL_WHITELIST += agent_explain_event + handler
  insert em support_agent_actions com shadow_status='not_applicable')
- Smokes + flutter analyze (baseline 55)
- Docs §36.13/14/15

⛔ Sem luz verde D1 (playbook ITEM_UNAVAILABLE) e D2 (mecanismo escalate)
não prossigo Fase B.
