# 05d — Auto-Suggest Cron Skills Novas (Fase A audit)

**Sessão:** 5D/7
**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — STOP após A5
**Estado:** ✅ COMPLETA Fase B (luz verde D1–D6 aprovada)

---

## Objectivo

Sistema automático que analisa conversas chatbot semanalmente e propõe
novas skills para cobrir padrões não cobertos. Loop perpétuo:
clientes perguntam → cron analisa → sugere → Danilo aprova → skill nova.

## Resultados Fase A

Audit detalhado: `.claude/.ai/reports/20260502_megafinal/05d_audit.md`

### Confirmações

- 20 skills active (estado pós 5B)
- pg_cron + pg_net extensions instaladas
- match_knowledge + is_admin existem
- 534 RAG chunks intactos
- support_chatbot_messages/sessions schemas confirmados
- 16 cron jobs preexistentes (sem analyze-conversations-weekly)
- 0 user msgs nos 7 dias (pré-launch)

### ⚠️ Gate principal

`pg_net` settings **NULL** em prod (`app.supabase_url`,
`app.service_role_key`). Cron será registado mas falhará em silêncio
até config. Análise manual via botão funciona (usa JWT, não pg_net).

### Numeração

§36.15 ocupada (5B-β2b). **§37 livre** para 5D.

## Decisões pendentes

| # | Item | Proposta |
|---|---|---|
| D1 | pg_net settings NULL | Aceitar — TODO permanece |
| D2 | Dedup textual SHA256 pattern_hash | Aceitar; semântico adiado p/ 5D-β |
| D3 | Anonimização PII regex | Aceitar; library GDPR adiada |
| D4 | Threshold mínimo | 5 mensagens (admin edita) |
| D5 | Numeração BR | §37.1-37.6 |
| D6 | Editor playbook | TextField multiline 10 rows; markdown avançado adiado |

## Plano Fase B (após luz verde)

- B1: Migration tabela skill_suggestions + 2 cols support_settings
- B2: Migration 3 RPCs (approve/reject/list)
- B3: Edge Fn analyze-conversations v1
- B4: Cron schedule (inactivo até pg_net config)
- B5: Flutter AdminSkillSuggestionsScreen
- Smokes S1-S27 + flutter analyze
- Docs §37.1-6

⛔ Sem luz verde D1 (pg_net) e D2 (dedup) não prossigo.
