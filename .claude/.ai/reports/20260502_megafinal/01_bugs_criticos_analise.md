# Sessão 1/7 — Bugs Críticos Launch — FASE A (Análise)

**Data:** 2026-05-03
**Branch:** autonomous-night-2026-04-29
**Modo:** Protecção Total (aprovação per-task)
**Baseline `flutter analyze`:** 52 issues, **0 errors** (todas `info`-level, deprecations + style). Qualquer `error` novo num commit = STOP.

---

## Resumo executivo

| # | Bug | Estado | Esforço | Bloqueia launch? |
|---|-----|--------|---------|------------------|
| 1 | Coords NULL no checkout | 🔧 fix urgente | 30-45m | **SIM** (90% pedidos NULL) |
| 2 | Widget Ganhos 0.00€ | 🔧 fix trivial | 5m | UX |
| 3 | Tela Ganhos antiga duplica | 🔧 fix limpeza | 20m | UX |
| 4 | Restaurante não-parceiro rejeitado | 🔧 fix RPC + UI | 45m | **SIM** (receita) |
| 5 | Sync migrations Git | ❓ verificar diff | 15-30m | NÃO (technical debt) |
| 6 | Aprovação admin parceiros | ❌ não existe | 3-4h | **SIM** (segurança) |
| 7 | Foto parceiro obrigatória | 🔧 fix validador | 10m | UX |
| 24 | Admin reset foto produto | ❌ UI inexistente | 30-45m | NÃO |

---

## BUG 1 — Coords NULL no checkout (CRÍTICO RECEITA)

### Validação prévia
```
SELECT COUNT(*) FILTER (WHERE dropoff_lat IS NULL) FROM (últimas 50 orders);
→ dropoff_null=45 / pickup_null=45 / all_null=45 (90% gravidade)
```
Período afectado: `2026-04-25` → `2026-05-02`. **Confirmação 90% últimos pedidos.**

