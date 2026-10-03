# Sessão 5A-2/7 — Agente IA Suporte: Frontend + Skills Seed

## Fase A — AUDIT (read-only)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m]
**Modo:** PROTECÇÃO TOTAL — aprovação por fase
**Pré-requisito:** Sessão 5A-1 fechada e em prod (commit 5269dde)

---

## A0 — Regressão 5A-1 backend + Sessões 1-4

| Check | Resultado | Estado |
|-------|-----------|--------|
| A0.1 coords NULL pós 2026-05-03 | 0 | ✅ |
| A0.2 cap 5 sacos source | 1 (presente) | ✅ |
| A0.3 wallet CHECK -2000 | 1 constraint | ✅ |
| A0.4 trg_zz_final_total_dual_write | 1 row | ✅ |
| A0.5 orders.extra_charge_settled_via | 1 col | ✅ |
| A0.6 5A-1 6 RPCs (5 agent + quota) | 6 | ✅ |
| A0.7 5A-1 7 tabelas suporte | 7 | ✅ |
| A0.8 support_settings singleton id=1 | 1 | ✅ |
| A0.9 pgvector ausente | 0 | ✅ (5C) |
| **A0.10 realtime pub support_chatbot_messages** | **0** | ⚠️ **necessária migration B11.5** |

**A0.10 confirma ajuste extra #1:** `support_chatbot_messages` não está em `supabase_realtime` publication. Sem isto, smoke S16 (Realtime device-A→B) falha silenciosamente. Migration adicional pré-B12.

---

## A1 — `support_screen.dart` audit

- **Linhas:** 298
- **6 FAQs hardcoded** (linhas 21, 26, 31, 36, 41, 46):
  1. "Como faço um pedido?"
  2. "Como acompanho a minha entrega?"
  3. "Métodos de pagamento disponíveis"
  4. "Como contactar o estafeta?"
  5. "Política de cancelamento"
  6. "Como usar os meus tokens?"

**Decisão 5A-2:** screen mantida acessível por route legacy (não tocada). Bora IA absorve estas perguntas via skill `GENERAL_FAQ`.

**5B:** deprecar formal — admin FAQs CRUD substitui.

---

## A2 — `BoraScaffold` pattern check

- `lib/widgets/bora_scaffold*` → **NÃO existe**.
- **Decisão (caso 2):** criar `lib/widgets/bora_scaffold.dart` minimal nesta sessão (B11):
  - Wrapper de `Scaffold` com param `showSupportFab: bool = true`
  - Lê `SupportSettingsProvider` (B11)
  - Renderiza `BoraSupportFab` overlay quando `state == loaded && support_agent_enabled == true`
  - **Sem refactor de scaffolds existentes** — só screens que querem FAB usam wrapper.

---

## A3 — Scaffolds enumeração + position FAB

### Mapeamento prompt → classes reais Flutter

| Prompt | Real | Posição | Razão |
|---|---|---|---|
| HomeClientScreen | `ClientHomeScreen` (`client_home_screen.dart`) | **TR** | já tem FAB próprio (`floatingActionButton:` 1) |
| ClientMain | `ClientMainScreen` | **BR** | tem `bottomNavigationBar` mas sem FAB; SafeArea cobre |
| OrdersListScreen | `OrdersScreen` (`orders_screen.dart`) | **BR** | bottomSheet/footer presente, BR ok com padding |
| OrderTrackingScreen | `OrderTrackingScreen` | **BR** | sem obstáculo |
| OrderDetailScreen | `OrderDetailsScreen` | **BR** | sem obstáculo |
| ProfileScreen | `ProfileScreen` | **BR** | bottomSheet/footer; BR ok |
| FavoritesScreen | `ClientFavoritesScreen` | **BR** | sem obstáculo |
| RestaurantsListScreen | `RestaurantsScreen` | **BR** | sem obstáculo |
| MarketsListScreen | `StoresScreen` | **BR** | sem obstáculo |
| RestaurantDetailScreen | `RestaurantMenuScreen` | **BR** | sem obstáculo |
| MarketDetailScreen | `StoreProductsScreen` | **BR** | sem obstáculo |
| ClientReservationsScreen | `ClientReservationsScreen` | **BR** | sem obstáculo |
| WalletScreen | `WalletHistoryScreen` | **BR** | sem obstáculo |
| (TokensScreen — não existe standalone) | (omitido) | — | tokens vivem em ProfileScreen |
| DriverMapScreen | `DriverMapScreen` | **BR** | tem bottomSheet (1); BR com SafeArea+padding 24dp ok |
| DriverEarningsScreen | `DriverEarningsScreen` | **BR** | sem obstáculo |
| DriverHomeScreen | `DriverHomeScreen` | **BR** | substitui "DriverHistoryScreen" inexistente |
| PartnerHomeScreen | `PartnerDashboardScreen` | **BR** | sem obstáculo |
| RestaurantDashboardScreen | `RestaurantDashboardScreen` | **BR** | sem obstáculo |
| PartnerProductsScreen | `PartnerProductsScreen` | **TR** | já tem FAB próprio (add product) |
| PartnerReservationsScreen | `PartnerReservationsScreen` | **BR** | sem obstáculo |
| PartnerEarningsScreen | `PartnerEarningsScreen` | **BR** | sem obstáculo |

