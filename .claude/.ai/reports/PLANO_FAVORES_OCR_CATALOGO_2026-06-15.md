# PLANO — Blocos 1-4: Transparência de Preço · Favores (errand) · Gemini OCR Talão · Catálogo Automático
> Data: 2026-06-16 · Modo: PROTECÇÃO TOTAL · Estado: **TODAS AS FASES COMPLETAS ✓ (Blocos 1, 2, 3, 4 + §55)**
> **Fase 6 (Bloco 3 OCR):** `ocr-receipt` upgraded gemini-1.5 → **gemini-2.5-flash** com `thinkingBudget=0`; extrai `{store, total_cents, lines:[…], datetime}`; grava `receipt_parsed`, `receipt_parsed_total_cents`, `receipt_parsed_store`, `receipt_match`; divergência `|digitado-parsed| > receipt_divergence_alert_cents (100)` → `match=false`; kill-switch `receipt_ocr_enabled`; retrocompat mantida (ocr_extracted/diff/flagged legacy).
> **Fase 7 (Bloco 4 + Admin):** 4 RPCs (`admin_list/approve/reject/edit_errand_item`) + helper `_errand_normalize` + trigger `fn_enqueue_errand_catalog` (on UPDATE de receipt_parsed → enfileira lines). Aprovação cria loja non-partner OCULTA (`is_partner=false, is_online=false`, padrão Wells/Worten) + produto `source='errand_auto'` com dedup por nome normalizado. NOVO `admin_errand_catalog_screen.dart` (PT-BR — pendentes/aprovados/rejeitados/todos + lote + editar nome/preço/categoria). Filtro "Favores" em `admin_orders_screen.dart` (corrige 'delivery' p/ excluir errand). Campos OCR adicionados ao SELECT em `admin_receipts_screen.dart`. NavCard "Catálogo de Favores" em `admin_dashboard_screen.dart`.
> **Fase 8 (Fecho):** §55 em `business_rules.md` com 16 sub-secções (tabela preços, distância, tokens, pagamentos, medicamentos, cancelamento, status mapping, dispatch, disponibilidade, S1, imutabilidade, OCR, catálogo, execução estafeta, chat, fora-de-scope).
> Gatilho execution sheet: botão "Tratar do favor" no driver_home_screen (row 2.5, antes de cancel delivery), abre `ErrandExecutionSheet.show(context, order)` — E2E desbloqueado.
> **Bloco 1** (transparência preço carry/send): novo `lib/widgets/quote_price_footer.dart` (rodapé sticky, invoca `quote_order_pricing` via `PaymentService.quoteOrder`, mostra "desde €6" sem moradas e total exacto com moradas + "Ver detalhe" para breakdown). Integrado em `send_package_form_screen.dart` e `carry_groceries_form_screen.dart` via `bottomNavigationBar`. Zero alteração ao fluxo do botão "Continuar" existente.
> **N3** (Pedir de novo): `ErrandPrefill` class + `ErrandFormScreen(prefill:)` parâmetro opcional + `initState` pré-preenche 7 campos. Botão "Pedir de novo" no `orders_screen.dart` envolvendo `_OrderCard` em Column quando `serviceType==errand`. `flutter analyze`: **0 errors** (165 issues, todos pré-existentes).
> Fase 4: `supportsService` errand em car+moto, `canAssignOrder` errand não-batchable (mesmo bloqueia novos assigns p/ drivers com errand activo), badges FAVOR/EXPRESSO/PARAR EM CASA no `_showNewOrderDialog`, `CartStore.configureErrandSession` + `ErrandSession` class, 3 helpers `markErrandArrivedAtErrand/OnTheWay/Delivered` no `OrderStore` (mapping N6: driverAccepted→pickedUp→onTheWay→delivered), wiring real do checkout (N4 resolvido — SnackBar→`Navigator.push(PaymentMethodScreen)`), e novo `lib/widgets/errand_execution_sheet.dart` com 3 fases (recolha c/ S1+N5 aviso cash<estimativa, compra c/ foto+talão→`finalize_errand_purchase`, entrega c/ "valor a cobrar"/"troco a devolver"/"nada a cobrar"). `flutter analyze`: **0 errors** (162 issues, todos warnings/infos pré-existentes ou tolerantes).
> Fase 3: enum `errand` + 10 fields no `OrderModel` + serialização + `OrderType.errand` + 2 switches exaustivos em `order_store.dart` + `tileErrand` (teal) + `quoteOrder()` em `PaymentService` + tile "Favores" no `client_home_screen` + textos próprios em `order_tracking_screen` (chat já genérico, N1 ✓) + `errand_form_screen.dart` (wizard 3 passos com rodapé live, UX 1–7, G1 receita-positiva, G5 disclaimer, D4 forçar paragem >€40, S1 trava cash). `flutter analyze`: **0 erros novos** (baseline 161→159 issues, todos info/warning pré-existentes).
> 2.C `finalize_errand_purchase` (P1 charge-extra + P2 is_purchase_finalized + GUC bypass) e trigger tokens com excepção cliente errand. **byte-a-byte trigger:** md5(stripped) = `c1e32491…` = ANTES. Cliente errand 0 tokens; estafeta +40 (default non-partner).
> 2.A `pricing_calculate` md5 antes=depois (`b9fa35b4…`); 5 vectors idênticos; A/B/C ao cêntimo.
> 2.B `create_order` md5(stripped errand) = `7615ae95…` = ANTES → **byte-a-byte garantido** (diff 0 chars). Branch errand cresce +9.787 bytes isolados; final_total fica NULL (escrita só em 2.C via GUC bypass). Inclui SEC-1, SEC-2 (haversine ×0.8), kill-switch `errand_available`, S1 cash-paragem, D4 cash>€40, `errand_max_advance_cents`. Re-emissão necessária na 1ª tentativa por comentários do original omitidos.
> Auditoria concluída (5 áreas). Matemática A/B/C ao cêntimo. **Fase 1 (DB aditiva) aplicada em prod 2026-06-15** — migrations `errand_phase1_schema`, `errand_catalog_queue`, `errand_phase1_settings` (verificadas: 10 cols orders, 4 cols receipts, queue+RLS, 18 settings). Fases 2-8 por implementar.

