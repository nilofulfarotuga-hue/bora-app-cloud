# Sessão 6 — Avaliações por Estrelas — AUDIT (Fase A)

**Branch:** `autonomous-night-2026-04-29`  
**Data:** 2026-05-07  
**Modelo:** Opus 4.7 (1M context)  
**Status:** ⛔ STOP após A6 — aguardar luz verde Danilo

---

## A0 — Regressão check + SHAs reais

| Métrica | Valor | Status |
|---|---|---|
| `support_skills` total active | **21** | ✅ esperado |
| `support_skills` por mode | escalate=3, read_only=11, write_shadow=7 | ✅ |
| `ratings` rows em prod | **0** | ✅ migration UNIQUE segura |
| `support_knowledge_chunks` (RAG) | **534** | ✅ esperado |
| `vault.secrets` count | **3** | ✅ 5F-β-α activos |
| `is_admin()` function | exists | ✅ |
| `support-chatbot` v8 SHA | `e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108` | ✅ ACTIVE |
| `notify-admin-urgent` v2 SHA | `98cce87cafa185ffbcf5e815690e93e81ad02cf741b09a58a8ed764d8ae9decd` | ✅ ACTIVE (5F-β-α-fix1) |
| Edge Fns total ACTIVE | 26 | OK |

---

## A1 — Schema `ratings` detalhado

### Colunas actuais (12)

| Coluna | Tipo | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `created_at` | timestamptz | NO | `now()` |
| `order_id` | **uuid** | YES | — |
| `driver_id` | uuid | YES | — (legacy) |
| `rating` | numeric | YES | — (**legacy dormente**) |
| `comment` | text | YES | — |
| `subject_type` | text | YES | — |
| `subject_id` | **text** | YES | — |
| `stars` | smallint | YES | — |
| `tags` | text[] | YES | `'{}'` |
| `is_private` | boolean | YES | `false` |
| `rater_user_id` | uuid | YES | — |

### Constraints

- `ratings_pkey` (PRIMARY KEY id) — **APENAS**
- ❌ Sem CHECK em `subject_type`
- ❌ Sem CHECK em `stars` (1-5)
- ❌ Sem UNIQUE anti-double-rating
- ❌ Sem FK para orders / auth.users / restaurants

### Indexes (3)

- `ratings_pkey` (id)
- `ratings_order_idx` (order_id)
- `ratings_subject_idx` (subject_type, subject_id)

### RLS Policies (2 — incompletas)

- `ratings_insert_own` (INSERT) — `with: auth.uid() = rater_user_id`
- `ratings_select_visible` (SELECT) — `(is_private IS NOT TRUE) OR (rater_user_id = auth.uid())`
- ❌ Sem policy admin
- ❌ Sem policy partner_owner_read
- ❌ Sem policy service_role

### Triggers

- **NENHUM** — sem auto-update averages

### `submit_rating` RPC já existe

**Signature:** `(p_order_id text, p_subject_type text, p_subject_id text, p_stars smallint, p_comment text, p_tags text[])`

**GRANTS:** PUBLIC, anon, authenticated, service_role, postgres (EXECUTE)

**Comportamento actual:**
- Auth required ✅
- Subject type IN ('driver','partner') ✅
- Stars 1-5 validation ✅
- Order ownership + delivered status ✅
- Idempotent (UPDATE se existing) — sem UNIQUE constraint
- INSERT faz `p_order_id::uuid` (assume IDs são UUIDs válidas)
- ❌ Não suporta `is_private` (sempre false hardcoded)
- ❌ Não suporta subject_type='app'
- ❌ Não actualiza `orders.rated_at` (coluna não existe ainda)

### Uso da coluna `rating` legacy

✅ **NÃO está em uso** por nenhuma function. submit_rating actual usa apenas `stars`. Decisão confirmada: **manter dormente**, não dropar.

---

## A2 — Schemas relacionados — DESCOBERTA CRÍTICA

### ⚠️ Tabela `partners` NÃO EXISTE

O Bora App usa **`restaurants`** como tabela canónica de parceiros (legado). Não existe `partners`.

