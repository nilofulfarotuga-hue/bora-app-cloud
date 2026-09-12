# Sessão 5E — Fase A · AUDIT (read-only)

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ⛔ STOP — aguarda luz verde Danilo para Fase B
**Pré-requisito:** 5D commit `34d8b34` em prod

---

## A0. Regressão check + numeração

| Métrica | Valor real | Esperado | Status |
|---|---|---|---|
| `support_skills` active | **20** | 20-21 | ✅ |
| `skill_suggestions` rows | **0** | 0 (pre-launch) | ✅ |
| `support_settings.rag_enabled` | **true** | true | ✅ |
| RPC `admin_approve_skill_suggestion` | present | present | ✅ |
| RPC `admin_reject_skill_suggestion` | present | present | ✅ |
| RPC `admin_list_skill_suggestions` | present | present | ✅ |
| Function `is_admin()` | present | present | ✅ |
| Edge Fn `analyze-conversations` | v1 ACTIVE | ACTIVE | ✅ |
| `business_rules.md` última § | **§37** (5D) | §37 | ✅ → próxima §38 |

### `skill_suggestions` estrutura actual (20 cols)

```
id (uuid PK), suggested_at, status (text default 'pending'),
pattern_summary, sample_messages (jsonb), message_count,
suggested_skill_name, suggested_category, suggested_mode,
suggested_playbook_md, suggested_allowed_tools (jsonb),
reviewed_at, reviewed_by, rejection_reason,
implemented_skill_id (FK→support_skills.id ON DELETE SET NULL),
implemented_at, analysis_window_start, analysis_window_end,
gemini_model, pattern_hash
```

### Constraints actuais

```
PRIMARY KEY (id)
CHECK status IN ('pending','approved','rejected','implemented')
CHECK suggested_mode IN ('read_only','write_shadow','escalate')
UNIQUE (pattern_hash, status)  ← name: skill_suggestions_pattern_hash_status_key
FOREIGN KEY implemented_skill_id → support_skills(id) ON DELETE SET NULL
```

**Faltam para 5E:** `proposal_type`, `zone_type`, `target_skill_id`, `target_setting_key`, `target_setting_value`, `previous_value`. Status CHECK precisa `+rolled_back`. UNIQUE precisa incluir `proposal_type`.

---

## A1. SAFE settings whitelist — colunas REAIS

⚠️ **Discrepância detectada vs plano.** Plano diz `welcome_text`, DB tem `chatbot_welcome_text`.

### `support_settings` colunas (17 totais)

| Coluna | Tipo | Default | Classificação 5E |
|---|---|---|---|
| `id` | integer | (PK) | — |
| `whatsapp_number` | text | `'+351937501673'` | **NÃO whitelist** (canal contacto crítico) |
| `support_email` | text | `'boraappbora@gmail.com'` | **NÃO whitelist** (canal contacto crítico) |
| **`chatbot_welcome_text`** | text | `'Olá! Sou a Bora IA…'` | **SAFE** ✅ (corrigir nome no plano) |
| **`sla_hours`** | integer | `24` | **SAFE** ✅ |
| `gemini_model` | text | `'gemini-1.5-flash'` | **CRITICAL** (mudança ↔ comportamento prod) |
| **`rate_limit_per_user_day`** | integer | `30` | **SAFE** ✅ |
| **`max_messages_per_session`** | integer | `30` | **SAFE** ✅ |
| **`max_output_tokens_per_call`** | integer | `8000` | **SAFE** ✅ |
| **`max_user_message_chars`** | integer | `2000` | **SAFE** ✅ |
| **`max_tool_iterations`** | integer | `5` | **SAFE** ✅ |
| `shadow_mode` | boolean | `true` | **CRITICAL** |
| `support_agent_enabled` | boolean | `true` | **CRITICAL** |
| `updated_at` | timestamptz | `now()` | NÃO whitelist (auto) |
| `rag_enabled` | boolean | `false` (override true) | **CRITICAL** |
| `last_skill_analysis_at` | timestamptz | NULL | NÃO whitelist (auto) |
| **`skill_analysis_min_messages`** | integer | `5` | **SAFE** ✅ |

### Whitelist final SAFE (8 keys, todos confirmados existem):

```
chatbot_welcome_text          (text)
sla_hours                     (integer)
max_messages_per_session      (integer)
rate_limit_per_user_day       (integer)
max_output_tokens_per_call    (integer)
max_user_message_chars        (integer)
max_tool_iterations           (integer)
skill_analysis_min_messages   (integer)
```

⚠️ **Acção em B2:** ajustar array `v_safe_keys` (substituir `'welcome_text'` → `'chatbot_welcome_text'`).
⚠️ **Acção em B3:** mesma correcção no Edge Fn prompt Gemini.

---

## A2. Skills CRITICAL list

⚠️ **Discrepância detectada.** Plano hardcode 8 skills; DB tem **7**. `OTP_RESEND` NÃO existe.