---

## 0-BIS. ADENDA v2 (2026-06-15) — Aprovação condicional + confirmações de código

**Estado:** Plano aprovado na arquitectura. Decisões fixadas: **D1-A** (estender `ocr-receipt`), **D2-A** (RPC `quote_order`), **D3 = estafeta +40**, **D4-A** (forçar paragem-casa-dinheiro >€40). Incorporadas correcções **G1–G7**, sugestões **S1–S2** e princípios de **UX 1–7**.

### Confirmações G3/G4/G6/G7 (provadas no código)
| Item | Resultado | Acção |
|---|---|---|
| **G3** markup 15% non-partner | ✅ Automático: `pricing_calculate` aplica `0.15` + fee €2,50 + fórmula estafeta non-partner (`20260425000001_batch_d_pricing_calculate.sql:43,95-111`) | Bloco 4 funciona sem tocar pricing |
| **G4** horário | ❌ `create_order` **NÃO** valida horário; `business_hours` só existe **por loja parceira** (`is_partner_open()`), não há horário global de plataforma | Ver **PONTO-ABERTO-H** abaixo |
| **G6** distância multi-segmento | ✅ `DirectionsService.fetchRoute()` **já suporta waypoints** (`directions_service.dart:69-74`) → 1 chamada casa→favor→entrega | Reusar; somar via 1 waypoint |
| **G7** settings UI | ✅ `admin_platform_settings_screen.dart:53-61` allowlist hardcoded | Adicionar `errand_*` + `receipt_*` à allowlist |
| **G7** lista pedidos | ✅ `admin_orders_screen.dart` filtro service_type | Adicionar `('errand','Favores')` + detalhe |
| **G7** talões/reembolsos | ✅ `admin_receipts_screen.dart` genérico (`order_receipts_v2`) | errand aparece **automaticamente** |
| **G7** settlements | ✅ `admin_settlements_screen.dart` soma `ledger_entries` | errand entra automaticamente |
| **G7** `products.source` | ❌ **NÃO existe** a coluna | Migration `ALTER TABLE products ADD COLUMN source TEXT DEFAULT 'manual'` |