### `restaurants` schema

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | **text** | `gen_random_uuid()` default mas TEXT |
| `user_` | uuid | **owner field** (nome estranho — não `owner_user_id`) |
| `name` | text | |
| `is_partner` | boolean | filtro partners |
| `fcm_token` | **text** | ✅ **JÁ EXISTE** push directo |
| `email`, `phone`, `address` | text | |
| `approval_status` | text | pending/approved/rejected |
| ❌ `avg_rating` | — | NÃO existe |
| ❌ `ratings_count` | — | NÃO existe |

### `drivers` schema (relevant)

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | uuid | ✅ |
| `user_id` | uuid | |
| `name` | text | (não `full_name`) |
| `fcm_token` | text | ✅ JÁ EXISTE |
| ❌ `avg_rating`, `ratings_count` | — | NÃO existem |

### `orders` schema (relevant)

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | **text** | gen_random_uuid() default |
| `user_id` | uuid | cliente |
| `restaurant_id` | **text** | (não `partner_id`) |
| `driver_id` | uuid | |
| `status` | text | |
| `delivered_at` | timestamptz | ✅ |
| `is_partner_store` | boolean | |
| `vendor_name` | text | |
| ❌ `rated_at` | — | NÃO existe |

### ⚠️ Type mismatches

- `ratings.order_id` (UUID) vs `orders.id` (TEXT) — submit_rating já faz cast `::uuid`. OK enquanto IDs forem UUIDs válidas.
- `ratings.subject_id` (TEXT) genérico — bom: aceita restaurants.id (text), drivers.id (uuid casted), 'app'.
- `ratings.driver_id` (UUID) é coluna legacy — paralela à abordagem subject_type/subject_id moderna.

---

## A3 — Edge Fn pattern FCM (notify-admin-urgent v2)

✅ **FCM v1 OAuth2 confirmado** (não legacy):

- URL: `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`
- Auth: Service account JWT (RS256) → exchange por access_token Google OAuth
- Body: `{ message: { token, notification, data, android, apns } }`
- Cleanup: `errorCode IN ('UNREGISTERED','INVALID_ARGUMENT')` → DELETE token
- `verify_jwt: true` + manual `payload.role === 'service_role'` check
- `Promise.allSettled` paralelismo

### ⚠️ Discrepância vs prompt original

Prompt diz "vault.decrypted_secrets reuse". **REALIDADE**: notify-admin-urgent v2 usa `Deno.env.get('FIREBASE_PROJECT_ID')` e `Deno.env.get('FIREBASE_SERVICE_ACCOUNT')` directo. **Replicar pattern Deno.env**, não vault, em B6.

---

## A4 — Push tokens

| Recurso | Existe? | Decisão |
|---|---|---|
| `partner_push_tokens` table | **NO** | ⚠️ **NÃO criar** |
| `partners.fcm_token` | NO (partners não existe) | n/a |
| `restaurants.fcm_token` | **YES** ✅ | ✅ **Reutilizar — pattern drivers** |
| `admin_push_tokens` | YES | referência apenas |
| `drivers.fcm_token` | YES | referência apenas |

**DECISÃO B5 simplificada:** Skip CREATE TABLE partner_push_tokens. Usar `restaurants.fcm_token` directo (mesmo pattern drivers). Reduz complexidade e elimina B5 RPC partner_register_push_token (já há `update_partner_fcm_token` ou similar — investigar se Flutter usa).

---

## A5 — Análise impacto + plano rollback

### Impacto Decisões Arquitecturais

1. **Tabela alvo é `restaurants`, não `partners`**
   - subject_id 'partner' aponta para `restaurants.id` (text)
   - Adicionar `restaurants.avg_rating` + `restaurants.ratings_count`
   - Owner check: `restaurants.user_ = auth.uid()` (não `owner_user_id`)

2. **submit_rating actual JÁ EXISTE** — usar `CREATE OR REPLACE` para estender:
   - Adicionar parâmetro `p_is_private boolean DEFAULT false`
   - Adicionar suporte `subject_type='app'`
   - Adicionar UPDATE `orders.rated_at` (após B2)
   - Aproveitar UNIQUE INDEX (B1) para EXCEPTION unique_violation → ALREADY_RATED
   - Manter signature actual + adicionar param novo no fim (compat)

3. **Skip partner_push_tokens** — usar `restaurants.fcm_token` directo
   - B5 simplificado: apenas trigger notify_partner_low_rating + RPC `update_restaurant_fcm_token` (se ainda não existir)