| Skill | Mode | Category | Active |
|---|---|---|---|
| ACCOUNT_UPDATE | write_shadow | account_support | ✅ |
| CANCEL_DURING_PURCHASE | write_shadow | order_management | ✅ |
| CANCEL_PRE_PURCHASE | write_shadow | order_management | ✅ |
| PASSWORD_RESET | write_shadow | account_support | ✅ |
| RESERVATION_CANCEL | write_shadow | reservations | ✅ |
| UPDATE_DELIVERY_ADDRESS | write_shadow | order_management | ✅ |
| UPDATE_DELIVERY_INSTRUCTIONS | write_shadow | order_management | ✅ |
| ~~OTP_RESEND~~ | — | — | ❌ NÃO EXISTE (verificado ILIKE %OTP% e %RESEND%) |

⚠️ **Acção em B2:** remover `OTP_RESEND` do `v_critical_skills` array (futureproofing — incluir comentário "será adicionado se skill futura criada").
⚠️ **Acção em B3:** remover `OTP_RESEND` do prompt Gemini.
⚠️ **Acção em §38.3:** lista de 7 skills, NÃO 8.

**Decisão:** Manter `OTP_RESEND` na lista hardcode RPC como segurança defensiva (se for criada no futuro, é classificada CRITICAL automaticamente). Adicionar comentário SQL.

---

## A3. AdminSkillSuggestionsScreen actual (5D · 703 linhas)

**Ficheiro:** [admin_skill_suggestions_screen.dart](lib/screens/admin/admin_skill_suggestions_screen.dart)

### Estrutura

- **State**: `_suggestions`, `_pendingBadgeCount`, `_loading`, `_analyzing`, `_lastAnalysisAt`, `_error`, `_channel`
- **Filtros actuais**: `_filterOptions` Map (pending/approved/rejected/implemented/all)
- **Card render**: `_buildCard(s)` linhas 561-700
- **Approve dialog**: linhas 169-284 (TextField name+category+playbook, Dropdown mode)
- **Reject dialog**: linhas 286-336
- **Realtime**: linhas 110-121 (channel `admin_skill_suggestions` PostgresChangeEvent.all)

### Pontos extensão B4

1. **Card header** (linha 582-602): adicionar segundo badge `proposal_type` antes do `status` badge.
2. **Card body** (linha 604-628): adicionar bloco condicional por `proposal_type`:
   - `new_skill` → manter render actual
   - `playbook_update` → mostrar `target_skill_name` + diff (`previous_value` vs `suggested_playbook_md`)
   - `settings_update` → mostrar `target_setting_key` + valor antes/depois
3. **Approve button** (linha 678-680): condicional por `zone_type`:
   - SAFE → habilitado
   - CRITICAL → disabled + tooltip "Requer SQL manual"
4. **Approve dialog** (linha 169-284): estender por tipo:
   - `new_skill` → manter actual
   - `playbook_update` → mostrar editor playbook + readonly previous
   - `settings_update` → input value validado por `data_type`
5. **Rollback button** (NOVO): cond. `status='implemented' && previous_value!=null && proposal_type IN ('playbook_update','settings_update')` → invoca `admin_rollback_suggestion`
6. **Filtros adicionais**: PopupMenu novos para `proposal_type` e `zone_type`
7. **Status filter**: adicionar `'rolled_back': 'Revertidas'` ao `_filterOptions`

---

## A4. analyze-conversations Edge Fn (5D · v1 ACTIVE · ~254 linhas)

**SHA:** `627d5c8203775e2b2a761fb54b0e9e3a9354bf500b08e65ba0fa45f7de937087`

### Estrutura actual

- Auth: admin via `app_metadata.role='admin'` OR service_role JWT
- PII anonymize regex (email/phone/UUID/4+ digits)
- Rate limit: 1/h via `last_skill_analysis_at`
- Min messages threshold: `skill_analysis_min_messages` (default 5)
- Anti-dedup: skill names + pending summaries
- Gemini config: `maxOutputTokens: 4096`, `temperature: 0.3`
- INSERT loop com hash + ON CONFLICT skip

### Pontos extensão B3

1. **System prompt** (linha ~155): adicionar 2 tipos novos com schemas e exemplos.
2. **maxOutputTokens** (linha ~177): aumentar 4096 → **8192** (playbooks longos).
3. **Loop INSERT** (linhas 230-250): branch por `proposal_type`:
   - `new_skill` → comportamento actual
   - `playbook_update` → lookup `support_skills.id+playbook_md` por `target_skill_name`; se não existir → skip; se existir → INSERT com `target_skill_id` + `previous_value`
   - `settings_update` → validar key in SAFE_WHITELIST; lookup `support_settings.<key>` → `previous_value`; INSERT
4. **Hash strategy**: manter `sha256(summary.toLowerCase())` ✅ (UNIQUE inclui `proposal_type` separa naturally)