### 🔴 ACHADOS DE SEGURANÇA (pré-existentes, fora do scope mas relevantes)
- **SEC-1 — `is_partner_store` é spoofable.** `create_order` lê `is_partner_store` do **input do cliente** (`20260504050000…:69`), não da tabela `restaurants`. Cliente malicioso pode forçar pricing de parceiro. → **Para errand: forçar `is_partner=false` no branch (seguro).** Recomendo (com aprovação) hardening geral: validar contra `SELECT is_partner FROM restaurants WHERE id=…`.
- **SEC-2 — `distance_km` é spoofable.** `create_order` confia no `distance_km` do cliente (só valida `<0`). Cliente pode pôr distância baixa e pagar menos. → **Mitigação errand (Fase 2):** backend soma `haversine(casa→favor→entrega)` das coordenadas e exige `distance_km >= mínimo`. Aplicar idealmente também a carry/send (anotado).

### PONTO-ABERTO-H (horário de favores) — decisão menor, não bloqueia Fase 1
Não existe horário global de plataforma. Proposta v1: settings novos `errand_hours_enabled=true`, `errand_open_minutes=480` (08:00), `errand_close_minutes=1440` (24:00), editáveis no admin; `create_order` valida só para `errand`. Confirmar na Fase 2.

### Correcções incorporadas (resumo)
- **G1** Medicamentos com receita = **permitido** com paragem-casa motivo "receita" → §3 errand_form + §7 business_rules (texto positivo).
- **G2** Campos `receipt_parsed*` ficam em **`order_receipts_v2`** (com os `ocr_*`), não em `orders`.
- **G5** Disclaimer no Passo 1 do wizard (ilegais/armas proibidos; receita→paragem casa).
- **S1** Trava de segurança: se `errand_home_stop_cash_cents < estimativa` → aviso/bloqueio (estafeta não fica a perder).
- **S2** Admin: botão "abrir chat com estafeta" no detalhe de pedido com divergência OCR.
- **UX 1–7** Wizard em linguagem humana: cards Normal/Expresso com tempos, paragem em 1 linha, estimativa com exemplo, mensagem amigável no forçar >€40, rodapé sticky com total live + "ver detalhe", resumo final com "~", placeholders com exemplos reais. Meta: "a avó consegue pedir".

---

## 0. ACHADOS CRÍTICOS DA AUDITORIA (lê antes de aprovar)

1. **🔴 BLOCO 3 — `ocr-receipt` JÁ EXISTE.** Há uma Edge Function `supabase/functions/ocr-receipt/index.ts` que já faz OCR do talão com Gemini (1.5-flash), em modo *shadow* não-bloqueante, e escreve `ocr_extracted_total_cents`, `ocr_diff_cents`, `ocr_flagged`, `ocr_raw_response` na tabela `order_receipts_v2` (threshold actual = 50 cents). **O Bloco 3 deve ESTENDER esta função, não criar `parse-receipt` do zero** (ver Decisão D1). Reusar = um só caminho OCR, menos superfície.

2. **🟡 PRICING TEM DUPLA FONTE.** O cálculo vive em DOIS sítios que têm de ficar idênticos:
   - SQL (fonte de verdade): `pricing_calculate()` em `supabase/migrations/20260425000001_batch_d_pricing_calculate.sql` (chamado por `create_order`).
   - Flutter (espelho para UI): `lib/services/pricing_service.dart` (`_packageBaseFee=6.0`, `_packageExtraPerKm=0.5`, base 4km).
   O branch `errand` tem de ser adicionado a AMBOS, com a mesma matemática. (Ver Decisão D2 sobre como a UI obtém o preço live.)

3. **🟡 BLOCO 1 não é um "6€ hardcoded enganador".** O breakdown no checkout (`payment_method_screen.dart`) já é real. O problema é **timing**: os forms (`send_package_form_screen.dart`, `carry_groceries_form_screen.dart`) só recolhem moradas+foto e o cliente só vê o preço no checkout. Fix = mostrar preço **live no form** assim que origem+destino estão preenchidos.

4. **🟢 Chat, dispatch e tracking já são genéricos por service_type** — sem allowlist que exclua tipos novos. `errand` é aceite automaticamente assim que o enum + `supportsService()` o suportam. Falta só UI (badges, textos de tracking) e verificar que os botões de chat aparecem.

5. **🟡 Tokens:** trigger `trg_award_tokens_on_delivery` (`supabase/migrations/20260404000000_bora_tokens.sql:136-174`). Cliente = `GREATEST(1, ROUND(price×0.03))`; estafeta = **40 fixo** (o "+50 partner" da memória NÃO existe no código — ver §Bugs). Excepção `errand` (cliente 0) entra aqui.

