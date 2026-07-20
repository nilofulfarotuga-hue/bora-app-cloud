---
id: plano-tvde-pagamentos-pente-fino-2026-07-20
tema: tvde
estado: atual
tipo: plano
data: 2026-07-20
autor: CEO-AI (sessão interativa, MODO PROTECÇÃO TOTAL)
---

# PLANO — TVDE cliente: pagamento a sério (Dinheiro · Cartão · MB Way)

**Aguarda aprovação do Danilo ("vai") antes de qualquer alteração.**
Diagnóstico feito por leitura de código + `SELECT` ao vivo na DB `ojykpzwqrtusfeakzrna`.
Nada foi alterado.

---

## 0. Estado REAL (provado, não assumido)

### Ao vivo na DB (via MCP, 2026-07-20)
| Facto | Prova |
|---|---|
| `tvde_card_payments_enabled` = **true** | `SELECT key,value FROM platform_settings` |
| `tvde_roundtrip_price_cents` = **800** | idem |
| Planos: `tvde_plan_weekly_cents`=4000 · `_biweekly_`=7000 · `_monthly_`=13200 | idem |
| `token_value_cents_x100` = 50 · `token_payment_max_pct` = 50 | idem |
| **2 overloads** de `tvde_request_ride` (uma `…,text`=p_payment_method, outra `…,integer`=p_tokens_to_apply) | `pg_proc` |
| `tvde_ride_charge_cents(uuid)` ✅ · `tvde_create_roundtrip_credit(uuid,uuid,int,text)` ✅ | `pg_proc` |
| Tabelas `tvde_driver_balances` ✅ · `tvde_roundtrip_credits` ✅ | `information_schema` |
| RPCs admin: `admin_tvde_rides_list`, `_subscriptions_list`, `_plan_requests_list`, `_cancellations`, `_drivers_list`, `_ride_stops`, `_access_requests_list`, **`admin_tvde_roundtrips`** | `pg_proc` |

### O que JÁ está feito (não refazer)
- EF `tvde-payment`: `charge` (card→clientSecret · mbway→server-confirm E.164) + `refund`.
- EF `tvde-plan-payment`: `create` · `create_mbway` · `activate` · `create_roundtrip` ·
  `create_roundtrip_mbway` · `activate_roundtrip`.
- `TvdeStore` tem **todos** os métodos, incluindo `requestRidePaid(mbwayPhone:)`,
  `createRoundtripPaymentMbway()` e `createPlanPaymentMbway()`.
- **(C) PLANO — completo**: `tvde_plans_screen.dart` usa `ReservationPaymentMethodSheet`
  (recolhe telefone, valida 9 dígitos) + `PlanMbwayWaitingDialog` (poll 3 s / timeout 120 s).
  → É o padrão-ouro **já dentro do TVDE**. É isto que se copia para (A) e (B).

---

## 1. Bugs encontrados

### 🔴 BUG 1 — CORRIDA · MB Way: o telefone NUNCA é recolhido nem enviado (causa-raiz)
Exatamente a hipótese do Danilo, confirmada:
- `_TvdePaymentSheet` devolve `_TvdePayResult(method, note, tokensUsed)` —
  **sem telefone** (`tvde_request_ride_screen.dart:851-856`).
- `_solicitar()` chama `store.requestRidePaid(...)` **sem `mbwayPhone:`** (`:327-339`).
- `TvdePaymentSelector` (`lib/widgets/tvde/tvde_payment_selector.dart`) são só chips —
  não tem campo de número.
- EF `tvde-payment:159-162`: `phone = String(body.phone ?? '')` → `''` → `e164 = '+351'`
  → Stripe rejeita → *"não foi possível"*.

### 🔴 BUG 2 — CORRIDA · MB Way: não há poll nem ecrã de espera
Após `charge` mbway o PaymentIntent fica `requires_action`/`processing`; `_solicitar()`
vai **direto** para `_openTracking()`. Ninguém confirma depois: a EF `tvde-payment`
**não tem** ação de verificação (só `charge` e `refund`) e o comentário do ficheiro diz
explicitamente que **não usa o `stripe-webhook`**. → `payment_status` fica preso em
`processing` para sempre. Contraste: o plano tem `activate` + `PlanMbwayWaitingDialog`.

### 🔴 BUG 3 — €8 ida-e-volta: só cartão; MB Way é código morto
`_solicitarRoundtrip()` (`:379-424`) chama **só** `createRoundtripPayment()` (cartão) e
aborta com *"Não foi possível iniciar o pagamento da volta"* se não vier `clientSecret`.
Nunca pergunta o método. `TvdeStore.createRoundtripPaymentMbway()` **não é chamado por
ninguém** — existe e está morto.

### 🔴 BUG 4 (a confirmar) — €8: a corrida de IDA é criada como `cash`
`_solicitarRoundtrip():403` chama `store.requestRide(...)` **sem `paymentMethod`** →
default `'cash'`. Se os €8 cobrem ida **+** volta, o motorista cobra a ida outra vez em
dinheiro = **cobrança dupla ao cliente**. Se os €8 só compram o vale da volta, está certo.
**Confirmar em `tvde_finish_ride` (isenção por `roundtrip_credit_id`) ANTES de tocar.**

