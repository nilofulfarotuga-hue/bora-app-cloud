# TVDE — o plano passa a ter preço PELA ROTA (Flutter)

> Data: 2026-08-25 · Branch: `tvde/reserva-agendada-2026-08-20` · Executor headless (Opus)
> Âmbito: **SÓ FLUTTER.** O servidor já estava pronto e provado por MCP nesta data.
> **Não** se criou migration, nem se tocou em função SQL ou Edge Function.

## A queixa do Danilo

Os cartões dos planos não diziam nada — nem quantas viagens dão, nem que a
distância incluída depende da rota. E o preço aparecia cravado, igual para
quem faz 3 km e para quem faz 30 km.

## O que existe no servidor (usado, não alterado)

| Peça | Assinatura / campos |
|---|---|
| RPC `tvde_quote_plan(p_plan, p_distance_km)` | devolve `base_km, extra_km, rides_total, days, per_km_cents, base_price_cents, extra_cents, price_cents, per_ride_cents` |
| `tvde_subscriptions` / `tvde_plan_requests` | ganharam `km_included`, `distance_km`, `route_origin_label`, `route_dest_label` |
| RPC `tvde_request_plan` | `(p_plan, p_plan_label, p_distance_km, p_origin_label, p_dest_label)` |
| RPC `admin_grant_subscription` | `(p_client_id, p_plan, p_km_included, p_origin_label, p_dest_label)` |
| Edge `tvde-plan-payment` v7 | aceita `distance_km` / `origin_label` / `dest_label` em `create` e `create_mbway`; calcula o valor no servidor e devolve `quote` + `amountCents` |

## TAREFA A — o cliente escolhe a rota antes de ver qualquer valor ✅

`lib/screens/client/tvde/tvde_plans_screen.dart` (reescrito).

1. Bloco **"A tua rota habitual"** no topo dos planos, com dois campos
   `AddressAutocompleteField` — **o mesmo seletor de moradas da corrida normal**.
2. Distância pelo **mesmo cálculo da corrida normal**: `DirectionsService.fetchRoute`
   com 2 tentativas (uma falha transitória subestimava o km) e haversine
   (`latlong2 Distance`) só como último recurso.
3. Com o km na mão, chama `tvde_quote_plan` para os 3 planos e mostra a
   **CONTA ABERTA em PT-PT, linha a linha**, antes do botão de pagar:

```
Plano Semanal                                       40,00 €
Inclui 10 viagens            2 por dia, segunda a sexta
Distância incluída                 até 6 km por viagem
A tua rota                                          8 km
2 km a mais × 1,00 € × 10 viagens                   20,00 €
TOTAL                                               60,00 €
```

4. **O botão só acende depois de haver orçamento** — sem rota diz
   "Escolhe a rota primeiro" e está desativado (`onAderir: null`). Editar um
   campo à mão invalida a rota e apaga o orçamento outra vez.
5. `distance_km`, `origin_label` e `dest_label` seguem para a Edge **nos dois
   caminhos** (cartão e MB Way). O caminho de **activação ficou como estava**
   (`activate` com `plan` + `payment_intent_id`).
6. **Zero valores no código.** Removeu-se `TvdeStore.planPriceCents()` (ficou
   sem chamadores) e o mapa `_ridesTotal = {semanal:10, quinzenal:20, mensal:44}`.
   O MB Way passa a mostrar o `amountCents` que o servidor devolveu.

## TAREFA B — os cartões passam a dizer o que dão ✅

Cada cartão diz agora, **antes** de haver rota:
`"10 viagens · 2 por dia · Segunda a Sexta"` +
*"A distância incluída em cada viagem depende da rota que escolheres — escolhe-a
acima para veres a conta."*

Esses números também **vêm do servidor**: no arranque o ecrã orça a **1 km**
(distância simbólica, só para ler a FORMA do plano — `rides_total`, `days`,
`base_km`, `per_km_cents`). **O valor desse orçamento nunca é mostrado.**
Se a chamada falhar, o cartão simplesmente não mostra a contagem — nunca
inventa números.

## TAREFA C — "o meu plano" mostra a rota guardada ✅

O cartão da subscrição ativa (mesmo ecrã) passa a mostrar:
- **A tua rota:** `origem → destino` (só se houver rota guardada);
- **Incluído:** `até X km por viagem` (de `km_included`; nas subscrições antigas
  cai para o `base_km` do plano);
- a frase *"Acima de X km, cada km a mais custa 1,00 € por viagem."* — o
  **1,00 € vem do servidor** (`per_km_cents`), não do código.

`TvdeSubscription` ganhou `kmIncluded`, `distanceKm`, `routeOriginLabel`,
`routeDestLabel` e o getter `hasRoute`.

## TAREFA D — painel admin (PT-BR, autoridade total) ✅

**`admin_tvde_subscriptions_screen.dart`**
- Cada assinatura mostra `Km incluídos: X km/viagem · rota de Y km` e
  `Rota: origem → destino` (`—` quando não há).