6. **🟡 `enforce_financial_immutability`** bloqueia `price, final_total, subtotal, delivery_fee, service_fee, platform_commission, driver_earnings, bag_fee, payment_buffer_total` pós-criação. Escrever `final_total`/`final_purchase_value` no fim exige o GUC `app.financial_bypass='true'` dentro de RPC auditada `finalize_*` (é assim que o storeShopping V2 já o faz). O `finalize` de errand tem de seguir o mesmo padrão.

7. **🟡 `products.price` é FLOAT8 em EUR**, não cents. O parse do talão devolve cents → converter ao inserir no catálogo (Bloco 4).

---

## 1. DECISÕES QUE PRECISAM DA TUA APROVAÇÃO

| # | Decisão | Opção A (recomendada) | Opção B |
|---|---|---|---|
| **D1** | Bloco 3 OCR | **Estender `ocr-receipt`**: subir para gemini-2.5-flash, extrair loja+total+linhas+data, gravar nos campos novos `receipt_parsed*` + manter `ocr_*`. Um caminho. | Criar `parse-receipt` novo e deprecar `ocr-receipt` (mais código, dois caminhos). |
| **D2** | Bloco 1+2 preço live | **RPC leve `quote_order(p_input)`** que corre a MESMA `pricing_calculate` e devolve breakdown SEM criar pedido. UI nunca calcula nada → zero drift. | UI usa `PricingService` Flutter (espelho local). Mais rápido mas risco de drift entre Dart e SQL. |
| **D3** | Tokens estafeta errand | **+40** (igual a logística normal, como o prompt diz). | +50. |
| **D4** | Caso-limite cash | Em **dinheiro + compra adiantada** se `fees+compra > €40` → forçar paragem-casa-dinheiro (cliente entrega dinheiro da compra na paragem; só taxas contam p/ limite). | Bloquear cash acima de €40 e exigir cartão. |

> Recomendo **A, A, +40, A**. As 4 escolhas estão refletidas no plano abaixo (assumindo as recomendadas).

---

## 2. VALIDAÇÃO MATEMÁTICA (settings do prompt) — bate ao cêntimo

Branch `errand` (tudo em cents; `extra_km = max(0, distance_km − 4)`; `km_fee = round(extra_km×50)`):

```
base_fee     = express ? 1000 : 600
driver_base  = express ? 800  : 500
home_fee     = home_stop ? 200 : 0
home_driver  = home_stop ? 100 : 0
km_fee       = round(max(0, distance_km−4) × 50)        # cliente
km_driver    = round(max(0, distance_km−4) × 50)        # estafeta (100%)
fees_total   = base_fee + home_fee + km_fee
driver_fees  = driver_base + home_driver + km_driver
platform     = fees_total − driver_fees
purchase     = has_purchase ? talão : 0
customer_total = fees_total + purchase
```

- **A** (Normal, 3km, s/ compra, s/ paragem): fees=600 · driver=500 · Bora=100 · cliente **€6,00** ✓
- **B** (Expresso, 6km, paragem, compra €23,50, cartão): km_extra=2→100. fees=1000+200+100=1300 · driver_fees=800+100+100=1000 · Bora=300 · cliente=1300+2350=**€36,50** ✓ · estafeta recebe 1000+2350(reembolso)=€33,50 ✓
- **C** (Normal, 5km, paragem dinheiro €50, compra €23,50): km_extra=1→50. fees=600+200+50=850 · driver_fees=500+100+50=650 · Bora=200 ✓ · troco=5000−2350=**€26,50** ✓ · entrega: cobra €8,50 taxas, devolve troco (líquido devolve €18,00).

---

## 3. BLOCO 1 — Transparência de preço (carryGroceries / sendPackage)

**Objectivo:** preço live no form. Sem moradas → "desde €6". Com origem+destino → valor exacto + breakdown. Valor mostrado == valor cobrado (backend manda).

**Ficheiros a tocar:**
- `lib/screens/carry_groceries_form_screen.dart` — adicionar rodapé sticky de preço; recalcular ao mudar origem/destino.
- `lib/screens/send_package_form_screen.dart` — idem.
- `lib/services/place_autocomplete_service*.dart` / `lib/screens/map_screen.dart` — reutilizar distância origem→destino (Google Routes) já existente; expor para o form (hoje só é usada no checkout).
- **NOVO** RPC `quote_order(p_input jsonb)` (migration nova) — devolve o breakdown de `pricing_calculate` sem criar pedido (Decisão D2-A). Read-only, `SECURITY DEFINER`.
- `lib/services/payment_service.dart` ou um novo `quote_service.dart` — invoca `quote_order`.
- `lib/screens/payment_method_screen.dart` — passa a mostrar o mesmo breakdown vindo do quote (consistência).