**Total MOSTRAR FAB: 21 screens.**

### Lista ESCONDER (não receber FAB)

| Screen | Razão |
|---|---|
| `LoginScreen`, `ClientLoginScreen`, `DriverLoginScreen`, `PartnerLoginScreen` | auth, sem JWT |
| `RegisterClientScreen`, `RegisterPartnerScreen`, `DriverSignupScreen` | auth, sem JWT |
| `RoleScreen`, `PartnerEntryScreen` | gateways pré-login |
| `CartScreen`, `PaymentMethodScreen` | checkout — UX limpa, sem distrações |
| `AddProductScreen`, `CarryGroceriesFormScreen`, `SendPackageFormScreen`, `RatingScreen` | flows transaccionais |
| `DriverPendingScreen`, `DriverRejectedScreen` | onboarding driver |
| Todas em `lib/screens/admin/` | admin tem painel próprio |

### Adicionalmente "mostrar conditional"

- `NotificationsScreen` — mostrar (BR)
- `ReferralScreen` — mostrar (BR)

**Final MOSTRAR: ~23 screens.** Posições documentadas para B15.

---

## A4 — ChatStore namespace audit

✅ **Isolamento total confirmado:**

| Sistema | Tabela DB | Store Flutter | Screen |
|---|---|---|---|
| Operacional cliente↔estafeta | `messages` | `ChatStore` (`lib/stores/chat_store.dart`) | `ChatScreen` (`chat_screen.dart`) |
| Suporte agente IA | `support_chatbot_messages` | (a criar B13) | `SupportChatScreen` (a criar B13) |

`ChatStore.from('messages')` confirmado em 3 locais (`listen`, 2 `insert`). Não há colisão de namespace nem de RLS.

🐛 **BUG 39 já reportado §32.1** (UUID/TEXT mismatch): `messages.order_id` UUID vs `orders.id` TEXT. **Não fixar nesta sessão.**

---

## A5 — 9 playbooks ESQUELETO

Cada playbook detalhado em B17 inclui valores LITERAIS de business_rules.md. Ambíguos ficam `[VERIFICAR: <descrição>]` para Danilo preencher pós-sessão.

### 1. ORDER_STATUS
- **Gatilho:** "Onde está o meu pedido?", "ETA", "estafeta chegou?"
- **Tools:** `agent_get_order_status` (requer order_id)
- **Mode:** read_only · handoff: false
- **Valores literais:** estados `pending|accepted|preparing|driver_assigned|picked_up|delivered|cancelled` (RPC traduz para PT)
- **[VERIFICAR]:** ETA real (RPC devolve NULL — backend 5C com `driver_locations`)

### 2. ORDER_HISTORY
- **Gatilho:** "últimos pedidos", "histórico", "pedido de ontem"
- **Tools:** `agent_get_user_orders_summary(p_limit≤20)`
- **Mode:** read_only · handoff: false
- **Valores literais:** can_be_cancelled = status IN (pending, accepted)

### 3. WALLET_INFO
- **Gatilho:** "saldo wallet", "quanto tenho?"
- **Tools:** `agent_get_user_wallet_summary`
- **Mode:** read_only · handoff: false
- **Valores literais (§28):**
  - Soft cap: **−€10** (gate em `create_order`)
  - Hard floor: **−€20** (CHECK constraint)
  - Wallet free isenta IVA Art. 53.º CIVA
- **[VERIFICAR]:** descrição "wallet promocional 80/20" — NÃO existe em prod (5B+); skill NÃO menciona