### Root cause confirmado
- Tabela `orders` tem as colunas `pickup_lat`, `pickup_lng`, `dropoff_lat`, `dropoff_lng` ✅
- RPC `create_order` em PROD (e em git em [supabase/migrations/20260430260000_payment_drafts_gating.sql:324-355](supabase/migrations/20260430260000_payment_drafts_gating.sql#L324-L355)) — INSERT statement **não inclui as 4 colunas**. 33 colunas inseridas, nenhuma é coord.
- O input `p_input` chega com as coords (cliente envia), mas RPC ignora silenciosamente.

### Plano fix
Nova migration `20260503xxxxxx_create_order_with_coords_v5.sql`:
- `CREATE OR REPLACE FUNCTION create_order(...)` com 4 colunas adicionais no INSERT.
- Validação: `IF (p_input->>'dropoff_lat') IS NULL OR (p_input->>'dropoff_lng') IS NULL THEN RAISE EXCEPTION 'MISSING_DROPOFF_COORDS'`.
- Pickup: para `service_type IN ('restaurant','storeShopping','carryGroceries')` exigir pickup_lat/lng. Para `sendPackage` permitir NULL (origem é endereço cliente).
- **SEM fallback geocoding** (spec).

### Rollback plan
Se smoke pós-deploy falhar, `CREATE OR REPLACE FUNCTION create_order` com versão anterior (script revert pré-preparado) → pedidos voltam a aceitar NULL temporariamente.

### Smoke MCP
- S1: criar order com coords reais → persiste com coords ✅
- S2: criar order sem coords → `RAISE EXCEPTION` claro ❌
- S3: SELECT count NULL nas próximas 24h → 0

### Riscos
- Cliente Flutter já envia coords? Verificar `OrderStore.createOrder` antes de subir migration. Se app não envia, RPC v5 vai bloquear todos os pedidos.

---

## BUG 2 — Widget Ganhos mostra 0.00€

### Root cause
[lib/widgets/weekly_settlement_card.dart:291](lib/widgets/weekly_settlement_card.dart#L291) lê `o['finalTotal']` (camelCase), mas o RPC `get_driver_current_week_summary` retorna chaves snake_case (RPC `list_driver_orders_in_week` returna `final_total`).

L322 (`Cash recebido: ${_fmtEur(finalTotal)}`) só usa a variável local — fix em L291 resolve ambos.

### Plano fix
`o['finalTotal']` → `o['final_total']` (uma linha).

### Smoke
Estafeta com pedidos entregues abre tela ganhos → valor real (não €0.00).

### Risco
Mínimo. Outras keys em L289, L292, L293, L294 já são snake_case.

---

## BUG 3 — Tela Ganhos antiga duplica card novo

### Layout actual ([lib/screens/driver_earnings_screen.dart:387-455](lib/screens/driver_earnings_screen.dart#L387-L455))
```
ListView:
  L393  WeeklySettlementCard()                   ← MANTER (BUG 2 corrige)
  L395  _BalanceCard(_balance)                   ← APAGAR (duplica saldo)
  L397-415  Row [_StatChip ganhos, _StatChip entregas]  ← APAGAR (duplica)
  L417-422  _TokenSection                        ← MANTER
  L424-429  _PrioritySection                     ← MANTER
  L431-452  Histórico + _TransactionTile         ← APAGAR (duplica histórico do card)
```

### A apagar (classes)
- `_BalanceCard` (L460-492)
- `_StatChip` (L674-723)
- `_TransactionTile` (L724-826)
- Variável `_balance` (L19, L62) — fica órfã.
- Imports/variables de transactions (`_transactions`, `_weeklyEarnings`, `_weeklyDeliveries`) — verificar órfãos no commit.

### A manter
- `_TokenSection` (L493-560), `_PrioritySection` (L561-665), `_PriorityOption` (L666-673).

### Validação
Card novo (`WeeklySettlementCard`) usa `compute_driver_settlement` (RPC) → `_balance` (driver_earnings) NÃO diverge mais (dado removido).

### Smoke
Tela só mostra: `WeeklySettlementCard` + `_TokenSection` + `_PrioritySection`. Sem secção "Histórico" duplicada.

---

## BUG 4 — Restaurante não-parceiro rejeitado em finalize

### Root cause confirmado
- RPC `finalize_storeshopping_purchase` em PROD: linha `IF v_order.service_type <> 'storeShopping' THEN RAISE EXCEPTION 'wrong_service_type'`. Restaurant rejeitado.
- [lib/screens/driver_map_screen.dart:1984-1986](lib/screens/driver_map_screen.dart#L1984-L1986): `_bagFee = _isRestaurant ? RESTAURANT_BAG_FEE : market` — **ignora `is_partner_store`**. Spec diz: parceiro restaurant = 0€, não-parceiro restaurant = €0.30 fixo.

### Plano fix

**a) Migration `20260503xxxxxx_finalize_extends_restaurant.sql`** — extender (NÃO reescrever) `finalize_storeshopping_purchase`:
- Aceitar `service_type IN ('storeShopping','restaurant')` no guard.
- Lógica bag_fee:
  - `restaurant AND is_partner_store` → 0€
  - `restaurant AND NOT is_partner_store` → €0.30 fixo (`v_bag_fee_cents := 30`)
  - `storeShopping` → comportamento ACTUAL (não tocar — Sessão 3 trata)

**b) [lib/screens/driver_map_screen.dart:1984-1986](lib/screens/driver_map_screen.dart#L1984)** — `_ShoppingListSheetContent`:
- `_bagFee` = parceiro? 0 : (_isRestaurant ? 0.30 : market_calc).
- UI: restaurante não-parceiro esconde slider, mostra texto fixo "Sacos: €0.30 (fixo)".
- UI: restaurante parceiro esconde secção sacos toda.

### Smoke MCP
- S1: restaurant não-parceiro → checkout aceita €0.30, RPC finalize aceita ✅
- S2: restaurant parceiro → 0€ checkout, RPC aceita ✅
- S3: storeShopping → comportamento idêntico ao actual (regressão zero) ✅

### Riscos
- ⚠️ `finalize_storeshopping_purchase` é tocado. NÃO REESCREVER, apenas adicionar branches. Cuidado com o markup_pct (15%) que só se aplica a storeShopping non-partner.
- ⚠️ BR `RESTAURANT_BAG_FEE = €0.30` — confirmar em [lib/config/business_rules.dart](lib/config/business_rules.dart) durante fix.

---

## BUG 5 — Sync migrations Git

### Comparação prod vs git

| RPC | Prod (pg_get_functiondef) | Git ([supabase/migrations/20260502080000_driver_weekly_settlements.sql](supabase/migrations/20260502080000_driver_weekly_settlements.sql)) |
|-----|---------------------------|---------------------------------------------------------------------|
| `compute_driver_settlement` | dump de 92 linhas | L136-242 |
| `list_driver_orders_in_week` | dump de 38 linhas | L67-133 |

### Análise prelim
Ambos os dumps prod têm a mesma estrutura visível dos blocos git (mesmas variáveis, mesma assinatura, mesmo retorno). A confirmação fina (whitespace, comentários) só pode ser feita com diff bytewise — vou executar isso como **primeiro passo do fix** (sem alterar código se forem idênticos).

### Plano fix
1. Diff programático: extrair prod normalizado vs git normalizado.
2. Se idênticos → BUG 5 = ✅ (no-op, fechar bug).
3. Se diferentes → criar migration consolidada com versão prod actual (zero mudanças funcionais).

### Risco
Nulo. Se prod = git, é fechar bug. Se diferente, é apenas snapshot.

---

## BUG 6 — Aprovação admin parceiros (CRÍTICO SEGURANÇA — ÉPICO)

### Estrutura tabela `restaurants` actual
Colunas existentes: `id, created_at, user_, name, address, phone, is_partner, category, cuisine_type, photo_url, is_online, email, lat, lng, reservations_enabled, fcm_token, business_hours, is_active_admin`.

⚠️ **Não existe**: `approval_status, approved_at, approved_by, rejection_reason, owner_email`. (Owner email = coluna `email`).

### Parceiros existentes (15 entries)
| ID | Nome | is_partner | is_active_admin | Email |
|----|------|------------|-----------------|-------|
| `partner-1777744354073323` | ovo | true | true | teste5@bora |
| `partner-1776559020556441` | pizzaria paulista | true | false | teste@bora |
| `partner-1776468272433840` | kbvyg | true | false | jggvhhh@bor |
| `partner-1776237403416663` | pizzaria paulista | true | false | nilofulfarotuga@gmail.com |
| `partner-1776189471745209` | iyyth | true | false | nhghjg@^huggg |
| `mercadona-guarda` … `continente-guarda` | (10 não-parceiros legítimos) | false | true | *@nonpartner.bora.app |

⛔ **STOP — DECISÃO DANILO OBRIGATÓRIA antes de backfill:**
Os 5 parceiros (`is_partner=true`) parecem ser tests/lixo (`teste@bora`, `kbvyg`, `iyyth`, emails malformados). Os 10 não-parceiros (`is_partner=false`) são lojas oficiais legítimas que devem ficar visíveis.

**Pergunta:** Backfill recomendado:
- 10 não-parceiros (`is_partner=false`) → `approval_status='approved'` (já visíveis, regressão zero)
- 5 parceiros: marcar **TODOS** `pending` (Danilo aprova manualmente depois)?
- OU marcar 1 (`pizzaria paulista` com email `nilofulfarotuga@gmail.com` = Danilo) `approved` + 4 `pending`?

### Plano fix (após confirmação Danilo)

**a) Migration estrutura:**
```sql
ALTER TABLE restaurants
  ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending','approved','rejected')),
  ADD COLUMN approved_at TIMESTAMPTZ,
  ADD COLUMN approved_by UUID REFERENCES auth.users(id),
  ADD COLUMN rejection_reason TEXT;
```

**b) Backfill** — apenas após confirmação Danilo (decisão acima).

**c) RLS cliente** — alterar policies de SELECT em `restaurants`:
- Cliente: `WHERE approval_status='approved' AND is_active_admin=true`
- Admin: bypass (continua a ver tudo)