- **Conceder à mão:** cliente → plano → **novo diálogo** onde o admin escreve
  os km da rota e a rota (origem/destino, opcionais), carrega em
  **"Ver orçamento"** (chama `tvde_quote_plan`) e vê a mesma conta que o cliente
  veria. **O botão "Conceder" só acende depois de haver orçamento.** Confirma e
  chama `admin_grant_subscription(p_client_id, p_plan, p_km_included,
  p_origin_label, p_dest_label)`.
- O diálogo de escolha de plano deixou de dizer "Semanal — 14 corridas (7 dias)"
  (números fixos que já **não batiam** com o servidor); agora só lista os nomes e
  quem diz as contas é o orçamento no passo seguinte.

**`admin_tvde_plan_requests_screen.dart`**
- Cada pedido mostra `Rota: origem → destino`, `Km da rota: Y km · incluídos: X km/viagem`
  e **`Valor orçado: 60,00 € (base 40,00 € + 2 km a mais = 20,00 €)`** — o valor
  é pedido ao servidor (`tvde_quote_plan`) para o plano + os km do pedido, nunca
  calculado no app.

## Ficheiros tocados

| Ficheiro | O quê |
|---|---|
| `lib/models/tvde_plan_quote.dart` | **novo** — espelho de `tvde_quote_plan` + a conta aberta PT-PT |
| `lib/models/tvde_subscription.dart` | + `km_included`, `distance_km`, rota, `hasRoute` |
| `lib/stores/tvde_store.dart` | + `quotePlan()`; rota nos 3 caminhos (`createPlanPayment`, `createPlanPaymentMbway`, `requestPlan`); − `planPriceCents()` órfão |
| `lib/screens/client/tvde/tvde_plans_screen.dart` | reescrito — TAREFAS A + B + C |
| `lib/screens/admin/admin_tvde_subscriptions_screen.dart` | TAREFA D (km/rota na lista + orçamento no conceder) |
| `lib/screens/admin/admin_tvde_plan_requests_screen.dart` | TAREFA D (rota, km e valor orçado no pedido) |
| `test/tvde_plan_quote_test.dart` | **novo** — 10 testes |

## Provas (saída literal)

`dart analyze` por lotes (o `flutter analyze` inteiro rebenta por RAM no PC de 4 GB):

```
Analyzing tvde_plan_quote.dart, tvde_subscription.dart, tvde_plans_screen.dart...
   info - tvde_plans_screen.dart:149:19 - Don't use 'BuildContext's across async gaps - use_build_context_synchronously
1 issue found.                                    ← CORRIGIDO (store lido antes dos await)

Analyzing admin_tvde_subscriptions_screen.dart, tvde_plans_screen.dart...
No issues found!

Analyzing admin_tvde_plan_requests_screen.dart, tvde_store.dart, tvde_plan_quote_test.dart...
No issues found!
```

`flutter test` dos 6 ficheiros TVDE:

```
00:33 +55: All tests passed!
```

Os 10 testes novos, isolados:

```
00:00 +0: TvdePlanQuote.fromMap lê todos os campos do servidor
00:00 +1: TvdePlanQuote.fromMap campo em falta não rebenta — fica 0 (e o ecrã não acende o botão)
00:00 +2: TvdePlanQuote.fromMap viagens por dia vêm do servidor (10 viagens / 5 dias = 2)
00:00 +3: conta aberta (PT-PT) rota acima do incluído — base + excesso + TOTAL
00:00 +4: conta aberta (PT-PT) a conta fecha: base + excesso = TOTAL
00:00 +5: conta aberta (PT-PT) rota dentro do incluído — sem linha de excesso
00:00 +6: formatação PT-PT euros com vírgula
00:00 +7: formatação PT-PT km sem casas decimais inúteis
00:00 +8: TvdeSubscription — rota guardada lê km incluídos e rota da subscrição
00:00 +9: TvdeSubscription — rota guardada subscrição antiga sem rota não finge ter uma
00:00 +10: All tests passed!
```

## ⚠️ O que FICA por confirmar (não é suposição minha, é uma dependência real)

O painel admin lê as assinaturas por `admin_tvde_subscriptions_list()` e os
pedidos por `admin_tvde_plan_requests_list()`. Essas duas RPCs montam a resposta
com `jsonb_build_object(...)` **campo a campo** (ver
`supabase/migrations/20260626100005_tvde_admin_read_rpcs.sql`).

**Se elas não tiverem sido actualizadas no servidor** para devolver também
`km_included`, `distance_km`, `route_origin_label` e `route_dest_label`, o
painel mostra `—` nessas colunas (o app lê com segurança e não rebenta) — mas o
Danilo não vê os km nem a rota.

Não pude confirmar: esta ordem proibia mexer em SQL, e o MCP do Supabase não
existe no executor headless (modo `-p` corre sem `--mcp-config`). Fica como o
único ponto por fechar, e é **uma linha de SQL em cada RPC**, não trabalho de
Flutter.

## Nota sobre dinheiro

Nada nesta entrega calcula, define ou altera preço. O app **só pergunta e
mostra**: todo o valor vem de `tvde_quote_plan` / da Edge `tvde-plan-payment`,
e o valor cobrado é o que a Edge recalcula. `pricing_service.dart`,
`dispatch_engine`, `finalizePurchase`, `bora_tokens` e o webhook Stripe não
foram tocados.
