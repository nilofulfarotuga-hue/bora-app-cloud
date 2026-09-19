# PLANO — Correção Favores (errand) cliente + Comércios da Guarda
> 2026-06-21 · MODO PROTECÇÃO TOTAL · CEO-AI · **EXECUTADO (código) — migrations/EF por aplicar**

## STATUS 2026-06-21 (pós-execução)
**FEITO + flutter analyze 0 erros** (Blocos 1–7 + 8.1/8.3/8.4):
- NOVOS: `lib/widgets/business_autocomplete_field.dart`, `lib/screens/admin/admin_businesses_screen.dart`,
  `supabase/functions/import-guarda-businesses/index.ts`, 3 migrations
  (`20260621100000_errand_request_photo.sql`, `20260621100100_errand_receipt_client_rls.sql`,
  `20260621100200_admin_guarda_businesses_rpcs.sql`).
- EDITADOS: errand_form_screen, cart_store, order_store, payment_method_screen,
  order_details_screen, errand_execution_sheet, carry_groceries_form_screen,
  admin_order_detail_screen, admin_dashboard_screen, order_model.
- `create_order`/pricing/dispatch/Stripe/tokens INTOCADOS. Foto 8.1 persiste via RPC
  dedicada `client_set_errand_request_photo` (não toca create_order).
- ⚠️ EXTRA além da aprovação literal: a migration 8.3 inclui também uma policy RLS em
  `storage.objects` (bucket `receipts`, owner-scoped) — necessária para a foto do talão
  abrir ao cliente. Confirmar antes de aplicar.

**PENDENTE (prod):** aplicar as 3 migrations (MCP/CI) + deploy da Edge Function
`import-guarda-businesses` + correr o import 1×. **8.2 continua gated** (aguarda diff do
`finalize_errand_purchase`).


## Confirmações exigidas (ENTREGA §2)

**(a) NÃO toco em lógica financeira de servidor.** `create_order`, `pricing_calculate`,
`pricing_calculate_errand`, `quote_order_pricing`, dispatch, triggers financeiros, tokens,
Stripe — intocados. O ramo `errand` de `create_order` JÁ EXISTE no servidor e já espera os
campos `errand_*`. O meu trabalho é Flutter + 1 Edge Function de import + 4 RPCs admin (só
leitura/escrita da tabela `guarda_businesses`, zero dinheiro) + 1 tela admin.

**(b) Outros service types não mudam de breakdown.** No `payment_method_screen.dart` ramifico
**só** `serviceType == errand`. `restaurant`/`storeShopping`/`carryGroceries`/`sendPackage`
ficam byte-a-byte iguais. Confirmo por grep pós-edição.

**(c) Padrão de guard admin a replicar:** `public._admin_op_guard()` (migration
`20260428000005`), invocado como
`SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();` + auditoria via
`PERFORM public.log_admin_action(action, entity_type, entity_id, jsonb)`. Como `guarda_businesses.id`
é UUID, uso `entity_id` (não `entity_id_text`). Réplica EXATA dos RPCs admin existentes.

**(d) Provedor de geocoding = GOOGLE** (Places Autocomplete + Place Details + Geocoding
fallback) em `place_autocomplete_service_io.dart`, chave `googleApiKey` de `maps_config.dart`.
**O bug histórico de tap-select JÁ ESTÁ CORRIGIDO**: `AddressAutocompleteField` tem GUARD 1
(síncrono) + GUARD 2 (eco IME assíncrono); `_onSelect` resolve coords e chama
`onSelected(description, coords)`. Funciona. **Não precisa correção — só precisa ser LIGADO**
ao formulário de Favores (que hoje usa `TextField` cru).

---

## DIAGNÓSTICO FINAL (causa-raiz por bug)

1. **Sem autocomplete + coords falsas.** `errand_form_screen.dart` `_StepWhere` (linhas 459-479)
   usa `TextField` cru cujos callbacks (`onErrandLocationPicked`/`onDropoffPicked`/`onHomePicked`,
   linhas 311-323) gravam **coordenadas FIXAS hardcoded** (`LatLng(40.5374,-7.2667)` /
   `LatLng(40.5395,-7.2700)`). Nunca há morada nem coords reais.
