# Sessão 5G — Fase A (AUDIT) — Relatório

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Última commit:** `b7962de feat(5f-beta-alpha): activação pg_net via Vault + Edge Fn auth refactor`
**Modo:** Protecção total · 5 commits granulares com aprovação por commit
**Estado:** ⛔ STOP em A6 — aguardar luz verde Danilo para Fase B

---

## A0 — Regressão check + SHA chatbot

### A0.1 — Skills count (esperado 21)

| mode | count |
|---|---:|
| `escalate` | 3 |
| `read_only` | 11 |
| `write_shadow` | 7 |
| **total** | **21** ✅ |

### A0.2 — RPCs `admin_*suggestion*` / `admin_*skill*` existentes (4)

| RPC | Args |
|---|---|
| `admin_approve_skill_suggestion` | `(p_suggestion_id uuid, p_skill_name text, p_category text, p_mode text='read_only', p_playbook_md text, p_allowed_tools jsonb='[]')` |
| `admin_list_skill_suggestions` | **`(p_status text='pending', p_limit int=20)`** ⚠️ só 2 params — vai ser `DROP+CREATE` em B3 |
| `admin_reject_skill_suggestion` | `(p_suggestion_id uuid, p_reason text)` |
| `admin_rollback_suggestion` | `(p_suggestion_id uuid)` |

### A0.3 — CHECK constraints `skill_suggestions` (todas)

| Constraint | Definição |
|---|---|
| `skill_suggestions_status_check` | `CHECK status IN ('pending','approved','rejected','implemented','rolled_back')` ✅ 5 valores 5E preservados |
| `skill_suggestions_proposal_type_check` | `CHECK proposal_type IN ('new_skill','playbook_update','settings_update')` ✅ **lowercase** |
| `skill_suggestions_zone_type_check` | `CHECK zone_type IN ('safe','critical')` ✅ **lowercase** |
| `skill_suggestions_suggested_mode_check` | `CHECK suggested_mode IN ('read_only','write_shadow','escalate')` |
| `skill_suggestions_target_setting_key_check` | `CHECK target_setting_key NULL OR ~ '^[a-z_]+$'` |
| `skill_suggestions_type_coherence` | new_skill | playbook_update+target_skill_id NOT NULL | settings_update+target_setting_key+target_setting_value NOT NULL |

### A0.4 — Status reais em prod

```
[]
```
✅ **0 propostas em produção.** Sem dados a preservar; sem risco no `ALTER CHECK`.

### A0.5 — `support-chatbot` v8 SHA real

```
ezbr_sha256: e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108
status: ACTIVE
version: 8
```
**Usar este valor no smoke S20** (NÃO hardcode).

### A0.6 — `business_rules.md` numeração

Última secção: **§42 — Sessão 5F-β-α (Vault + Edge Fn auth refactor)**.
Próxima: **§43 — Painel Admin Inbox Avançado (5G)** ✅

---

## A1 — Schema `skill_suggestions`

### A1.1 — 26 colunas (presentes)

`id, suggested_at, status, pattern_summary, sample_messages, message_count, suggested_skill_name, suggested_category, suggested_mode, suggested_playbook_md, suggested_allowed_tools, reviewed_at, reviewed_by, rejection_reason, implemented_skill_id, implemented_at, analysis_window_start, analysis_window_end, gemini_model, pattern_hash, proposal_type, zone_type, target_skill_id, target_setting_key, target_setting_value, previous_value`

⚠️ **`admin_notes` NÃO existe** — criar em B1.

### A1.2 — FTS portuguese: presente ✅

### A1.3 — Indexes existentes (6)

| Index | Comentário |
|---|---|
| `skill_suggestions_pkey` | PK |
| `skill_suggestions_pattern_hash_unique` | UNIQUE pattern_hash |
| `idx_skill_suggestions_status_pending` | partial (status='pending') |
| `idx_skill_suggestions_suggested_at` | order by |
| `idx_skill_suggestions_proposal_type` | type filter |
| `idx_skill_suggestions_zone_pending` | partial (zone IS NOT NULL AND status='pending') |