**Sem alteração à fórmula** (pricing existente intacto). Só expor o cálculo mais cedo.

---

## 4. BLOCO 2 — Categoria FAVORES (`errand`)

### 4.1 Modelo / enum
- `lib/models/order_service_type.dart` — adicionar `errand`; label "Favores"; desc "Pede um favor a um estafeta".
- `lib/models/order_model.dart` — adicionar campos errand (mapear em `fromSupabase`/`toSupabase`): `errandDescription, errandLocation, errandHomeStop, errandHomeStopReason, errandHomeStopCashCents, errandSpeed, errandHasPurchase, errandEstimatedPurchaseCents`.

### 4.2 Migration ADITIVA `orders` (campos novos — nullable/default)
`errand_description text`, `errand_location text`, `errand_home_stop boolean default false`, `errand_home_stop_reason text`, `errand_home_stop_cash_cents int`, `errand_speed text check (errand_speed in ('normal','express'))`, `errand_has_purchase boolean default false`, `errand_estimated_purchase_cents int` + campos Bloco 3 (§5).

### 4.3 platform_settings (todas editáveis no admin)
`errand_fee_normal_cents=600`, `errand_fee_express_cents=1000`, `errand_driver_normal_cents=500`, `errand_driver_express_cents=800`, `errand_home_stop_fee_cents=200`, `errand_home_stop_driver_cents=100`, `errand_base_distance_km=4`, `errand_per_km_cents=50`, `errand_driver_per_km_cents=50`, `errand_max_advance_cents=4000`, `errand_buffer_multiplier=1.2`, `errand_sla_normal_minutes=180`, `errand_sla_express_minutes=60`, `errand_description_max_chars=500`, `receipt_ocr_enabled=true`, `receipt_divergence_alert_cents=100`, `errand_catalog_queue_enabled=true`.

### 4.4 Pricing — branch `errand` (ADITIVO, em ambos)
- `supabase/migrations/20260425000001_batch_d_pricing_calculate.sql` → **nova migration** que recria `pricing_calculate` com branch `errand` (§2). NUNCA toca os branches existentes.
- `lib/services/pricing_service.dart` — branch `errand` espelhado (para preview; o backend manda).

### 4.5 create_order — branch `errand` (ADITIVO)
- `supabase/migrations/20260504050000_create_order_wallet_negative.sql` → **nova migration** que recria `create_order`: adicionar `'errand'` ao allowlist (linha ~85); ramo que lê os inputs errand, calcula via `pricing_calculate`, define `payment_buffer_total = fees_total + round(estimated×1.2)` quando compra adiantada por cartão/MBWay. Respeita `enforce_financial_immutability`.

### 4.6 finalize_errand (compra + talão)
- **NOVA** migration RPC `finalize_errand_purchase` (clone do padrão `finalize_storeshopping_purchase_v2`): grava talão em `order_receipts_v2`, escreve `final_purchase_value`/`final_total` via GUC bypass, define `reimbursement_status` (`pending_admin` cartão/MBWay; `cash_settled` cash/paragem-dinheiro), dispara `charge-extra` se talão>buffer, e `parse-receipt`/`ocr-receipt` (Bloco 3).

### 4.7 Tokens — excepção errand
- **NOVA** migration: alterar `fn_award_tokens_on_delivery` → `IF NEW.service_type <> 'errand'` para o award do cliente (0 tokens); estafeta +40 (Decisão D3).

### 4.8 Cancelamento
- Reutiliza `wallet_debit_cancel_fee` + settings `cancel_fee_*` (antes aceitar = reembolso total; após aceitar = €2,50; após compra = paga tudo). Sem código novo de fee — só garantir que o fluxo errand chama o existente. Verificar `cancel_order`/`client_cancel_order`.

