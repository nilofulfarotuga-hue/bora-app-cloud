# ⚠️ PRIORITY CONTEXT (READ FIRST)

## Project: BORA APP

### Core Rules (ALWAYS FOLLOW)
- Follow: Model → Store → Screen
- NEVER use String for status
- ALWAYS use OrderStatus enum:
  created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
- NEVER break existing working features
- ALWAYS maintain Supabase compatibility

### Current Focus
- Fix realtime sync between devices
- Complete driver flow
- Fix auth/session persistence

### Important Notes
- OrderStore uses ID comparison (not reference)
- Realtime replaces objects → never rely on object identity
- DispatchEngine is memory-based with DB sync for offers
## 🧠 Cérebro (memória estruturada) — LER ANTES DE TRABALHAR

- **TODO agente lê `.claude/.ai/knowledge/INDEX.md` antes de trabalhar** e carrega **só** os
  ficheiros do seu tema (nunca o Cérebro inteiro — foi o que rebentou o MEMORY.md de 45 KB).
- **Só o agente `bibliotecario-cerebro` escreve no Cérebro.** Os outros entregam-lhe um *handoff*
  no fim da tarefa (ver `.claude/.ai/knowledge/PROTOCOLO.md`). Escrita de memória é operação de
  primeira classe, com gatilho explícito — não "o modelo decide sozinho o que lembrar".
- **Frescura:** aplicar só factos `estado: atual`; um facto `superado` fica na história, não se aplica.
- **Invariante:** índice e cada ficheiro carregam abaixo de ~24 KB. Passou → o Bibliotecário parte.

## Nota: `context-mode` (ctx_*/`/ctx doctor`/`/ctx stats`) não vale no executor headless

A regra "usa sempre `ctx_*` em vez de Bash/Read para output grande" (injetada pelo hook
`SessionStart` do plugin `context-mode`) só se aplica a **sessões interactivas** (Claude Code
app/CLI com MCP ligado — confirmado ao vivo 2026-08-01, `ctx_doctor`/`ctx_stats` respondem).
**Não vale no loop autónomo** (`run-claude-loop.cmd` → `claude -p --output-format stream-json`):
o modo `-p` não-interactivo não despacha comandos-slash e corre sem `--mcp-config`, logo nenhuma
ferramenta `ctx_*` existe nesse processo — não é regressão nem falta de instalação, é o desenho
do modo `-p`. Um agente/ordem a correr dentro do loop autónomo deve continuar a usar
Bash/Read/Grep directamente; só uma sessão interactiva (Claude.ai, Claude Code app) deve preferir
`ctx_*`. Ver `.claude/.ai/reports/sistema-redondo-FECHO-2026-08-01.md` §6(d) e
`.claude/.ai/reports/sistema-redondo-continuacao-2026-08-01.md` (Bloco C.3).

## Skill Usage Rule

- ALWAYS prefer using skills instead of long prompts
- When a task matches a skill, EXECUTE the skill immediately
- Do not ask for clarification if skill context is sufficient
- Combine skill + short context instead of large explanations

## Sistema de Agentes

- **Path:** `.claude/agents/` (no repo `bora_app/`). Ver `.claude/agents/README.md`.
- **Princípio:** Agentes **orquestram** skills (ferramentas); nunca duplicam a lógica delas.
  Quando existe um agente responsável por um domínio, usa o agente — ele chama as skills certas.
  Skills sem agente dono continuam a ser invocadas diretamente (ver "Skill Usage Rule").
  **O CEO-AI é o dispatcher master.** Todos os agentes leem `agent-memory.md` no arranque.
- **Regra obrigatória:** cada agente tem secção **"Admin Panel Needed?"**. Toda feature nova →
  invocar o agente `admin` no final (gatilho de paridade).
- **TODO agente lê `.claude/.ai/knowledge/INDEX.md` antes de trabalhar** (só o seu tema) e faz
  *handoff* ao `bibliotecario-cerebro` no fim. Proteção: 🟢 zona segura · 🟡 sensível · 🔴 dinheiro
  = **PROPOSE-ONLY** (a Trava bloqueia a edição; o agente lê e propõe, o Danilo aprova).