**Sobreposição com B1 propostos:**
- `idx_skill_suggestions_status_type` (B1) — composite mais amplo que `idx_skill_suggestions_status_pending` (parcial). Mantêm-se ambos sem conflito.
- `idx_skill_suggestions_zone` (B1) — mais amplo que `idx_skill_suggestions_zone_pending` (parcial). Mantêm-se ambos.
- `idx_skill_suggestions_category` (B1) — **novo, não existe**.
- `idx_skill_suggestions_search` (B1, GIN FTS) — **novo, não existe**.

✅ Sem duplicação real. Custo storage marginal (parciais são pequenos).

---

## A2 — `AdminSkillSuggestionsScreen` (1214 linhas)

**Caminho:** `lib/screens/admin/admin_skill_suggestions_screen.dart`

### A2.1 — State actual relevante

| Campo | Linha | Comentário 5G |
|---|---:|---|
| `_statusFilter = 'pending'` | 29 | manter |
| `_typeFilter = 'all'` | 30 | já existe — passa client → server (B5) |
| `_zoneFilter = 'all'` | 31 | já existe — passa client → server (B5) |
| `_pendingBadgeCount` | 33 | já existe na própria screen — reusar para badge no Dashboard (B7) |
| `_channel: RealtimeChannel?` | 38 | realtime já configurado |

### A2.2 — Métodos críticos

| Método | Linha | Comentário 5G |
|---|---:|---|
| `_matchesFilters(s)` | 79 | client-side filter — **substituir por server-side B3** (passar p_type, p_zone, p_category) |
| `_load()` | 85 | `rpc('admin_list_skill_suggestions', {p_status, p_limit:100})` — **estender com 6 params (B5)** |
| `_refreshBadge()` | 111 | actualmente `.length` da lista pendente (limite 200) — **substituir por `admin_skill_suggestions_stats` para `pending` exacto (B5)** |
| `_loadLastAnalysis()` | 121 | manter |
| `_subscribeRealtime()` | 136 | manter (channel `admin_skill_suggestions`, table `skill_suggestions`, all events) |
| `_analyzeNow()` | 149 | manter |
| `_approve(s)` | 204 | switch por proposal_type — manter |
| `_approveNewSkill` / `_approvePlaybookUpdate` / `_approveSettingsUpdate` | 230/338/426 | manter |
| `_reject(s)` | 506 | manter |
| `_rollback(s)` | 550 | manter |
| `_buildBody` / `_buildBanner` / `_buildErrorCard` / `_buildEmpty` / `_buildCard` | 752/768/837/857/872 | **`_buildCard` é o ponto de inserção para checkbox + notas + diff lado-a-lado (B5)** |
| `_buildTypeSpecificContent` | 1008 | onde inserir diff para `playbook_update` |
| `_buildPendingActions` / `_buildRollbackAction` | 1139/1197 | manter |

### A2.3 — Padrão chamada RPC

```dart
final data = await _supabase.rpc(
  'admin_list_skill_suggestions',
  params: {'p_status': _statusFilter, 'p_limit': 100},
);
```
Named params via `params:` Map. Padrão consistente para B5.

### A2.4 — Onde inserir B5

1. **Stats card no topo** → antes de `_buildBanner()` em `_buildBody` (linha 752)
2. **ExpansionTile filtros** → entre stats card e listagem
3. **Pesquisa FTS** → dentro do ExpansionTile
4. **Checkbox bulk** → primeira posição em `_buildCard` (linha 872) com `if (status=='pending')`
5. **AppBar bulk action** → quando `selectedIds.isNotEmpty`
6. **Diff lado-a-lado** → em `_buildTypeSpecificContent` (linha 1008) para `proposal_type=='playbook_update'`
7. **Notas internas** → após `_buildPendingActions` em `_buildCard`
8. **FAB Métricas** → no Scaffold body wrapper

---

## A3 — `AdminDashboardScreen` (802 linhas)

**Caminho:** `lib/screens/admin/admin_dashboard_screen.dart`

