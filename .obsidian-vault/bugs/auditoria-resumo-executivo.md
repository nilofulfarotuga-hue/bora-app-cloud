# Auditoria Bora App — Resumo Executivo
> Data: 2026-04-24
> 5 auditorias exaustivas: cliente, estafeta, parceiro, dinheiro, mapa

## Nota metodológica
Este resumo cruza as 5 auditorias existentes em `bugs/`. Os totais por severidade são estimativas derivadas dos IDs indexados (BUG-CL-001..042, BUG-DR-001..~018, BUG-PT-001..~020, BUG-MN-001..018, BUG-MP-001..~015) e podem divergir +/- 2 unidades da contagem literal. Os IDs citados são todos reais.

## Números globais
- **Total de bugs: ~115** (🔴 ~28 críticos · 🟡 ~50 médios · 🟢 ~37 baixos)
- **Total de melhorias sugeridas: ~60** (🔴 ~12 · 🟡 ~30 · 🟢 ~18)
- **Pontuação geral ponderada: 42/100** (vs Uber Eats ~91 · Glovo ~88 · iFood ~92)

## Pontuação por área
| Área      | Bugs 🔴/🟡/🟢 | Melhorias 🔴/🟡/🟢 | /100 |
|-----------|---------------|--------------------|------|
| Cliente   | 5 / 12 / 12   | 3 / 6 / 4          | 45   |
| Estafeta  | 9 / 10 / 6    | 2 / 6 / 3          | 50   |
| Parceiro  | 8 / 10 / 5    | 3 / 8 / 5          | 28   |
| Dinheiro  | 4 / 8 / 6     | 3 / 6 / 3          | 43   |
| Mapa      | 5 / 10 / 8    | 1 / 4 / 3          | 48   |

Parceiro é a área mais fraca (28/100); dinheiro está OK em funcionalidade mas fraco em robustez (idempotência 2/10). Cliente sólido no motor, fraco no fim do funil (auth/push/UX).

---

## 🚨 LAUNCH BLOCKERS (corrigir AGORA)

| ID | Ficheiro | Razão do bloqueio | Esforço |
|----|----------|-------------------|---------|
| **BUG-PT-006** | `partner_dashboard_screen.dart` | Parceiro recebe pedido em silêncio — sem som/vibração/push loop. App inviável em ambiente real. | 0.5 d |
| **BUG-PT-007** | `partner_dashboard_screen.dart` + FCM | Sem push quando app está em background. Pedidos perdidos. | 0.5 d |
| **BUG-CL-016** | `lib/services/notification_service.dart` | Cliente **não** tem `saveTokenForClient` — nunca recebe push "driver chegou" / "pedido entregue". | 0.3 d |
| **BUG-MN-001/002** | `supabase/functions/create-payment-intent/index.ts` | Tolerância ±5% no amount permite até €2 underpayment por pedido de €40 (~€60/dia em 1 000 pedidos). | 0.5 d |
| **BUG-MN-004** | `supabase/functions/refund/index.ts` | Refund sem cap vs `payment_buffer_total`, sem idempotency key. | 0.3 d |
| **BUG-MN-015** | pricing | Bag fee de mercado (€0.10/saco) **não cobrado ao cliente**, só mostrado no driver. Receita perdida em 100% dos pedidos de mercado. | 0.3 d |
| **BUG-MN-003** | trigger tokens SQL | Server não valida cap de 50% em tokens — cliente pode forçar. | 0.3 d |
| **Markup partner 10+5+5%** | `PricingService.applyMarkup` | Regra de negócio documentada **não implementada** — `applyMarkup` devolve basePrice unchanged para partner. Receita perdida em todos os pedidos de parceiro. | 0.5 d |
| **Driver fee partner +€3** | `PricingService.calculateBreakdown` | Regra documentada não existe. Driver ganha igual partner/non-partner. | 0.3 d |
| **Driver +50 tokens partner** | `bora_tokens.sql:143` | Trigger dá sempre 40 tokens, sem distinção partner. | 0.2 d |
| **BUG-DR-003** | `driver_login_screen.dart:25-26` | Credenciais `driver@bora.app / 123456` hard-coded visíveis em produção. Risco segurança + UX. | 0.1 d |
| **BUG-PT-002/003** | partner onboarding | `registerPartner` não é síncrono com Supabase, UUID/foto não obrigatórios, `via.placeholder.com` em runtime. Onboarding real inviável. | 1 d |
| **BUG-PT-001** | `partner_login_screen.dart` | Sem "Esqueceu a palavra-passe?". SLA quebrado no dia 1. | 0.1 d |
| **BUG-PT-005** | partner product mutations | `update/delete/addPartnerProduct` sem `await`/rollback. Venda a preço errado. | 0.5 d |
| **BUG-CL-015** | `consent_store.dart` | Consent GDPR **não enforce** — rejeitar não desactiva FCM/Geolocator/analytics. Risco legal. | 0.5 d |
| **BUG-DR-009** | `driver_order_action_helper.dart` | Entrega sem proof of delivery (foto/PIN). Disputas insolúveis. | 1 d |