### 4. WALLET_BLOCKED_HELP
- **Gatilho:** "wallet bloqueada", "porque não posso comprar?"
- **Tools:** `agent_get_user_wallet_summary`
- **Mode:** read_only · handoff: false
- **Valores literais:** "Liquida no próximo pedido para desbloquear"
- **[VERIFICAR]:** prazo limite legal antes de cobrança (§28.1 fala em "regime simplificado", sem prazo explícito) — tom playbook: "saldo regulariza-se automaticamente na próxima compra; se prefere liquidar manualmente, contacta humano"

### 5. TOKENS_INFO
- **Gatilho:** "tokens", "quantos pontos?", "quando expiram?"
- **Tools:** `agent_get_user_tokens_summary`
- **Mode:** read_only · handoff: false
- **Valores literais (§tokens):**
  - **100 tokens = €0,50**
  - Cliente ganha **3% do valor do pedido** em tokens
  - Estafeta ganha +40 tokens por entrega base, +50 stacking
  - Desconto cliente: até **50% do valor do pedido**
  - Tabela: `bora_tokens` (campo `expires_at` NOT NULL)
- **[VERIFICAR]:** ROUND(price×3) min 1 — fórmula exacta Award (§tokens/award rule); skill mostra apenas saldo+expiring, sem fórmula

### 6. REFUND_STATUS
- **Gatilho:** "onde está meu reembolso?", "estado refund"
- **Tools:** `agent_get_refund_status(order_id)`
- **Mode:** read_only · handoff: false
- **Valores literais:**
  - **Cartão Stripe: 3-5 dias úteis**
  - Wallet: imediato
  - **NUNCA calcular valor de refund** (REGRA CRÍTICA §31.3) — apenas reportar estado
- **[VERIFICAR]:** RPC actualmente devolve placeholder `pending|not_applicable|unknown` (5A-1). Refund detail real em 5B (tabela refunds dedicada ou logs Stripe). Skill marca `[VERIFICAR]: amount placeholder` e oferece humano se cliente exige número.

### 7. GENERAL_FAQ
- **Gatilho:** "como funciona?", "Bora opera onde?", "horário?"
- **Tools:** [] (sem tools)
- **Mode:** read_only · handoff: false
- **Valores literais (§projeto):**
  - **Cidade Guarda, Portugal** (`restaurant_id` sufixo `-guarda`)
  - Expansão pós-lançamento
  - Reserva de mesa integrada (diferenciador vs Glovo/Uber Eats)
- **[VERIFICAR]:** horário operacional (não está em business_rules.md — perguntar Danilo)
- **[VERIFICAR]:** taxa entrega base (skill NÃO calcula; só descreve serviço)

### 8. APP_TROUBLESHOOTING
- **Gatilho:** "GPS não funciona", "não recebo notificações", "app fechou"
- **Tools:** [] (sem tools)
- **Mode:** read_only · handoff: false
- **Conteúdo (boas práticas Uber/Glovo):**
  - GPS: ir a Definições → Localização → permitir Bora "Sempre"
  - Push: Definições → Notificações → Bora → activar
  - Crash: forçar fecho + reabrir; se persistir → handoff humano
- **[VERIFICAR]:** versão mínima Android/iOS suportada — skill diz "se app não actualiza, vai à Play/App Store"

### 9. HUMAN_REQUEST
- **Gatilho:** "falar com humano", "não me ajudaste", queixas, palavras-chave fortes
- **Tools:** [] (sem tools)
- **Mode:** **escalate** · handoff: **true**
- **Acção:** apresenta WhatsApp **+351937501673** + Email **boraappbora@gmail.com**, marca `[HANDOFF_HUMAN]`, Edge Fn cria `support_tickets` channel='chatbot' + `escalated=true` + `ticket_id`.
- **Valores literais (§31.6):** WhatsApp tap NÃO cria ticket (anti-spam); só email/chat criam.

### Lista [VERIFICAR] consolidada para Danilo (relatório B)

| Skill | Item |
|---|---|
| ORDER_STATUS | ETA real (5C com `driver_locations`) |
| WALLET_BLOCKED_HELP | prazo limite legal liquidação manual |
| TOKENS_INFO | fórmula award exacta `ROUND(price×3) min 1` |
| REFUND_STATUS | refund amount placeholder (5B refunds table) |
| GENERAL_FAQ | horário operacional |
| GENERAL_FAQ | taxa entrega base (skill descreve, não calcula) |
| APP_TROUBLESHOOTING | versão mínima Android/iOS |

---

## A6 — Análise impacto + plano rollback