**Elenco canónico (Fase Marketing+Evolução, 2026-07-10) — 29 agentes** (Fase 5: +`maestro-autonomia`;
Marketing+Evolução 2026-07-10: +`diretor-criativo` +`social-media` +`evolution-engine`). Ver `README.md`.
- **Domínio:** `cliente`🟢 · `estafeta-motorista`🟡 · `parceiro-restaurante`🟡 · `parceiro-servicos`🟢
  · `mercados`🟢 · `favores`🟢 · `pagamentos-wallet`🔴 · `dispatch`🔴 · `admin`🟢 · `notificacoes`🟢 · `chat-suporte`🟢
- **Ofício:** `flutter-ui`🟢 · `backend-supabase`🟡 · `seguranca`🟡 · `dados-sql`🟢 · `devops-ci`🟡
  · `compliance-pt`🟡 · `pesquisa-concorrencia`🟢 · `catalogo-visual`🟢 · `marketing-push`🟢 · `obsidian-sync`🟢
- **Marketing & Evolução (2026-07-10):** `diretor-criativo`🟢 (marca/campanhas; catálogo=produto,
  diretor=marca) · `social-media`🟢 (Postiz; nunca cria contas, nunca publica sem Juiz+Danilo)
  · `evolution-engine`🟡 (meta-agente de evolução de skills; nunca se auto-modifica).
- **Cérebro:** `bibliotecario-cerebro`🟡 (único que escreve na memória).
- **Juiz (Fase 4):** `juiz-revisor`🟡 (gate anti-trapaça) — **absorveu** `checkout-fixer` (fixer de
  regressão de checkout) e `e2e-test-builder` (geração de teste) como braços.

### 🧑‍⚖️ GATE DO JUIZ (obrigatório — Fase 4)
**NENHUM trabalho de agente é ACEITE (commit/merge) até o `juiz-revisor` passar as 3 camadas.**
- **Camada 1** (mecânica): TestSprite via MCP — corre + classifica falha (bug/fragilidade/ambiente).
- **Camada 2**: (1) `flutter analyze` limpo · (2) `flutter test` verde · (3) nenhuma zona protegida
  tocada · (4) nenhuma business_rule violada.
- **Camada 3**: rubrica UI (funcional/visual/layout/UX) para mudanças Flutter.
- **CHÃO determinístico (não-negociável):** `python .claude/juiz/anti_trapaca.py` corre **SEMPRE
  primeiro** — apanha teste apagado/enfraquecido/skip/valor-esperado-trocado/conserto-fantasma via
  git diff. Mecânico — não dá para conversar em volta. exit 2 → REJEITA.
- **Rejeição → aprendizado:** o Juiz gera lição (`.claude/juiz/reflexao.py`) → handoff ao
  `bibliotecario-cerebro` → grava em `procedural/licoes/` → próximo agente lê antes de trabalhar.
- Scripts em `.claude/juiz/` (NÃO em `.claude/hooks/`). Ver `.claude/juiz/README.md`.

### 🎛️ CENTRAL DE AUTONOMIA + O LOOP (Fase 5, 2026-07-01)
O **primeiro loop autónomo seguro**, apontado ao backlog de **paridade admin** (auditoria 360°).
Híbrido: `robot_suggestions` = a fila de itens; `autonomy_goals` + `autonomy_backlog_items` = a
camada de **goals** (o `/goal`, o placar, os tetos). **Superfície ÚNICA de aprovação:**
`AdminRobotSuggestionsScreen` — o placar de paridade + kill switch + dial são o **cabeçalho** dessa
mesma caixa (guardrail: `autonomy_goals` não é um segundo inbox).
- **Maestro (26.º agente):** `.claude/agents/maestro-autonomia.md` 🟡 — dono do ciclo (pega →
  classifica nível → esquadrão pequeno → **Juiz obrigatório** → posta na Central). Evolui `robot-b`.