2. **"Confirmar morada paragem em casa" não faz nada.** `onHomePicked` grava coords falsas e
   **não há confirmação visual**; se o utilizador não tocar, `_home` fica null.
3. **Ecrã de pagamento errado.** `payment_method_screen.dart` (linhas 271-314) usa
   `cartStore.pricingBreakdown` (= `PricingService.calculateBreakdown`, modelo genérico
   €2,50+€0,50/km + taxa serviço) → para errand mostra Subtotal €0 / Entrega €2,50 / Taxas.
   O quote correto do favor está em `cartStore.errandSession.quote` mas é **ignorado** aqui.
4. **"Não foi possível criar o pedido"** — dupla causa:
   - `cart_store.dart finishOrder` BLOQUEIA todos os errands: `_pickupLocation == null`
     (favor sem paragem) → `return false` (linha 635); `_dropoffStreet.isEmpty`
     (sempre, o wizard nunca preenche) → `return false` (linha 651).
   - `order_store.dart createOrder` constrói `rpcInput` (815-873) **sem nenhum campo
     `errand_*`** → servidor lança `MISSING_ERRAND_LOCATION_COORDS`/`MISSING_DROPOFF_COORDS`.
5. **Cartão vs dinheiro confuso** → BLOCO 6 (UX).

> Nota: `OrderModel` já tem TODOS os campos errand e `fromSupabase` já os lê (linhas 200-214,
> 505-515). Mas `createOrder` monta `rpcInput` à mão (não via `toSupabase`), por isso a correção
> é adicionar as chaves no `rpcInput` + propagar params em `createOrder`/`finishOrder`.

---

## BLOCO 1 — Widget `BusinessAutocompleteField` (NOVO)
**CRIAR** `lib/widgets/business_autocomplete_field.dart`
- Chama RPC `search_businesses(p_query, p_lat, p_lng, p_limit)` via Supabase (debounce 300ms,
  min 2 chars; com GPS lista os mais próximos com query vazia ao focar).
- Resultados: badge "Loja Bora" (`source='bora'`) vs comércio normal (`source='osm'`); distância
  ("0,4 km") quando houver. `onSelected(name, LatLng)` grava nome + coords.