**Total Sprint 1 estimado: ~7 dias solo (1 pessoa + IA).**

---

## 🔥 Top 10 globais (gravidade × frequência × impacto receita)

1. **BUG-PT-006/007** — Parceiro sem som/push (bloqueia operação inteira).
2. **BUG-MN-015 + Markup partner 10+5+5%** — receita perdida em 100% dos pedidos de mercado e parceiro.
3. **BUG-MN-001/002** — tolerância ±5% em payment intent = ~€60/dia em buracos a volume médio.
4. **BUG-CL-016** — cliente sem push FCM (conversão e retenção).
5. **Driver fee partner +€3 + Driver +50 tokens partner** — economia de estafeta desalinhada com regras de negócio.
6. **BUG-DR-009** — entrega sem proof of delivery.
7. **BUG-PT-002/003** — onboarding parceiro não funciona em produção.
8. **BUG-CL-015** — consent GDPR sem enforcement.
9. **BUG-MN-004** — refund sem cap nem idempotency.
10. **BUG-MP-004 + BUG-MP-003** — mapa sem modo follow navegacional + animação dupla (UX estafeta comparável a concorrentes).

---

## 💸 Bugs de receita perdida (dinheiro a sair hoje)

- **Markup partner 10+5+5% não implementado** — todos pedidos de parceiro perdem margem.
- **BUG-MN-015** — saco de mercado (€0.10/un) não cobrado ao cliente.
- **BUG-MN-001/002** — tolerância ±5% em create-payment-intent.
- **BUG-MN-008** — trigger tokens usa `NEW.price` (total) em vez de subtotal — taxa 3% mal calculada.
- **Driver +40 em vez de +50 em parceiro** — economia de tokens errada (impacto menor mas contínuo).
- **BUG-MN-004** — refunds podem exceder cobrança (sem cap) — Stripe rejeita mas abre window de bug humano.

---

## 🔐 Bugs de segurança / compliance

- **BUG-CL-015** — GDPR: consent não enforce.
- **BUG-DR-003** — credenciais demo hard-coded no binário produção.
- **BUG-MN-004** — refund EF sem idempotency key (retries = double-refund).
- **BUG-MN-003** — cap de tokens 50% só client-side.
- **BUG-PT-002** — KYC parceiro não síncrono, UUID/foto não obrigatórios.
- **Auth/RLS** — `saveTokenForClient` ausente cria assimetria; auditoria de `payment_events` inexistente (compliance fiscal 3/10).

---

## 📋 Plano de ataque por sprint (1 dev solo + IA)

### Sprint 1 — pré-lançamento (5-7 dias) — SÓ blockers
1. **Dia 1**: BUG-PT-001 (reset pw), BUG-DR-003 (creds), BUG-CL-016 (FCM cliente), BUG-PT-006 (som parceiro — reusar `SoundService`).
2. **Dia 2**: BUG-PT-007 (push parceiro), BUG-PT-005 (await mutations), BUG-MN-003 (cap tokens server).
3. **Dia 3**: BUG-MN-001/002 (fixar `serverAmount = payment_buffer_total`), BUG-MN-004 (cap + idempotency refund), BUG-MN-015 (bag fee mercado no breakdown).
4. **Dia 4**: Markup partner 10+5+5%, Driver fee partner +€3, Driver +50 tokens partner (3 regras SQL/Dart coerentes, mesmo commit).
5. **Dia 5**: BUG-PT-002/003 (onboarding parceiro síncrono + UUID + foto obrigatória).
6. **Dia 6**: BUG-DR-009 (proof of delivery foto ou PIN), BUG-CL-015 (enforce consent).
7. **Dia 7**: buffer + smoke tests + TestFlight.