### 4.9 UI Cliente — wizard 3 passos + rodapé sticky live
- **NOVO** `lib/screens/errand_form_screen.dart` (padrão de `send_package_form_screen.dart`): Passo 1 O quê (descrição ≤500 + toggle compra + estimativa); Passo 2 Onde (local favor autocomplete → entrega → toggle paragem casa +€2 c/ motivo; estimativa>€40 força ON); Passo 3 Quando+pagar (cards Normal €6 / Expresso €10 → resumo linha-a-linha → checkout). Rodapé sticky com `quote_order`.
- `lib/screens/client_home_screen.dart` + `lib/theme/app_colors.dart` — tile "Favores" na home (skill `add-home-category`, auditar regra 1-laranja).
- Histórico: botão "Pedir de novo" (pré-preenche). Ficheiro de histórico cliente (lista de pedidos).

### 4.10 Tracking cliente (textos próprios)
- `lib/screens/order_tracking_screen.dart` — textos errand: "Estafeta a caminho da tua casa" → "Estafeta a tratar do teu favor" → "A caminho da entrega". NUNCA textos de restaurante.

### 4.11 Estafeta
- `lib/models/driver_model.dart:71-88` — `supportsService`: mota + carro aceitam `errand`.
- `lib/dispatch/driver_capacity_service.dart` — `errand` não-batchable (como logística; estafeta livre).
- `lib/screens/driver_home_screen.dart:~364 _showNewOrderDialog` — badge **FAVOR** + **EXPRESSO**, descrição completa, sequência de paragens, ganho discriminado (€5/€8 + paragem + km).
- Fluxo de execução: confirmar recolha (receita/cartão/dinheiro; se dinheiro registar `errand_home_stop_cash_cents`) → foto talão + valor (bloqueante, reusa `mandatory_photo_picker.dart` + `receipt_upload_service.dart`) → entrega mostra **valor a cobrar** / **troco a devolver** / "nada a cobrar".

### 4.12 Chat
- Verificar `chat_bubble_button.dart` (cliente, em tracking) e `driver_chat_fab.dart` (estafeta) aparecem em pedidos `errand`. Modelo `senderType` e `chat_mark_read` já genéricos. Confirmar push `notify-chat-message`.

### 4.13 Dispatch / Expresso
- `dispatch-engine` aceita `errand` via `supportsService`. **Expresso = sem priorização real no engine** → implementar só como flag/badge + SLA informativo (timer admin). Priorização real = **fora de scope v1** (reportado, não inventado).

### 4.14 Push (PT-PT)
- Reutiliza `notify-driver`/`notify-partner` + textos: aceite / a caminho da tua casa / favor em curso / compra finalizada—total atualizado / a caminho da entrega / entregue.

---

## 5. BLOCO 3 — Gemini lê o talão (ESTENDER `ocr-receipt`) — Decisão D1-A

**Ficheiros a tocar:**
- `supabase/functions/ocr-receipt/index.ts` — subir para `gemini-2.5-flash` (cuidado thinkingBudget/`responseMimeType:application/json` + prompt apertado, como `robot-b/index.ts`); extrair `{store, total_cents, lines:[{name,qty,unit_price_cents}], datetime}`; gravar campos novos.
- **NOVA** migration ADITIVA em `orders` (ou `order_receipts_v2`): `receipt_parsed jsonb`, `receipt_parsed_total_cents int`, `receipt_match boolean`, `receipt_parsed_store text`. (Manter `ocr_*` para retrocompat.)
- **Divergência:** `|digitado − parsed| > receipt_divergence_alert_cents (100)` → `receipt_match=false` + alerta admin (NÃO bloqueia).
- `lib/screens/admin/admin_receipts_screen.dart` (PT-BR) — mostrar foto + dados Gemini (loja/total/produtos) + badge ✓/⚠ + filtro "divergências".
- Settings `receipt_ocr_enabled` (kill-switch) e `receipt_divergence_alert_cents`.
- **Segurança:** bucket `receipts` privado; função lê via service role; nunca URLs públicos. (Inalterado.)
- **Regra de ouro:** valor digitado = fonte de verdade; Gemini nunca bloqueia o estafeta.

---

## 6. BLOCO 4 — Catálogo automático "Lojas de Favores"