- Texto livre permitido (fallback geocodificado no BLOCO 3.5).
- Reusa o padrão de overlay e estilo do `AddressAutocompleteField`; GPS via
  `LocationService.getCurrentLocation()`. Design system (#16A34A/#F97316/Inter).

## BLOCO 2 — Autocomplete de rua (verificar + ligar)
- **Provedor = Google. Bug tap-select = já corrigido** (ver (d)). Sem alteração ao widget.
- **VERIFICAR** que `carryGroceries` (entrega) e `sendPackage` (recolha+entrega) já usam
  `AddressAutocompleteField` a gravar coords; ligar onde faltar. (Ficheiros a confirmar em
  execução: ecrãs de carry/send.)

## BLOCO 3 — Ligar autocompletes + garantir coords
**EDITAR** `lib/screens/errand_form_screen.dart` (edição principal):
- 3.1 Local do favor → `BusinessAutocompleteField` (grava `_errandLocation` nome+coords).
- 3.2 Onde entregar → `AddressAutocompleteField` (grava `_dropoff` + strings rua/cidade).
- 3.4 Paragem em casa → `AddressAutocompleteField` com 1-toque para morada guardada/atual do
  cliente (coords); confirmação visual ("✓ Morada da paragem definida").
- Remover coords placeholder (311-323).
- 3.5 GUARD submissão: desativar "Continuar para pagamento" até ter coords do favor + coords da
  entrega + descrição + (se paragem) coords da casa. Texto livre → geocodificar antes de
  submeter; se falhar, mensagem clara ("não consegui localizar esse sítio, escolhe da lista").

**EDITAR** `lib/stores/cart_store.dart`:
- `configureErrandSession` — gravar também `_dropoffStreet`/`_dropoffCity` (vindos do form) e a
  distância multi-segmento (BLOCO 4).
- `finishOrder` — **ramo errand**: não bloquear quando `_pickupLocation == null` (favor sem
  paragem); garantir `dropoffStreet` definido; passar campos `errand_*` a `createOrder`.

**EDITAR** `lib/stores/order_store.dart`:
- `createOrder` — novos params nomeados `errand*` + chaves `errand_*` no `rpcInput`; para errand
  **não** sobrepor a distância com o recompute google de 2 pontos (linhas 740-756) — confiar na
  distância multi-segmento recebida.

## BLOCO 4 — Distância correta
- Calcular distância real do percurso: soma de segmentos (casa→favor→entrega, ou favor→entrega)
  via `MapsService.getDistanceKm` por segmento. Substituir o placeholder `distance_km: 1.0` em
  `_refreshQuote` (errand_form_screen.dart:122) e gravar no quote/cart. Servidor valida
  `distance_km ≥ haversine(segmentos)×0,8` — distância real passa folgada.

## BLOCO 5 — Preço correto no ecrã de pagamento (errand)
**EDITAR** `lib/screens/payment_method_screen.dart` — ramo `isErrand`:
- Render do resumo a partir de `cartStore.errandSession.quote`: **Favor** (`base_fee`) ·
  **Paragem em casa** +€2 (se houver) · **Km extra** (se houver) · **Compra estimada** (se houver,
  1:1) · **Total**. SEM "Subtotal €0", SEM "Entrega €2,50", SEM "Taxas/15%".
- `totalToPay`/`finalPrice` a partir de `customer_total` do quote errand. Esconder toggle de
  tokens (§55.3: cliente ganha/usa 0 tokens em errand). Wallet/dívida/cash-limit mantêm-se.
- Anti-regressão: tudo o resto intacto (ramo só-errand).

## BLOCO 6 — Clareza cartão vs dinheiro (UX)
**EDITAR** `errand_form_screen.dart` + `payment_method_screen.dart`:
- >€40 sem paragem → já força paragem (`_forcedHomeStopByEstimate` + diálogo amigável) — manter.
- Cartão + compra: explicar que o cartão pode **segurar** estimativa×1,2 como garantia e que o
  valor final é o do **talão**; mostrar garantia separada do total estimado.
- Dinheiro + compra + paragem-dinheiro: perguntar quanto vai entregar e validar ≥ estimativa.
- Texto Passo 1 (disclaimer receita) já existe — confirmar.

## BLOCO 7 — Import comércios + Admin
- 7.1 **CRIAR** `supabase/functions/import-guarda-businesses/index.ts` — Overpass (raio 8km de
  40.5373,-7.2674; `node`/`way` com `shop=*` + `amenity` em {pharmacy,cafe,restaurant,fast_food,
  bar,bakery,fuel,marketplace}; `out center tags;`); normaliza `category`; **upsert por `osm_id`**
  (`node/123`/`way/123`); service role (`SUPABASE_URL`+`SUPABASE_SERVICE_ROLE_KEY`); padrão ESM.sh;
  reporta contagem. Só comércios estruturais.
- 7.2 **CRIAR** migration `<ts>_admin_guarda_businesses_rpcs.sql` — `admin_list_businesses`,
  `admin_upsert_business`, `admin_set_business_visibility`, `admin_delete_business` (todas com
  `_admin_op_guard()` + `log_admin_action`).
- 7.2 **CRIAR** `lib/screens/admin/admin_businesses_screen.dart` (PT-BR: lista paginada+busca,
  editar, esconder/mostrar, apagar, adicionar manual, botão "Reimportar comércios da Guarda").
- 7.2 **EDITAR** `lib/screens/admin/admin_dashboard_screen.dart` — `_NavCard` "Comércios da Guarda".

---

## Validação de preço (ENTREGA §3)
Normal €6 / Expresso €10 / +€2 paragem / +€0,50 km / compra 1:1 — o `_Breakdown` do form
(linhas 648-664) já mapeia `base_fee`/`home_stop_fee`/`km_extra_fee`/`purchase_estimate`/
`customer_total` corretamente; o ecrã de pagamento passará a usar o MESMO quote. Bate ao cêntimo.

## Bugs fora de scope encontrados
- Comentário em `errand_form_screen.dart:119` refere `CartStore.refreshMultiSegmentDistance` que
  **não existe** (a criar no BLOCO 4).
- `finishOrder` bloqueia 100% dos errands hoje (já coberto pelo BLOCO 3).

## Ordem de execução proposta
7.1+7.2 (import primeiro, para popular dados de teste) → 1 → 3 → 4 → 5 → 6 → 2 (verificação) →
`flutter analyze` (0 erros) → `/ctx doctor` + `/ctx stats`.

---

# ADENDA (2026-06-21) — confirmações A + BLOCO 8 + admin C

## A) 3 constraints duras (integradas)
1. **Zero coords fixas** em TODO o fluxo errand (remover os 2 placeholders Guarda + qualquer
   fallback). `distance_km` vem só de coords reais (favor/casa/entrega).
2. **carryGroceries explícito:** campo da loja em "Leva a tua compra" passa de
   `AddressAutocompleteField` → **`BusinessAutocompleteField`** com **GPS pre-fill**: ao abrir,
   `search_businesses('', lat, lng, 1)`; se ≤ 0,15 km, pré-preenche (editável) nome+coords.
   (`carry_groceries_form_screen.dart`.)
3. **Guard submissão + geocode fallback (Google `geocodeAddress`)**: bloquear finalizar sem
   coords reais; texto livre → geocodificar antes de submeter; falha → mensagem clara; **nunca**
   submeter com coords nulas/fixas.

## B) BLOCO 8 — 8.1 / 8.3 / 8.4 (entram com o principal); 8.2 em mini-plano separado
- **8.4 Atalhos (FÁCIL):** chips no topo do form (`errand_form_screen.dart`) que pré-preenchem a
  descrição (editável) + focam o campo: "Farmácia"/"Levantar encomenda"/"Pagar conta"/
  "Buscar/entregar chaves". Ícones Material existentes. Sem PNG novo.
- **8.1 Foto do que comprar (FÁCIL):** campo opcional câmara/galeria no form (ImagePicker, já
  usado em `errand_execution_sheet.dart:85`). Upload reutiliza infra de fotos de pedido
  (`order-photos` bucket privado, padrão de `_packagePhotoUrl`). **MIGRATION ADITIVA**: coluna
  `orders.errand_request_photo_url`. Threading: form → `configureErrandSession` → `finishOrder`
  → `createOrder` rpcInput. Estafeta vê no execution sheet (`_buildPurchase`/`_Header`). Descrição
  continua obrigatória.
- **8.3 Talão ao cliente (FÁCIL):** em `order_details_screen.dart` (secção errand), mostrar foto
  do talão (`order_receipts_v2.photo_url`, via `PrivateBucketImage` que assina o bucket privado
  `receipts`) + `final_purchase_value`/`final_total` vs `errand_estimated_purchase_cents`.
  **MIGRATION (RLS)**: policy SELECT em `order_receipts_v2` para o cliente dono do pedido.
- **8.2 Over-budget:** ver `MINIPLANO_8_2_AUMENTO_ORCAMENTO_2026_06_21.md` — **gated**.

## C) Admin (resposta)
`admin_orders_screen.dart` já filtra 'Favores' mas abre `admin_order_detail_screen.dart` (4 abas
genéricas) que **não mostra campos errand**. → **Estender** a aba Resumo desse ecrã para, quando
`service_type=='errand'`, mostrar descrição/local/estimativa/`final_purchase_value` + foto do
pedido (8.1) + (futuro) eventos de aumento (8.2). (Edição aditiva, ramo só-errand.)

## Deltas de DB descobertos na exploração (NOVOS vs plano principal)
- MIGRATION aditiva: `orders.errand_request_photo_url` (8.1).
- MIGRATION RLS: SELECT cliente em `order_receipts_v2` (8.3).
- (8.2 traz outra migration — só após OK do mini-plano.)

## Ficheiros consolidados: 3 novos, ~9 editados, 3 migrations
NOVOS: `business_autocomplete_field.dart`, `admin_businesses_screen.dart`,
`import-guarda-businesses/index.ts`.
EDITADOS: `errand_form_screen.dart`, `cart_store.dart`, `order_store.dart`,
`payment_method_screen.dart`, `admin_dashboard_screen.dart`, `carry_groceries_form_screen.dart`,
`errand_execution_sheet.dart` (8.1 ver foto), `order_details_screen.dart` (8.3),
`admin_order_detail_screen.dart` (C). (send_package já OK.)
MIGRATIONS: `<ts>_admin_guarda_businesses_rpcs.sql`, `<ts>_errand_request_photo.sql` (8.1),
`<ts>_errand_receipt_client_rls.sql` (8.3).