- **Os 3 níveis (× Trava × Juiz × dial):** **N1 🟢** auto reversível (só se o dial permitir) · **N2 🟡**
  1 toque (fila + push) · **N3 🔴** dinheiro = **só propõe** (a Trava bloqueia aplicar; ato humano).
- **Dial de confiança** (`platform_settings.robot_b_auto_level1_enabled`) — **COMEÇA CAUTELOSO**
  (tudo passa por ti). **Kill switch "PARAR TUDO"** (`robot_b_enabled=false`) — suspende o loop já.
- **Envelope de segurança (5 paredes):** Trava · Juiz · Tetos · Humano-acima-do-L1 · Kill switch.
  Ver `docs/fase5/ENVELOPE_SEGURANCA.md` + `docs/fase5/GOAL_PARIDADE_ADMIN.md`.
- **Push in-system (sem Hermes):** `notify-admin-urgent` modo `generic` quando itens ficam `aguarda_ti`.
- **Aprendizado no loop:** rejeição do Juiz → lição → `bibliotecario-cerebro` → próximo ciclo já sabe.

### Regras de despacho do CEO-AI (esquadrões pequenos — NUNCA o exército todo)
Para cada tipo de tarefa, o CEO-AI convoca um **líder + 2 a 4** agentes. Fan-out (muitos) só em
varreduras grandes (auditoria/migração ampla).

| Tarefa | Esquadrão (líder primeiro) |
|---|---|
| Nova categoria de loja | `mercados` + `flutter-ui` + `catalogo-visual` + `admin` |
| Bug de pagamento | `pagamentos-wallet`[propõe] + `backend-supabase` + `seguranca` |
| Bug/afinação de dispatch | `dispatch`[propõe] + `backend-supabase` + `dados-sql` |
| Ecrã novo do cliente | `cliente` + `flutter-ui` + `admin` |
| Fluxo do estafeta / TVDE | `estafeta-motorista` + `compliance-pt` + `notificacoes` + `admin` |
| Onboarding de parceiro | `parceiro-restaurante` + `backend-supabase` + `admin` |
| Reserva/serviço | `parceiro-servicos` + `flutter-ui` + `admin` |
| Favor/errand + talão | `favores` + `dados-sql` + `admin` |
| Push/campanha | `marketing-push` + `notificacoes` + `admin` |
| Campanha de marca/criativos | `diretor-criativo` + `marketing-push` + `catalogo-visual` + `admin` |
| Publicar redes/métricas sociais | `social-media` + `diretor-criativo` + `admin` |
| Evolução de skills (telemetria) | `evolution-engine`[propõe] → `juiz-revisor` (gate) → Danilo |
| RLS/segurança | `seguranca` + `backend-supabase` |
| Release/CI | `devops-ci` + `juiz-revisor` (gate antes do release) |
| Gerar/reparar teste | `juiz-revisor` → braços `e2e-test-builder` (gerar) / `checkout-fixer` (regressão checkout) |
| Benchmark/paridade de UX | `pesquisa-concorrencia` + o agente de domínio + `admin` |
| Suporte/FAQ | `chat-suporte` + `admin` |
| Auditoria/migração ampla | **fan-out** coordenado pelo CEO-AI + `bibliotecario-cerebro` |
| Loop autónomo (paridade admin) | `maestro-autonomia` → esquadrão por item → `juiz-revisor` (gate) → Central |

**GATE DO JUIZ (obrigatório):** qualquer esquadrão que produza código → o `juiz-revisor` corre o
chão anti-trapaça + 3 camadas **antes** de aceitar (commit/merge). Rejeição → lição → Bibliotecário.

**GATILHO DE PARIDADE (obrigatório):** qualquer feature construída num domínio → convocar também
`admin` para garantir o ecrã de gestão correspondente (PT-BR). **Escalonamento 🔴:** se o esquadrão
tocar dinheiro real, `pagamentos-wallet` entra em modo PROPOSE-ONLY e a alteração final espera "vai".