**Telas/serviços impactados pela RLS:**
- [lib/stores/restaurant_store.dart](lib/stores/restaurant_store.dart) — fonte principal cliente
- [lib/screens/admin/admin_partners_screen.dart](lib/screens/admin/admin_partners_screen.dart) — admin (bypass via policy)
- [lib/screens/admin/admin_partner_detail_screen.dart](lib/screens/admin/admin_partner_detail_screen.dart) — admin
- [lib/screens/client_favorites_screen.dart](lib/screens/client_favorites_screen.dart) — cliente
- [lib/services/notification_service.dart](lib/services/notification_service.dart) — push

⚠️ Validar **antes** do backfill: nenhuma query cliente continua a funcionar se `approval_status='pending'` — confirmar com lista parceiros legítimos (para evitar perder parceiro real).

**d) Tela admin nova:** `lib/screens/admin/admin_partners_pending_screen.dart`
- Lista pendentes (`approval_status='pending'`)
- Acções: Aprovar / Rejeitar (motivo obrigatório)
- Filtro: ver aprovados/rejeitados também

**e) RPCs:**
```sql
approve_partner(p_restaurant_id TEXT) RETURNS jsonb  -- SECURITY DEFINER + admin check
reject_partner(p_restaurant_id TEXT, p_reason TEXT) RETURNS jsonb
```
Audit log: registar em `admin_audit_log` (já existe).