### Sprint 2 — pós-lançamento imediato (1-2 semanas)
- BUG-MP-003/004 (fix animação dupla, modo follow navegação tilt).
- BUG-MP-005 (centrar em mim — callback truncado).
- BUG-PT-009 (validação close>open).
- BUG-MN-008 (trigger tokens subtotal).
- BUG-CL-013/014 (favorites produto vs restaurante, promo banner dinâmico Supabase).
- BUG-CL-017 (debounce autocomplete).
- Banners dinâmicos (tabela `banners` Supabase).
- Melhorias: MEL-PT-003 (recusa com motivo), MEL-PT-016 (confirmação toggle online).

### Sprint 3+ — competitividade vs Uber/Glovo
- **MEL-MN-001**: migrar para cêntimos int (single source of truth) — 1 sprint.
- Navegação turn-by-turn (mapa 2/10 → 7/10).
- Robustez offline (mapa 1/10 → 7/10).
- Multi-loja parceiro (0/10 → viável).
- Programa fidelidade, social sign-in, skeleton loaders, dark mode, i18n.
- Property tests em pricing; reconcile Stripe no webhook; tabela `payment_events`.

---

## 🎁 Quick wins (<2h cada, alto impacto)

- BUG-PT-001 — botão "Esqueceu palavra-passe" (10 linhas).
- BUG-DR-003 — limpar credenciais hard-coded para `kDebugMode`.
- BUG-CL-036 — detectar caps lock no login.
- BUG-CL-033 — haptic feedback add to cart.
- BUG-CL-032 — skeleton loaders (widget reutilizável).
- BUG-PT-009 — validação `close > open` inline.
- BUG-CL-017 — debounce 300ms em place autocomplete.
- BUG-MN-018 — documentar driver bonus shopping `€0.80` vs `apartmentDriverBonus 1.0`.
- BUG-CL-034 — cache busting na foto de perfil (append `?v=timestamp`).

Somados elevam Cliente de 45 → ~55 e Parceiro de 28 → ~38 em <1 dia de trabalho.

---

## ✅ Pontos fortes confirmados (não mexer)

- **Motor Dart**: stores, realtime, dispatch, modelos — sólido (70/100 pós BUG-012/13/14/16/17 resolvidos).
- **auth_store.dart** — BUG-007 fechado em 2026-04-24; driver nunca usa guest UID, cold start re-autentica via Supabase.
- **Stripe core + MBWay live** (7/10 MBWay) — funcional, só faltam idempotency/reconcile.
- **PricingService** — estrutura boa; bugs são regras ausentes, não arquitectura.
- **SoundService driver** — reutilizável para parceiro sem refactor.
- **Triggers tokens base** — `TOKEN_VALUE_EUR`, `v_driver_tokens=40`, cap 50% ratio — estrutura correcta, só faltam branches.
- **Stacking multi-pedido mapa** (7/10) — comparável a Glovo.

---

## ⚠️ Riscos e dependências

- **Markup partner + driver fee partner + driver tokens partner** devem sair **no mesmo commit** — alterar um sem os outros desalinha economia.
- **BUG-MN-001 fix** deve preceder qualquer teste de pagamento em produção (server-trusted amount).
- **Migração para cêntimos int (MEL-MN-001)** é alto risco (DB migration) — deixar para Sprint 3 com backup e feature flag.
- **FCM cliente (BUG-CL-016)** requer adicionar coluna — coordenar com migration Supabase.
- **Proof of delivery** requer Supabase Storage bucket + RLS — não é só UI.
- **Stripe live keys** devem estar configuradas antes do Sprint 1 dia 3.
- **Firebase / APNs** (iOS push) para parceiro e cliente — certificados válidos.
- **Consent enforce (BUG-CL-015)** pode quebrar analytics existentes — testar com conta rejeitada.

---

## 📈 Projecção de pontuação após Sprint 1

| Área      | Antes | Depois Sprint 1 | Delta |
|-----------|-------|-----------------|-------|
| Cliente   | 45    | 60              | +15 (FCM + consent + caps lock + haptic) |
| Estafeta  | 50    | 62              | +12 (creds + proof of delivery) |
| Parceiro  | 28    | **58**          | +30 (som+push+reset pw+await+onboarding) |
| Dinheiro  | 43    | 68              | +25 (amount server + markup partner + bag fee + idempotency) |
| Mapa      | 48    | 50              | +2 (sem Sprint 1) |
| **TOTAL** | **42**| **~60**         | **+18** |

Após Sprint 1 a app é **operacionalmente viável para lançamento beta limitado**. Gap vs Uber/Glovo (~91) ainda existe (~31 pts) mas endereçável em Sprint 2-3 sem urgência.