### A3.1 — `_NavCard` "Sugestões Skills IA"

**Linhas 524-534:**
```dart
_NavCard(
  icon: Icons.auto_awesome,
  title: 'Sugestões Skills IA',
  subtitle: 'Skills novas propostas pelo cron semanal',
  color: const Color(0xFFFF8F00),
  onTap: () => Navigator.push(...AdminSkillSuggestionsScreen()),
),
```

### A3.2 — Onde inserir badge (B7)

- `_NavCard` é stateless e recebe `icon` por valor → **não dá** Stack directo no `icon`.
- Solução: **wrap o `_NavCard` num `Stack`** no dashboard (não alterar `_NavCard`), com o `Positioned` por cima do CircleAvatar/leading.
- Alternativa mais limpa: **adicionar parâmetro opcional `int? badgeCount` ao `_NavCard`** (mantém encapsulamento). Decidir em B7.

### A3.3 — Padrão `_loadMetrics` actual

```dart
late Future<Map<String, dynamic>> _metricsFuture;
_metricsFuture = _loadMetrics();
```
Adicionar `_loadPendingCount()` separado (não bloqueia metrics future).

### A3.4 — Padrão imports

29 screens admin importadas individualmente. Adicionar `admin_skill_suggestions_metrics_screen.dart` em B6.

---

## A4 — `pubspec.yaml`

| Pacote | Versão actual | Decisão 5G |
|---|---|---|
| `fl_chart` | `^0.69.0` | ✅ presente, **reusar** (≥0.66 satisfeito) |
| `device_info_plus` | **ausente** | não necessário 5G |
| `diff_match_patch` | **ausente** | não adicionar — diff naive linha-a-linha em B5; LCS proper TODO 5G-β |

⚠️ Pubspec **não muda** em 5G.

---

## A5 — Análise impacto + rollback

### A5.1 — Migrations DB (5 totais)

| ID | Nome | Reversível? |
|---|---|---|
| B1 | `20260507_5g_b1_schema_extend` (ADD COLUMN admin_notes + ALTER CHECK status + 4 indexes) | ✅ via DROP COLUMN + revert CHECK + DROP INDEX |
| B2 | `20260507_5g_b2_rpcs_new` (4 RPCs) | ✅ via `DROP FUNCTION` |
| B3 | `20260507_5g_b3_list_extended` (REPLACE list 6 params) | ⚠️ `DROP+CREATE`; precisa restaurar assinatura antiga |
| B4 | `20260507_5g_b4_auto_archive_cron` (cron + função) | ✅ via `cron.unschedule` + `DROP FUNCTION` |

### A5.2 — Flutter (4 ficheiros)

| Ficheiro | Acção |
|---|---|
| `lib/screens/admin/admin_skill_suggestions_screen.dart` | EDIT cirúrgico (estender state + `_load` + `_buildCard`) |
| `lib/screens/admin/admin_skill_suggestions_metrics_screen.dart` | NEW |
| `lib/screens/admin/admin_dashboard_screen.dart` | EDIT (badge + RouteObserver) |
| `lib/main.dart` | EDIT (rota `/admin/suggestions/metrics` + `RouteObserver` em `navigatorObservers`) |

⚠️ `pubspec.yaml` **não muda** (fl_chart já 0.69.0).

### A5.3 — Riscos

| # | Risco | Mitigação |
|---|---|---|
| R1 | `DROP+CREATE admin_list_skill_suggestions` quebra Flutter calls em produção | App actual usa só 2 named params (`p_status`, `p_limit`); novo RPC tem **defaults compatíveis** (`p_type='all'`, etc.) → backward compat. Verificar no smoke S8. |
| R2 | `ALTER CHECK status` falha se rows com status removido | A0.4 confirmou **0 rows**. Risk = 0. |
| R3 | Status `auto_archived` invisível em filtros existentes | Mitigação: dropdown explicitamente lista 7 estados (Todos, Pendentes, Implementadas, Aprovadas, Rejeitadas, Revertidas, Arquivadas) |
| R4 | Cron auto-archive arquiva pendentes legítimos | 30 dias é generoso para uso real (cron 5D só corre semanalmente). |
| R5 | Diff naive sem LCS = falsos positivos visuais | Aceite. TODO 5G-β: `diff_match_patch` package |
| R6 | `_NavCard` wrap com Stack pode quebrar layout | Testar em B7; alternativa cleaner = parâmetro `badgeCount` opcional |
| R7 | RouteObserver não dispara em `pushNamed` se rota base for `home:` | `_RootNavigator` é `home:` directo, **não** rota nomeada → testar `didPopNext` na própria `AdminDashboardScreen`. Solução: registar observer apenas para `PageRoute` (já no spec). |

