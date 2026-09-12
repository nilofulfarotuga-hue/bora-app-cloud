# 5F-β-α — FASE A Audit (Activação pg_net via Vault)

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Status:** ⛔ STOP após A5 — aguardar luz verde

## TL;DR

- ✅ Vault disponível (v0.3.1) + 1 secret pré-existente (`dispatch_anon_jwt`, sem conflito)
- ✅ 21 skills active (read_only=11, escalate=3, write_shadow=7)
- ❌ `app.supabase_url` NULL + `app.service_role_key` MISSING (confirma 5F-β audit)
- ✅ `service_role_key` localizada em `scripts/rag/.env` (JWT 219 chars)
- ✅ 3 funções a refactorizar (B2 + B3): `_notify_admin_urgent_trigger`, `admin_approve_action`, `fn_notify_admin_pending_action`
- ✅ 1 cron job em escopo (B4): `analyze-conversations-weekly` (jobid 28)
- ⚠️ DESCOBERTA: 7 jobs `update-*` usam formato antigo `app.settings.service_role_key` — fora de escopo 5F-β-α

## Decisões pendentes Danilo

1. Migration B1 contém secret → recomendada **Opção B** (apply_migration sem commit do `.sql`)
2. Confirmar escopo B3 (2 funções 5B-β1)
3. Confirmar escopo B4 (apenas jobid 28; 7 update-* ficam para sessão separada)
4. Avançar FASE B?

## Referência

Relatório detalhado: `.claude/.ai/reports/20260502_megafinal/05f_beta_alpha_audit.md`
