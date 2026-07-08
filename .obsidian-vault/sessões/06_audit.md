# Sessão 6 — Avaliações por Estrelas — AUDIT (Fase A)

**Data:** 2026-05-07  
**Branch:** `autonomous-night-2026-04-29`  
**Modelo:** Opus 4.7 (1M context)  
**Status:** ⛔ STOP após A6 — aguardar luz verde Danilo  
**Relatório completo:** `.claude/.ai/reports/20260502_megafinal/06_audit.md`

## Sumário executivo

Audit read-only via MCP Supabase confirmou:
- 21 skills active (3 escalate + 11 read_only + 7 write_shadow) ✅
- 0 ratings em prod (UNIQUE migration segura) ✅
- 534 RAG chunks ✅, 3 vault.secrets activos ✅
- support-chatbot v8 SHA `e351ab62...` ACTIVE ✅
- notify-admin-urgent v2 SHA `98cce87c...` ACTIVE ✅

## Achados críticos (8 decisões para Danilo)

1. ⚠️ Tabela `partners` **NÃO EXISTE** — sistema usa `restaurants` (legado). Adapt B2/B3/B4 para restaurants.
2. ⚠️ Owner field em restaurants é `user_` (com underscore), não `owner_user_id`.
3. ⚠️ `restaurants.fcm_token` **JÁ EXISTE** — skip CREATE TABLE partner_push_tokens. Usar pattern drivers.
4. ⚠️ `submit_rating` RPC **JÁ EXISTE** com signature actual. Usar CREATE OR REPLACE para estender (adicionar `p_is_private`, suporte 'app', UPDATE rated_at).
5. ⚠️ `ratings.rating` (numeric) legacy — **dormente confirmado**, não usado por functions. Manter, não dropar.
6. ⚠️ FCM v1 OAuth2 confirmed; `notify-admin-urgent` v2 usa `Deno.env.get('FIREBASE_*')` directo, **NÃO vault.decrypted_secrets** como prompt sugere. Replicar Deno.env em B6.
7. ⚠️ `subject_type` CHECK deve incluir 'app' (feedback geral, sem trigger average por design).
8. ⚠️ Naming Flutter: provável `RestaurantCard` (confirmar grep antes B8); B11 PartnerPushService possivelmente desnecessário (Flutter pode actualizar `restaurants.fcm_token` directo).

## Schema ratings actual

```
id (uuid PK), created_at, order_id (uuid), driver_id (uuid LEGACY),
rating (numeric LEGACY DORMENTE), comment, subject_type (text),
subject_id (text), stars (smallint), tags (text[]), is_private (bool),
rater_user_id (uuid)
```

- Constraints: APENAS pkey
- Indexes: pkey + order_idx + subject_idx
- RLS policies: insert_own + select_visible (faltam admin/partner_owner/service_role)
- Triggers: NENHUM
- submit_rating actual: existe + idempotent; cast `p_order_id::uuid` para INSERT

## Type compatibilities confirmadas

- `orders.id` TEXT (legacy) ↔ `ratings.order_id` UUID — submit_rating cast OK enquanto IDs são UUID-format strings
- `restaurants.id` TEXT, `drivers.id` UUID, `ratings.subject_id` TEXT genérico (aceita ambos)

## Próximo passo

⛔ Aguardar luz verde Danilo nas 8 decisões. Após aprovação: execução B1→B12 + smokes S1-S36 + 5 commits granulares + push.