### A5.4 — Plano rollback

**DB rollback (ordem inversa):**
```sql
-- B4
SELECT cron.unschedule('auto-archive-old-suggestions');
DROP FUNCTION IF EXISTS public._auto_archive_old_suggestions();
-- B3
DROP FUNCTION IF EXISTS public.admin_list_skill_suggestions(text,text,text,text,text,int);
-- recriar versão antiga (text, int)
-- B2
DROP FUNCTION IF EXISTS public.admin_skill_suggestions_stats();
DROP FUNCTION IF EXISTS public.admin_skill_suggestions_metrics();
DROP FUNCTION IF EXISTS public.admin_bulk_reject_skill_suggestions(uuid[], text);
DROP FUNCTION IF EXISTS public.admin_update_skill_suggestion_note(uuid, text);
-- B1
DROP INDEX IF EXISTS idx_skill_suggestions_search;
DROP INDEX IF EXISTS idx_skill_suggestions_category;
DROP INDEX IF EXISTS idx_skill_suggestions_zone;
DROP INDEX IF EXISTS idx_skill_suggestions_status_type;
ALTER TABLE skill_suggestions DROP CONSTRAINT skill_suggestions_status_check;
ALTER TABLE skill_suggestions ADD CONSTRAINT skill_suggestions_status_check
  CHECK (status IN ('pending','approved','rejected','implemented','rolled_back'));
ALTER TABLE skill_suggestions DROP COLUMN IF EXISTS admin_notes;
```

**Flutter rollback:** `git revert <commit>` × 4 commits Flutter.

---

## A6 — Skill identification + Skill recomendada

**Skill match:** nenhuma das 24 skills disponíveis (`ask-knowledge-base`, `auto-rules-sync`, `category-mapper-v2`, `ceo-ai`, `market-data-cleaner`, `market-data-sync`, `taxonomy-mapper`, etc.) cobre painel admin/Flutter.

**Skill mais próxima:** **`ceo-ai`** — já invocada no início para análise estratégica.

**Recomendação execução Fase B:** trabalho directo (Edit + apply_migration + execute_sql), sem skill especializada.

---

## ⛔ STOP — Aguardar luz verde Danilo

**Resumo executivo para aprovar Fase B:**

| Item | Estado |
|---|---|
| Skills count | **21** ✅ (3 escalate + 11 read_only + 7 write_shadow) |
| `support-chatbot` v8 SHA | `e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108` ✅ |
| Status enum actual | `pending,approved,rejected,implemented,rolled_back` ✅ (todos preservados; +`auto_archived` em B1) |
| `proposal_type` case | **lowercase** ✅ |
| `zone_type` case | **lowercase** ✅ |
| Propostas em prod | **0** ✅ |
| `admin_notes` exists | **NÃO** — criar em B1 ✅ |
| `fl_chart` | **0.69.0** ✅ presente |
| `diff_match_patch` | **ausente** — diff naive em B5; LCS em 5G-β |
| `admin_list_skill_suggestions` actual | `(p_status text='pending', p_limit int=20)` — backward-compat OK no DROP+CREATE |
| FTS portuguese | ✅ presente |
| Indexes a criar (B1) | 4 (sem conflito com 6 existentes) |
| `business_rules.md` próxima secção | **§43** ✅ |

**Próxima acção esperada:** Danilo diz "go B1" → aplico migration B1 (schema extend + indexes), reporto, espero "go B2" etc.