4. **rating column legacy** — manter dormente. submit_rating actual NÃO usa, novo idem.

5. **FCM v1 via Deno.env** — replicar pattern actual notify-admin-urgent v2 (NÃO vault.decrypted_secrets como prompt sugere)

6. **subject_type='app'** semântica — sem trigger update average (por design). Útil para feedback geral do app.

### Migrations DB ajustadas

- **B1** ratings: ADD constraints (subject_type CHECK incluindo 'app' + stars CHECK + UNIQUE parcial), 4 indexes novos, 5 RLS policies, 4 colunas (response_text, response_at, flagged_inappropriate, flagged_at, flagged_by)
- **B2** averages: `restaurants.avg_rating`, `restaurants.ratings_count`, `drivers.avg_rating`, `drivers.ratings_count`, `orders.rated_at` + 3 indexes
- **B3** 6 RPCs (incl. `submit_rating` REPLACE com novos params)
- **B4** 2 triggers auto-update averages (`restaurants` + `drivers`; cast `restaurants.id` text directo, `drivers.id` ::uuid)
- **B5** simplificado: apenas trigger `_notify_partner_low_rating_trigger` + (eventualmente) RPC update_fcm_token se Flutter precisar
- **B6** Edge Fn `notify-partner-low-rating` (clone notify-admin-urgent v2 pattern Deno.env)

### Migrations Flutter

- B7 RatingScreen NEW
- B8 RestaurantCard (não PartnerCard) + DriverCard estrelas — confirmar nome real widget
- B9 RestaurantRatingsListScreen + DriverRatingsListScreen
- B10 AdminRatingsScreen
- B11 PartnerPushService — POSSIVELMENTE não necessário se Flutter já actualiza `restaurants.fcm_token` directo. **TODO confirmar com grep no Flutter**.
- B12 rotas + lifecycle hook

### Riscos

| Risco | Mitigação |
|---|---|
| `orders.id` text mas submit_rating cast `::uuid` | manter cast — IDs são UUIDs string-format desde sempre |
| Trigger AVG performance >100k ratings | TODO 6-α running average |
| `restaurants.user_` nome confuso | usar `user_` literal nas RPCs (RLS + partner_respond) |
| Existing 0 ratings | sem migration data backfill needed |
| RLS overlap (own + visible) | rever 5 policies como SET completo no B1 |

### Plano rollback

- **DB**: DROP RPCs novas (`get_*_summary`, `admin_*`, `partner_respond`); DROP triggers `_update_*_avg_rating` + `_notify_partner_low_rating`; ALTER DROP colunas novas (`avg_rating`, `ratings_count`, `rated_at`, `response_*`, `flagged_*`); DROP indexes novos
- **submit_rating**: CREATE OR REPLACE volta à versão actual (preservada nos migrations)
- **Edge Fn**: delete via dashboard / list_edge_functions
- **Flutter**: revert ficheiros via git

---

## A6 — Decisões finais para luz verde

### ✅ Confirmar com Danilo antes de B

1. **Tabela alvo `restaurants` (não `partners`)** — adapt B2/B3/B4/B5 para restaurants
2. **owner field é `user_`** (com underscore) — usar nas RPCs partner_respond + RLS partner_owner_read
3. **Skip partner_push_tokens** — usar `restaurants.fcm_token` directo (igual drivers)
4. **submit_rating CREATE OR REPLACE** — preservar signature + adicionar `p_is_private`, suporte 'app'
5. **NÃO drop `ratings.rating`** legacy (confirmado dormente)
6. **FCM v1 via `Deno.env`** (NÃO vault.decrypted_secrets como prompt sugere)
7. **Naming Flutter:** widget `RestaurantCard` (provável) — confirmar grep antes B8
8. **`subject_type` CHECK incluir 'app'** — para feedback geral

### Skill identification

Tarefa não corresponde a nenhuma skill activa específica. CEO-AI invocada como orchestrator (decisão arquitectural). Não invocar `auto-rules-sync` ainda — só após B12 + business_rules §44 escrita.

---

## Próximo passo

⛔ **STOP — aguardar luz verde Danilo** com confirmação dos 8 pontos acima.

Após luz verde: execução B1→B12 + smokes S1-S36 + 5 commits granulares + push.