### 🔴 BUG 5 — 2 overloads de `tvde_request_ride` → toggle de tokens é decorativo
Confirmado ao vivo. PostgREST resolve sempre a overload `p_payment_method` (é a que a UI
e a EF nomeiam) → `p_tokens_to_apply` nunca chega. Já há migration de fusão **proposta e
não aplicada** (`supabase/migrations/20260717000000_PROPOSTA_tvde_request_ride_merge_tokens_payment.sql`),
já com a fórmula 10× corrigida. **Continua a aguardar "vai".**

### 🟡 LACUNAS ADMIN
| Item | Estado |
|---|---|
| Corridas / assinaturas / pedidos de plano / cancelamentos / no-shows / motoristas / docs | ✅ ecrã existe |
| **Ida-e-volta** | ⚠️ RPC `admin_tvde_roundtrips` **existe na DB**, **nenhum ecrã Flutter a chama** |
| **Dívidas de dinheiro dos motoristas** (`tvde_driver_balances`) | ❌ sem RPC admin e **sem ecrã** |

---

## 2. Plano de execução

### FASE 0 — Verificação (read-only, 🟢)
1. `get_edge_function` das duas EFs → confirmar que a versão **deployed** já tem
   `create_roundtrip_mbway` e `activate_roundtrip` (o repo tem; a prod é que manda).
2. Ler `tvde_finish_ride` → decidir o BUG 4 com prova, não com palpite.

### FASE 1 — 🟢 ZONA VERDE (executo assim que houver "vai")
Só Flutter. Não toca EF, não toca RPC, não toca preços.
1. **Corrida · MB Way** — trocar o `TvdePaymentSelector` por um selector que, ao escolher
   MB Way, mostra o campo de telefone (mesma validação de 9 dígitos + pré-preenchimento do
   perfil do `ReservationPaymentMethodSheet`); `_TvdePayResult` ganha `mbwayPhone`;
   `_solicitar()` passa-o a `requestRidePaid(mbwayPhone:)`. → **fecha o BUG 1**.
2. **Corrida · MB Way** — `TvdeRideMbwayWaitingDialog`, clone do `PlanMbwayWaitingDialog`.
   *Depende da FASE 2 para ter o que fazer poll.* → BUG 2.
3. **€8 · MB Way** — `_solicitarRoundtrip()` abre o `ReservationPaymentMethodSheet`
   (€8); cartão = fluxo atual; MB Way = `createRoundtripPaymentMbway(phone)` +
   `PlanMbwayWaitingDialog` adaptado → `activateRoundtrip`. → **fecha o BUG 3**.
4. **Admin · ida-e-volta** — `AdminTvdeRoundtripsScreen` (PT-BR) ligando a RPC
   `admin_tvde_roundtrips` que já existe + entrada no dashboard.
5. `flutter analyze` limpo (baseline 217 issues, 0 erros) + widget tests dos 3 métodos.

### FASE 2 — 🔴 LISTA VERMELHA (preparo tudo, **NÃO aplico**)
Cada item fica pronto (código + SQL + diff), à espera de "vai" item a item:
1. **Ação `confirm_ride_payment` na EF `tvde-payment`** — retrieve do PI + `UPDATE
   tvde_rides.payment_status`. **É o único caminho para o MB Way da corrida fechar de
   verdade** (sem isto, o ponto 2 da FASE 1 não tem o que consultar). Deploy de EF que
   cobra = Lista Vermelha.
2. **BUG 4** — se a prova mostrar cobrança dupla, mudar o método da ida do pacote €8.
3. **BUG 5** — aplicar a migration de fusão das overloads (já escrita) + commitar as
   5 linhas client-side que estão uncommitted **só depois** da migration entrar em prod.
4. **Dívidas de motorista no admin** — RPC `admin_tvde_driver_balances` (read-only) +
   ecrã PT-BR. Read-only mas lê saldo devedor real → trato como Lista Vermelha.
5. Auditoria do refund de cancelamento (`action:'refund'`).

### FASE 3 — Provas
Cada item do checklist final só é marcado com `SELECT` colado no relatório.
Com Android por USB → testes reais no device (MCP `scrcpy`). Sem device → widget tests +
prova das EFs/`SELECT`.

---

## 3. O que NÃO vou tocar
`dispatch_engine` · `pricing_service.dart` · `finalizePurchase` · `bora_tokens` ·
`stripe-webhook` · todo o fluxo de delivery · preços/comissões · `versionCode`.

---

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo mapeado — confirma que eu avanço.

**Pergunta concreta ao Danilo (uma só):** avanço já com a **FASE 1 (zona verde, só
Flutter)** e deixo a FASE 2 preparada para aprovares item a item? Ou queres que prepare
tudo — verde incluído — sem aplicar nada?