- **Edge Functions (contagem real):** **53 funções locais** em `supabase/functions/*/index.ts`
  (contadas a 2026-08-01; eram 44 na contagem anterior). Dessas, **24 não declaram `verify_jwt`**
  em nenhum ficheiro da sua pasta — vale a pena auditar quais deviam ser públicas.
  A skill CEO-AI ainda diz "43 deployed / 38 locais" — **stale**; confirmar deployed via MCP
  `list_edge_functions` e atualizar `SKILL.md` com aprovação do Danilo.

## Validation Gate — SÓ DINHEIRO (revisto 2026-07-01)

Regra do Danilo: tarefas normais (bugs, ecrãs, features, infra, admin não-financeiro,
DB/segurança não-financeira, pesquisa) → **DECIDE E EXECUTA ponta-a-ponta**, sem parar,
sem menus de escolha, sem prompts em inglês. No fim, relatório do que foi feito.

A ÚNICA travagem é **dinheiro real** — a 🔴 LISTA VERMELHA (ver `.claude/skills/ceo-ai/SKILL.md` §1.6):
- Stripe / pagamentos / refund / MBWay / webhook + chaves Stripe
- Preços / taxas / comissões (`pricing_service`, fees, markup, service_fee)
- `finalizePurchase` e checkout que cobra
- `bora_tokens` e triggers de tokens
- `platform_settings` financeiros (`stripe_*`, `pricing_*`, `commission_*`, `fee_*`, `token_*`)
- Migrations/UPDATE que alterem valores cobrados a clientes ou pagos a estafetas/parceiros

Para a Lista Vermelha: **faz todo o trabalho de preparação, mas NÃO aplica a alteração final.**
Em vez de parar com pergunta em inglês, escreve no relatório, em português, bem claro:

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Só aplica depois de o Danilo responder "vai". Tudo o resto executa sozinho.

## Execution Mode

- Always execute tasks end-to-end without stopping midway
- Do not ask for confirmation unless absolutely necessary
- When fixing a problem:
  1. Identify cause
  2. Apply fix
  3. Validate result
  4. Repeat until fully resolved

- If the task is not completed:
  - Continue automatically
  - Do not stop at partial solutions

- Always simulate the result mentally before finishing
- Only finish when the system is fully working