**f) Email parceiro:**
Verificar [supabase/functions/send-email](supabase/functions/) — se não existir, registar TODO em `.claude/.ai/todos/sessao_1_pending.md` (não bloquear BUG 6).

### Smoke MCP
- S1: novo restaurant inserido manualmente → `pending`, NÃO aparece ao cliente em `restaurant_store.fetchAll()` ✅
- S2: admin chama `approve_partner` → aparece imediatamente ✅
- S3: admin chama `reject_partner('motivo X')` → não aparece, audit log gravado ✅
- S4: backfill executou → 10 não-parceiros legítimos continuam visíveis (regressão zero) ✅

### Riscos
- 🚨 Se RLS aplicar antes do backfill → todas as lojas desaparecem do cliente.
- 🚨 Sub-checkpoint Danilo OBRIGATÓRIO antes de UPDATE backfill.
- 🚨 RLS para admin: confirmar via `auth.jwt() ->> 'role' = 'admin'` ou allowlist email (atual). Hoje o admin é detectado por allowlist email no client (`profile_screen.dart`) — RLS server-side precisa coerência.

---

## BUG 7 — Foto parceiro obrigatória no cadastro

### Root cause
[lib/screens/register_partner_screen.dart:240-247](lib/screens/register_partner_screen.dart#L240-L247):
```dart
labelText: 'URL da foto do restaurante',
helperText: 'Obrigatório — imagem visível aos clientes',
validator: (value) {
  if (value == null || value.trim().isEmpty) {
    return 'Adicione uma foto do restaurante';
  }
  ...
}
```

### Plano fix
- Remover validator (manter campo opcional).
- Mudar `helperText` → `'Opcional — pode adicionar depois no perfil'`.
- Mudar `labelText` → `'URL da foto do restaurante (opcional)'`.
- No save (L81, L128) — se vazio, usar placeholder do branding (`'assets/branding/bora_partner_placeholder.png'` ou URL hardcoded).
- Verificar se asset placeholder existe; senão criar TODO ou usar URL do logo (verde+laranja Bora).

### Smoke
Cadastrar parceiro sem URL foto → completa, placeholder visível na lista cliente.

---

## BUG 24 — Admin não consegue resetar foto produto

### Root cause confirmado
[lib/screens/admin/admin_catalog_screen.dart](lib/screens/admin/admin_catalog_screen.dart) é o único candidato. Tem:
- L40: `admin_partners_with_counts`
- L150: `admin_list_products_by_partner`
- L185: `admin_set_product_availability`
- L217: `admin_update_product_price`

❌ **NÃO existe** UI nem RPC para `photo_url`/`needs_photo`/`image_source`. Funcionalidade está completamente ausente.

### Plano fix
**a) Nova RPC:** `admin_reset_product_photo(p_product_id TEXT)` — SECURITY DEFINER + admin check + audit log.
```sql
UPDATE products
SET photo_url=NULL, image_source=NULL, needs_photo=true, updated_at=now()
WHERE id=p_product_id;
```