**Ficheiros a tocar:**
- **NOVA** migration: tabela `errand_catalog_queue` (`id, product_name, price_cents, store_name, source_order_id, status default 'pending', normalized_name, category, created_at`) + **RLS** (cliente só o seu/nada; admin tudo; estafeta nada). RPCs admin com `_admin_op_guard()` + `log_admin_action()`: `admin_list_errand_queue`, `admin_approve_errand_item`, `admin_reject_errand_item`, `admin_edit_errand_item`.
- `finalize_errand_purchase` (§4.6) — quando há compra + talão parseado, enfileira linhas em `errand_catalog_queue` (gated por `errand_catalog_queue_enabled`).
- **NOVO** `lib/screens/admin/admin_errand_catalog_screen.dart` (PT-BR) — fila pendente: aprovar (1 clique) / editar nome+preço+categoria / rejeitar / lote. Registar em `admin_dashboard_screen.dart` (rota + badge contador).
- Aprovação cria/usa loja **non-partner** (`restaurants`, `is_partner=false`, `category` adequada, **`is_online=false`** = oculta até admin activar) — replica padrão Wells/Worten. Produtos → `products` com `source='errand_auto'` (confirmar/adicionar coluna `source`), `price` (EUR, converter de cents), placeholder de foto, dedup por `search_normalized` (actualiza preço se talão mais recente). Categoria default "Geral" editável.
- **Loja visível + outros encomendam** = storeShopping não-parceiro NORMAL (base+15% `non_partner_markup_pct`, fee €2,50). O 1:1 sem markup é SÓ dentro do favor.
- NÃO tocar catálogos existentes (Continente/Wells…). Tudo em `admin_audit_log`.

---

## 7. business_rules.md — nova secção §55
Adicionar **§55 — FAVORES (ERRAND)** (última secção actual = §54): tabela de preços, split, distância (soma de segmentos), regras de compra/adiantamento/talão, medicamentos com receita (permitido c/ paragem), pagamentos (matriz cartão/MBWay/dinheiro × compra × paragem), cancelamento, tokens (cliente 0 / estafeta 40), OCR divergência, catálogo automático. (Regra 10 do prompt.)

---

## 8. ORDEM DE IMPLEMENTAÇÃO (fases) — após aprovação
1. **DB base:** migration campos `orders` + `errand_catalog_queue` + settings + RLS. → `flutter analyze` n/a; validar SQL.
2. **Pricing+create_order+quote:** branch errand SQL + `quote_order` + espelho Dart + finalize_errand + tokens excepção. → testes A/B/C via SQL.
3. **UI Cliente:** enum, OrderModel, errand_form (wizard+rodapé), home tile, tracking textos, histórico "pedir de novo".
4. **UI Estafeta:** supportsService, capacity, offer badges, fluxo recolha/talão/entrega.
5. **Bloco 1:** rodapé live carry/send via quote.
6. **Bloco 3:** estender ocr-receipt + campos parsed + admin receipts.
7. **Bloco 4:** queue→admin screen→aprovação→loja/produtos.
8. **business_rules §55** + `/ctx doctor` + `/ctx stats`.

Cada fase que toca Pagamentos/DB/Segurança dispara o **Validation Gate** do CLAUDE.md antes de executar.

---

## 9. ZONAS PROTEGIDAS (não alterar comportamento existente)
Dispatch core, `pricing_calculate` branches existentes, triggers financeiros, tokens (só excepção aditiva), Stripe/`charge-extra`/`create-payment-intent`, catálogos de mercado existentes, fotos de produtos reais. Tudo errand é **aditivo** (novos branches/valores).

## 10. FORA DE SCOPE v1 (anotado, não implementar)
Multi-paragens, agendamento futuro, refund automático por SLA, aprovação formal de substituições (resolve-se por chat), fotos automáticas de produtos, publicação automática de loja sem admin, priorização real de Expresso no dispatch.

## 11. BUGS / OBSERVAÇÕES FORA DO SCOPE (reporte)
- **B-OCR-MODELO:** `ocr-receipt` usa `gemini-1.5-flash`; resto do sistema usa `gemini-2.5-flash`. Inconsistência (resolvida se aprovares D1-A).
- **B-TOKENS-DOC:** memória/docs dizem estafeta "+40/+50 (partner)", mas o código (`bora_tokens.sql:143`) dá **40 fixo** sempre. Doc vs código divergem.
- **B-TOKENS-PEQUENO:** cliente `ROUND(price×0.03)` com floor 1 → quase todos os pedidos < €16,67 dão só 1 token (já validado 2026-05-04; não é regressão, mas a comunicação "3%" engana).
- Confirmar existência da coluna `products.source` (assumida para `source='errand_auto'`).