### NÃO alterar
- Anonimização PII regex
- Rate limit logic
- Auth check (admin OR service_role)
- Threshold min_messages
- CORS headers
- Defaults

---

## A5. Análise impacto

### Migrations DB (2)

1. **B1** `20260506_5e_b1_skill_suggestions_extend`:
   - +6 colunas nullable com defaults coerentes
   - CHECK `proposal_type` (3 valores)
   - CHECK `zone_type` (2 valores)
   - CHECK coerência type↔target fields
   - DROP/ADD status CHECK (+rolled_back)
   - DROP/ADD UNIQUE (incluir proposal_type)
   - 2 indexes parciais (proposal_type pending, zone+status pending)

2. **B2** `20260506_5e_b2_approve_extended_rpcs`:
   - REPLACE `admin_approve_skill_suggestion` (CASE 3 tipos)
   - CREATE `admin_rollback_suggestion`
   - GRANTS authenticated only

### Edge Fn edit (1)

- `analyze-conversations` v2: prompt 3 tipos + max_tokens 8192 + lookup branches

### Flutter edit (1)

- `admin_skill_suggestions_screen.dart`: extend card render + dialogs + rollback btn + filters

### Riscos identificados

| Risco | Mitigação | Severidade |
|---|---|---|
| Cast dinâmico settings_update text→int/bool | `data_type` lookup `information_schema` + `format(%I::%s)` + EXCEPTION wrapper | Médio |
| SQL injection `target_setting_key` | CHECK regex `^[a-z_]+$` + whitelist ANTES de format | Alto (mitigado) |
| Version decrement frágil em rollback | `GREATEST(version-1, 1)` + TODO histórico real | Baixo (aceito) |
| Edge Fn em prod | Anotar SHA actual; preservar PII/rate-limit/auth; revisão visual antes deploy | Médio |
| UNIQUE migration pode falhar com duplicados | A0 confirma 0 rows ✅ | Baixo |
| Rollback `new_skill` não suportado | RPC RAISE explícito; UI esconde btn nesse caso | Baixo (documentado) |
| Token playbook >8K Gemini | Truncate detection + warning UI; TODO histórico | Baixo |

### Plano rollback emergência

```sql
-- Rollback B2 (RPCs)
DROP FUNCTION public.admin_rollback_suggestion;
-- restore admin_approve_skill_suggestion 5D version (saved git history)

-- Rollback B1 (schema) — APENAS se DB ainda 0 rows novos:
ALTER TABLE skill_suggestions
  DROP COLUMN proposal_type,
  DROP COLUMN zone_type,
  DROP COLUMN target_skill_id,
  DROP COLUMN target_setting_key,
  DROP COLUMN target_setting_value,
  DROP COLUMN previous_value,
  DROP CONSTRAINT skill_suggestions_type_coherence,
  DROP CONSTRAINT skill_suggestions_pattern_hash_unique;
ALTER TABLE skill_suggestions
  ADD CONSTRAINT skill_suggestions_pattern_hash_status_key
  UNIQUE (pattern_hash, status);
ALTER TABLE skill_suggestions
  DROP CONSTRAINT skill_suggestions_status_check;
ALTER TABLE skill_suggestions
  ADD CONSTRAINT skill_suggestions_status_check
  CHECK (status IN ('pending','approved','rejected','implemented'));
```

Edge Fn rollback: redeploy v1 conteúdo (preservado em `files[].content` lido nesta auditoria).

---

## A6. Skill identification durante 5E

Nenhuma skill nova identificada durante Fase A (apenas leitura de schema/código).

---

## ⛔ DECISÕES PARA DANILO ANTES DE FASE B

1. **Whitelist SAFE confirmada (8 keys)** — sigo com `chatbot_welcome_text` em vez de `welcome_text`. ✅ propõe-se aceitar.

2. **CRITICAL skills (7 reais, OTP_RESEND ausente)** — proponho:
   - **Opção A** (recomendada): manter array hardcode com 7 skills + comment SQL "OTP_RESEND reservado se criada no futuro" (defensivo, lista futureproof)
   - **Opção B**: remover OTP_RESEND completamente; quando skill criada, vai como SAFE até alguém actualizar RPC

3. **`whatsapp_number` e `support_email`**: são SAFE (texto livre) ou CRITICAL (canais contacto)? Plano não inclui — proponho **CRITICAL** (mudança ↔ break de comunicação cliente).

4. **Próxima sessão (5F/5G/6/7)** — não decidir agora; STOP após 5E completo.

5. **Aprovação por step granular**: peço luz verde **B1 isolado** primeiro. Depois B2, B3, B4 separadamente.

---

**Aguardo:**

- ✅ "go B1" para migration ALTER skill_suggestions
- ⛔ ou correcções nas 4 decisões acima

Sem luz verde explícita, não procedo.