**LEI DO PRE-VOO (2026-07-13):** antes de começar (não só antes de terminar), simula mentalmente
se o caminho vai dar certo — timeout, ficheiro/device em falta, permissão. Previsão de falha →
muda a abordagem antes de agir. 2 falhas iguais → muda de abordagem, nunca uma 3ª tentativa igual.
Ver `.claude/.ai/knowledge/permanente/procedural/decision-brain.md` (secção "LEI DO PRE-VOO").
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get          # install dependencies
flutter run              # run on connected device/emulator
flutter analyze          # static analysis (must return 0 errors)
flutter clean            # clear build cache (run before analyze if seeing stale errors)
flutter build apk        # build Android release
```

There are no custom scripts or Makefile. No test suite exists in this project.

---

## Schema source of truth

`supabase/schema.sql` é a **fonte da verdade declarativa do schema actual**
(snapshot CREATE TABLE consolidado). É documento, **não migration aplicável**.
Migrations efectivas estão em `supabase/migrations/` (ordem cronológica).

Notas:
- `restaurants.id`, `products.id`, `orders.id` são **TEXT** em prod (legado).
  Migration plan em `decisions/2026-04-29-restaurants-id-uuid-refactor.md`.
- `migration_trigger_dispatch.sql` (raiz `supabase/`) é boot scaffold legado
  — substituído pelas migrations `dispatch_trigger_pgcron` e
  `dispatch_ttl_auto_reject`. Não re-aplicar.
- `debug_dispatch.sql` é diagnóstico ad-hoc; não é parte do schema.

## Architecture Overview

### Three User Roles

Every feature is scoped to one of three roles: **client**, **driver**, **partner**. The role is persisted in `SessionStore` (SharedPreferences key `bora_app.user_role`) and drives the entire navigation tree.

### Navigation: `_RootNavigator` (widget-rebuild pattern)

All navigation is handled by `_RootNavigator` in `main.dart`. It watches `SessionStore` and `AuthStore` and returns different widgets based on state — it is **not** a Navigator. There are **no** `Navigator.push/pushReplacement` calls to the main screens. Any login or role change simply calls `sessionStore.setRole(...)` or sets auth state, and `_RootNavigator` rebuilds automatically.

Breaking this pattern (e.g., using `pushReplacement` from `RoleScreen`) removes `_RootNavigator` from the widget tree and makes auto-navigation stop working entirely.

### State Management: Provider chain

Providers are declared in `main.dart` in dependency order:

```
SessionStore (value, pre-created — await sessionStore.load() before runApp)
AuthStore    (create:)
CartStore
DriverStore
RestaurantStore
PartnerProductStore  ← ChangeNotifierProxyProvider<RestaurantStore>
OrderStore           ← ChangeNotifierProxyProvider2<DriverStore, RestaurantStore>
DispatchEngine       ← ProxyProvider2<DriverStore, OrderStore>
```

`OrderStore` receives `DriverStore` and `RestaurantStore` via `update:` callbacks. `DispatchEngine` is attached via `engine.attach(orderStore, driverStore)` on every provider rebuild — this call is idempotent.

### Authentication: Dual-layer

`AuthStore` has two layers:
1. **In-memory maps**: `_clientsByEmail`, `_driversByPhone`, `_partnersByEmail` — populated from hardcoded demo accounts, registrations, and SharedPreferences on startup.
2. **Supabase Auth fallback**: `loginClientAsync / loginDriverAsync / loginPartnerAsync` check in-memory first; if not found, call `supabase.auth.signInWithPassword` and verify `user.userMetadata['bora_role']`.

Driver emails in Supabase are synthetic: `{phone}@driver.bora.app`. Partners use their real email.

Non-demo accounts are persisted to SharedPreferences (keys `bora_auth.driver_account` / `bora_auth.partner_account`) so they survive app restarts. `_initFromPrefs()` is called fire-and-forget from the constructor.

**Demo accounts** hardcoded in the constructor (always available offline):
- Client: `cliente@bora.app` / `123456`
- Driver: phone `910000000` / `123456`
- No hardcoded partner demo.

### Realtime: Supabase channels

`OrderStore` subscribes to `orders_channel` on the `orders` table (INSERT / UPDATE / DELETE). The subscription is idempotent — guarded by `if (_channel != null) return`. On error it retries after 5 s via `_resubscribeWithDelay`. A fallback `Timer.periodic(3 s)` calls `refresh()` (only `notifyListeners`, not a DB fetch).

`DriverStore` subscribes to `public:drivers` for realtime driver location updates with smooth animation (12 steps × 80 ms).

### Order lifecycle & `_advanceStatus`

`OrderStatus` enum values and the strict transition flow in `OrderStore._statusFlow`:

```
created → preparing | rejected
preparing → callingDriver
callingDriver → driverAccepted
driverAccepted → pickedUp
pickedUp → onTheWay
onTheWay → delivered
```

Every transition:
1. Writes to DB first (`_updateOrderStatusInDatabase`)
2. Only mutates local state after DB confirms

**Critical**: `_advanceStatus` checks `_orders.any((o) => o.id == order.id)` (ID comparison, not object reference). Realtime UPDATE events replace the object in `_orders` with a fresh `fromSupabase` instance, so reference equality (`contains`) would silently fail.

### Driver batching rules (`DriverCapacityService`)

`lib/dispatch/driver_capacity_service.dart` controls whether a driver can be assigned an order:

- **Logistics orders** (`carryGroceries`, `sendPackage`): cannot be batched — driver must be completely free.
- **Partner orders**: max 2 simultaneous; second order must be from the same vendor OR within 800 m of the existing pickup.
- **Non-partner orders**: max 3 simultaneous; all must be from the same vendor.
- `DispatchEngine` also calls `shouldPrioritize()` to rank drivers who already have an assignment from the same non-partner vendor.

### DispatchEngine

`DispatchEngine` is a pure in-memory engine. It listens to `OrderStore` and `DriverStore` changes and cycles through eligible drivers using a timer-based offer system (`_offerTimeout = 10 s` by default).

When `currentDriverOfferId` is set, it is persisted to Supabase (`persistDriverOffer` on `OrderStore`) so other devices see the active offer and do not restart the dispatch loop.

`driverOfferHistory` is **not** persisted in the DB — it lives only in memory for the current session.

### Pricing

All fee calculation goes through `PricingService.calculateBreakdown(serviceType, subtotal, distanceKm, isPartnerStore, apartmentDelivery)`. It returns `OrderPricingBreakdown` with `deliveryFee`, `serviceFee`, `platformCommission`, `driverEarnings`, `customerTotal`. Never compute fees manually in screens.

### Map integration

The project uses **two** map packages simultaneously:
- `google_maps_flutter` — rendered map widget (driver map, client map)
- `latlong2` — coordinate math and route data

`lib/utils/map_utils.dart` provides `toGMaps()` extension to convert `latlong2.LatLng` → `google_maps_flutter.LatLng`. `google_maps_flutter`'s `LatLng` is hidden at import: `import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;`.

### Data flow for fake/demo data

`lib/data/fake_data.dart` contains hardcoded restaurants, markets, and pharmacies used when Supabase has no data. `lib/data/postal_coordinates.dart` maps 7 Portuguese postal codes to coordinates for order placement without GPS.

### Payment integration

`PaymentService` (`lib/services/payment_service.dart`) handles three payment methods matching the `PaymentMethod` enum (`card`, `mbway`, `cash`):

- **Card**: Stripe (`flutter_stripe`), mobile-only (`kIsWeb` guard). Backend runs as **Supabase Edge Functions** — no `BACKEND_BASE_URL` needed. `PaymentService` calls `Supabase.instance.client.functions.invoke(...)` for:
  - `create-payment-intent` — public (verify_jwt=false), server-validates amount against `orders.payment_buffer_total` (±5% tolerance)
  - `refund` — admin-only (verify_jwt=true + JWT `role=service_role` check)
  - `charge-extra` — authenticated users (verify_jwt=true)
  - All three enforce Stripe's 0.50 EUR minimum.
  - The standalone Node backend at `backend/server.js` (deployed to Render) mirrors the same endpoints as a redundancy/backup — **not** currently called by the app.
  - `notify-partner` — authenticated users (verify_jwt=true, default), fire-and-forget after createOrder; no-ops gracefully if Firebase not configured.
- **MBWay**: real Supabase Edge Function `create-mbway-payment-intent` (verify_jwt=false) — creates Stripe PaymentIntent for `mb_way` + confirms server-side with phone in E.164 format → triggers push notification to MB WAY app. Webhook `stripe-webhook` handles `payment_intent.succeeded` → marks order paid + triggers dispatch. LIVE since 2026-04-24.
- **Cash**: handled locally, no backend required.

Stripe publishable key is initialised in `main()` (non-web only).

### Maps & address autocomplete

`lib/config/maps_config.dart` exports `googleApiKey` (used by `PlaceAutocompleteService` and other map services).

`lib/services/place_autocomplete_service.dart` uses conditional imports to pick the correct platform implementation at compile time:

```dart
import 'place_autocomplete_service_stub.dart'
    if (dart.library.html) 'place_autocomplete_service_web.dart'
    if (dart.library.io)   'place_autocomplete_service_io.dart'
    as impl;