### Ficheiros novos (~7)
1. `lib/providers/support_settings_provider.dart` (B11) — ChangeNotifier 3-state
2. `lib/widgets/bora_scaffold.dart` (B11) — wrapper minimal
3. `lib/widgets/bora_support_fab.dart` (B12) — FabPosition enum
4. `lib/widgets/bora_support_sheet.dart` (B12) — 3 cards condicionais
5. `lib/screens/support_chat_screen.dart` (B13) — Gemini + Realtime
6. `lib/screens/support_email_form_screen.dart` (B14) — submit form
7. `lib/screens/admin/admin_support_tickets_screen.dart` (B16) — admin list

### Ficheiros tocados (~22-24)
- `lib/main.dart` — register `SupportSettingsProvider` em `MultiProvider`
- ~21-23 scaffolds em `lib/screens/` — adicionar `floatingActionButton: BoraSupportFab(...)` ou wrap com `BoraScaffold`

### Migrations novas (2)
- `20260504080000_5a2_realtime_publish_chatbot_messages.sql` (ajuste extra #1)
- `20260504080100_5a2_admin_resolve_ticket.sql` (B16)

### Riscos críticos: **zero**
- Backend 5A-1 NÃO tocado
- FAB lê Provider → kill switch instantâneo
- Skills read-only seed idempotente (`ON CONFLICT DO UPDATE`)
- 23 edits de scaffolds são aditivos (apenas `floatingActionButton:`)

### Plano rollback
1. **Kill switch operacional:**
   ```sql
   UPDATE support_settings SET support_agent_enabled=false WHERE id=1;
   ```
   FAB esconde card "Bora IA"; WhatsApp/Email persistem.
2. **Rollback total skills:**
   ```sql
   UPDATE support_skills SET active=false;
   ```
3. **Rollback admin RPC:** `DROP FUNCTION admin_resolve_ticket;` (idempotente).
4. **Rollback Realtime publication:** `ALTER PUBLICATION supabase_realtime DROP TABLE support_chatbot_messages;` (não destrutivo).

---

## A7 — Skills identificadas

**Nenhuma nova skill emergiu.** Registo formal em `.claude/skills/identified_during_5a2_NONE.md`. As 9 read-only ficam para seed em B17.

---

## A8 — Decisão split α/β

### Estimativa contexto B11-B17

| Bloco | LOC novo | Edits | Token-pesado? |
|---|---|---|---|
| Migration realtime pub | trivial | 0 | não |
| B11 Provider 3-state + BoraScaffold | ~250 | 1 (main.dart) | não |
| B12 BoraSupportFab + Sheet | ~350 | 0 | não |
| B13 SupportChatScreen | ~400 | 0 | médio (Realtime + Edge Fn call) |
| B14 SupportEmailFormScreen | ~150 | 0 | não |
| **B15 FAB em ~23 scaffolds** | 0 | **~23 small edits** | ⚠️ **alto** (muitos Edit calls) |
| B16 Migration + admin list | ~250 | 0 | não |
| B17 Seed 9 skills | INSERT massivo (~25K chars total playbooks) | 0 | médio |
| Smokes 19 UI + 10 regressão | — | — | médio |

### Decisão: **5A-2 inteiro como default**

- Risco contexto: **moderado** (não alto). B15 é o gargalo mas são edits pequenos.
- **Sinalização preventiva:** se durante B14→B15 detectar contexto >85%, paro automaticamente em ponto de cisão limpo (após B14 commit) e proponho sub-sessão "5A-2-β" para B15+B16+B17 + smokes.
- **Não fazer split preventivo** — adiciona overhead de fechamento/reabertura.

---

## A9 — Status final Fase A

✅ **Todos os 9 checks (A0-A8) executados. Sem bloqueios.**

⚠️ **Confirmações importantes:**
- A0.10 → migration realtime publication necessária pré-B12 ✅ planeada
- A2 → criar `BoraScaffold` minimal (caso 2) ✅
- A3 → 23 screens MOSTRAR + posições documentadas ✅
- A5 → 7 itens [VERIFICAR] para Danilo preencher pós-sessão ✅
- A8 → 5A-2 inteiro como default; sinalização preventiva durante B14→B15 ✅

📦 **Sync Obsidian:** copiar para `C:\Users\danil\Desktop\Bora\entregas\05a2_agente_frontend_audit.md`.

⛔ **STOP — Aguardar luz verde Danilo para Fase B (B11–B17 + 29 smokes + relatório + sync).**