**b) UI:** botão "Resetar foto" em `admin_catalog_screen` (linha do produto) ou novo `admin_product_detail_screen`. Prefiro inline na lista (clica → confirm dialog → chama RPC → refresh).

**c) Validação RLS:** confirmar tabela `products` permite UPDATE para `service_role` ou role admin (provavelmente já permite).

### Smoke
- Admin abre catálogo → vê botão "🔄 Resetar foto" em cada produto.
- Clica → confirm → photo_url=NULL, needs_photo=true → UI mostra placeholder.

### Riscos
Mínimo. Funcionalidade nova, não toca em código existente.

---

## TODOs adiados (criar `.claude/.ai/todos/sessao_1_pending.md`)

- BUG 6f — Email parceiro (se infra Resend/email não existir).
- Sessão 1B — Push notifications (escopo removido desta sessão).

---

## Análise de impacto cruzada

| Bug | Toca dispatch engine? | Toca Stripe core? | Toca enforce_financial_immutability? | Toca tokens? |
|-----|-----------------------|-------------------|--------------------------------------|--------------|
| 1 | NÃO | NÃO | NÃO | NÃO |
| 2 | NÃO | NÃO | NÃO | NÃO |
| 3 | NÃO | NÃO | NÃO | NÃO |
| 4 | NÃO | NÃO | ⚠️ usa `set_config app.financial_bypass` (já existe na fn) | NÃO |
| 5 | NÃO | NÃO | NÃO | NÃO |
| 6 | NÃO | NÃO | NÃO | NÃO |
| 7 | NÃO | NÃO | NÃO | NÃO |
| 24 | NÃO | NÃO | NÃO | NÃO |

✅ Nenhum bug toca componentes proibidos.

---

## Ordem de execução recomendada (Fase B)

1. **BUG 1** (90% pedidos com NULL — desbloquear DEPOIS imediatamente — receita)
2. **BUG 2** (5min, ROI altíssimo)
3. **BUG 3** (limpeza visual)
4. **BUG 4** (receita restaurantes não-parceiros bloqueados)
5. **BUG 5** (snapshot, no-op se idêntico)
6. **⛔ CHECKPOINT 1** — pergunta Danilo (a/b)
7. **BUG 6** (com sub-checkpoint backfill)
8. **⛔ CHECKPOINT 2** — pergunta Danilo (a/b)
9. **BUG 7**, **BUG 24**

---

## ⛔ FIM FASE A — AGUARDAR LUZ VERDE DANILO

Próximos passos requerem aprovação:
1. Confirmar plano BUG 1 (migration v5 + risco app não enviar coords).
2. Confirmar abordagem BUG 4 (extender `finalize_storeshopping_purchase` em vez de criar nova RPC).
3. **DECIDIR backfill BUG 6** (ver tabela parceiros acima).

Sem aprovação → não avançar para Fase B.