```

Each file exports `createPlaceAutocompleteServiceImpl`. The stub returns empty results (safe default for unsupported platforms).

### Key conventions

- `assigned_driver_id` is intentionally TEXT (not UUID) for historical data compatibility. Triggers that need it as UUID cast explicitly (`assigned_driver_id::UUID`). Do NOT change the column type — the cast workaround is deliberate.
- `OrderModel.fromSupabase` / `toSupabase` — all DB serialisation goes through these. `fromSupabase` maps every column; never assume defaults.
- `OrderServiceType` — 4 types: `restaurant`, `storeShopping`, `carryGroceries`, `sendPackage`. Pricing rules differ per type.
- `BusinessCategory` — enum on `RestaurantModel`: `restaurant`, `supermarket`, `store`, `pharmacy`.
- `VehicleType` — on `DriverModel`: affects which service types a driver can handle (via `supportsService()`).
- Partner orders go through `restaurantAcceptOrder → restaurantMarkReady → callingDriver` flow; non-partner orders skip directly to `preparing → callingDriver` after a simulated delay.

---

## Karpathy Guidelines — Comportamento obrigatório do Claude Code

Behavioral guidelines to reduce common LLM coding mistakes.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

# BORA APP — CONTEXTO NUCLEAR (leia isto ANTES de qualquer tarefa)

> Este ficheiro é o núcleo. O detalhe completo vive em `docs/contexto/` — o índice no fim diz onde está o quê. **Abra o capítulo relevante antes de mexer na área correspondente.** Nunca adivinhe: se a resposta não está aqui nem nos capítulos, investigue no código/DB.

---

## 1. O QUE É O BORA

Plataforma multi-serviço para a **Guarda, Portugal**, construída por **um único fundador (Danilo)** com orquestração de IA. Verticais:

- **Delivery** (restaurantes + mercados/supermercados + lojas + farmácias)
- **TVDE** (ride-hailing tipo Uber/Bolt)
- **Limpeza** (tipo Helpling)
- **Reservas** (mesas com pré-pagamento €3)
- **Favores/Errands** (compras por encomenda, OCR de talão)
- **Serviços** (barbearias, salões de beleza — marcações)

Referências de mercado: **Glovo, Uber Eats, iFood, Uber, Bolt, Helpling**. Regra: nunca inventar padrão novo — copiar o que essas apps consagraram.

## 2. QUEM É DANILO (o dono)

- Brasileiro a viver na Guarda, Portugal. Fundador solo. Motorista TVDE (Uber/Bolt) como renda atual — conhece os dois lados do negócio na pele.
- Comunica em PT-BR informal, quase sempre por voz (voice-to-text — mensagens chegam fragmentadas; interpretar pela intenção).
- Não é programador: **decide e aprova**; a execução é 100% dos agentes de IA. NUNCA pedir tarefa manual técnica a ele (exceção: decisões legais/financeiras e ações que as travas de segurança exigem que sejam humanas).
- Estilo: respostas curtas e diretas; odeia repetição e enrolação.

## 3. STACK E IDENTIFICADORES

| Item | Valor |
|---|---|
| Frontend | Flutter (app cliente + estafeta + parceiro + painel admin web) |
| Backend | Supabase — Postgres, RLS, Edge Functions, pg_cron, Realtime, Storage |
| Pagamentos | **Stripe LIVE** (cuidado: cobranças reais) + MB Way |
| Push | Firebase FCM (`boraapp-d2bea`) |
| Repo | `nilofulfarotuga-hue/bora-app-cloud`, branch `autonomous-night-2026-04-29` |
| Supabase project | `ojykpzwqrtusfeakzrna` |
| Package Android | `pt.boraapp.bora` |
| Path local | `C:\Users\danil\Desktop\projetosflutter\bora_app\` |
| Vault Obsidian | `C:\Users\danil\Desktop\Bora` |
| Web app | bora-app-web.pages.dev (mesmo codebase, Cloudflare Pages) |
| Site institucional | bora-site.pages.dev (repo público `bora-site`) |
| PC do Danilo | Acer Celeron N4500, **4GB RAM** — gargalo permanente; nada pesado local |

## 4. REGRAS INVIOLÁVEIS (quebrar = falha grave)

1. **ZONAS PROTEGIDAS** — não tocar sem ordem explícita: `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`, Stripe webhook v17+, RLS de `orders`/`wallets`/`ledger`, `.claude/settings.json` (Trava protege-dinheiro).
2. **versionCode**: o CI (`build_android.yml`) auto-incrementa. NUNCA incrementar no pubspec.
3. **Push = publicação**: push na branch dispara build Android → Play alpha E deploy web. Commits só-`.md` ou só-`.claude/` não disparam (paths-ignore), MAS o paths-ignore avalia TODOS os commits do push — código pendente "pega boleia". Sempre verificar o que viaja junto antes de push.
4. **Idiomas**: apps (cliente/estafeta/parceiro) = **PT-PT**; painel admin = **PT-BR** (só Danilo usa).
5. **Design**: verde `#16A34A`, laranja `#F97316`, fonte Inter. NUNCA alterar fotos reais de produtos.
6. **Painel admin**: toda feature nova/alterada exige perguntar se precisa de correspondência no painel admin (Danilo quer autoridade total: ver/editar/criar/banir/configurar/exportar/auditar).
7. **Testes de pagamento**: sempre em DINHEIRO (Stripe é live — cartão cobra de verdade).
8. **Web + Android saem juntos**: toda atualização que vai pro Play atualiza também o web app.
9. **Fonte de verdade**: 1º `business_rules.md` (vault Obsidian), 2º código do app, 3º padrão Glovo/Uber Eats/iFood. Dúvida → investigar, nunca chutar.
10. **CEO-AI**: todo prompt de missão invoca o orchestrator em `.claude/skills/ceo-ai/` primeiro.

## 5. REGRAS DE DINHEIRO (resumo — detalhe no cap. 03)

- **PARCEIRO** (só restaurantes): 10% comissão visível + 5% markup oculto + 5% taxa serviço. Estafeta €3,80 + €0,20/km.
- **NÃO-PARCEIRO**: preço base + 15% fixo incluído; fee €2,50 fixo. Estafeta €3,80 + €0,20/km + €0,80 + 30% lucro líquido Bora. **TODOS os mercados são não-parceiros.**
- Entrega €2,50 até 4km, +€0,50/km. Cash máx €40. Sacos: restaurante €0,30, mercado €0,10/saco.
- Tokens: cliente ROUND(preço×3) mín 1; estafeta +40 normal / +50 parceiro.
- Refund p/ wallet: split **80% saldo livre + 20% tokens (60d)**, configurável em `platform_settings`.
- Reservas: pré-pagamento €3 (parceiro €2 / Bora €1; no-show e cancel <2h = Bora 100%).
- TVDE ida-e-volta €8 = preço TOTAL do cliente; motorista da ida ganha €4, da volta €3,50, Bora ~€0,50 — acerto no fecho semanal. Payout é SEMANAL, nunca reembolso instantâneo.
- Buffer MB Way: `payment_buffer_total = fees_total + round(estimativa × 1.2)` — NUNCA ×1.15.

**Confundir parceiro/não-parceiro = erro grave.**

## 6. ÍNDICE DO CONTEXTO COMPLETO (`docs/contexto/`)

| Capítulo | Quando abrir |
|---|---|
| `01-fundador-e-visao.md` | Decisões de produto/estratégia; entender "por quê" |
| `02-arquitetura.md` | Mexer em estrutura, CI/CD, deploy, Edge Functions |
| `03-regras-de-negocio.md` | QUALQUER coisa que toque preço, comissão, wallet, refund |
| `04-verticais.md` | Trabalhar em delivery, TVDE, Limpeza, Reservas, Favores, Serviços |
| `05-parceiros-reais.md` | Lojas reais: Sabores de Casa, Ouro e Prata, BeUnique, mini-sites |
| `06-infra-automacao.md` | Hermes, Córtex, loop autônomo, robôs, motor de conhecimento |
| `07-estado-atual.md` | Saber o que está pronto, pendente e em curso |
| `08-licoes-aprendidas.md` | ANTES de repetir abordagem que já falhou (SSH, GPU, OOM...) |

---
*Mantido por Claude.ai a partir da memória persistente + Córtex Bora. Última consolidação: 2026-07-22.*
