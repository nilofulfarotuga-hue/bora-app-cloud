# Sessão Lançamento 2026-06-11 — B1/B2/B4/B3 (bugs confirmados no build 278)

> Branch `autonomous-night-2026-04-29` · 4 commits (1 por bug) · flutter analyze 0 errors
> Knowledge: CEO-AI + BORA_DNA + business_rules lidos no arranque. FSI/overlay NÃO tocados.

---

## B1 — CRÍTICO FINANCEIRO: preço exibido ≠ preço cobrado (não-parceiro) ✅

### Causa-raiz
Em **2026-05-21** o `CartStore.addItem` deixou de aplicar o markup de exibição, com base
numa conclusão **errada** ("preços na DB já incluem o markup" — caso Água Auchan €0,28
site vs €0,32 DB). O pedido real 80ba3a2e provou o contrário: a DB tem o preço **BASE**
do site oficial (cnt-4603911 = €1,55) e o backend cobra base×1,15. Só o
`restaurant_menu_screen` aplicava ×1,15 por conta própria — por isso "funcionava nalgum
ponto". Mercados, detalhe do produto, busca e sugestões mostravam o preço base.

### Como o servidor cobra (verificado na função real `create_order`)
- Faz **lookup do preço em `products` por product_id** (ignora o preço enviado);
  `unit_price` do payload é só fallback quando o id não existe (ex. variantes).
- Não-parceiro: `subtotal = ROUND(SUM(base×qty) × 1.15, 2)` — markup na SOMA,
  arredondado UMA vez no fim.
- `orders.items` é gravado **tal e qual** o payload do Flutter.

### Fix (10 ficheiros, commit `e1c48ea`)
1. **`PricingService.applyMarkup`** = fonte única do preço exibido/cobrado — agora **sem
   arredondar por unidade** (round unitário divergia ±1 cêntimo com qty>1; ex. 4×€0,28:
   server €6,39 vs round unitário €6,38).
2. **`CartItem.basePrice`** (novo): `price` = exibido/cobrado (com markup) → vai para
   `orders.items` (histórico bate com o Stripe — missão 4 ✓); `basePrice` = puro →
   vai em `product_lines.unit_price` (evita **duplo markup** no fallback das variantes).
3. Markup aplicado em **todos os call sites**: market_product_card, store_products_screen
   (tile, card, variantes, sugestões), product_detail_screen (novo param obrigatório
   `isPartnerStore` — 8 callers atualizados), restaurant_menu_screen (2 adds manuais
   unificados no helper + caminho legacy que não tinha markup + busca).
4. **Linha "Saco para viagem"**: `calculateBreakdown` espelha o servidor (restaurant
   €0,30; storeShopping €0,10×max(1, sacos) — o checkout cobra sempre 1 à cabeça);
   linha adicionada ao payment_method_screen (cart_screen já tinha mas nunca aparecia
   para mercados porque o breakdown devolvia 0).
5. `createOrder` preservava `selectedOptions` só no fluxo cartão — o clone cash/MBWay
   descartava-as de `orders.items`; corrigido (+`basePrice`).
6. Reorder: pedidos de mercado antigos (price=base) reaplicam o markup ao recarregar.

### PROVA (pricing_calculate REAL vs breakdown Flutter pós-fix) — ao cêntimo
| Caso | Server | Flutter pós-fix |
|---|---|---|
| Pedido real: 1×€1,55 mercado, 1km, 1 saco | 1,78+2,50+2,50+0,10 = **6,88** | **6,88** ✓ (antes: 6,55) |
| 4×€0,28 (qty>1, arredondamento) | subtotal 1,29 → **6,39** | **6,39** ✓ |
| Restaurante não-parceiro 1×€6,50 | 7,48+2,50+2,50+0,30 = **12,78** | **12,78** ✓ |
| **Parceiro** €10,00 (auditoria 10+5+5) | 10+0,50+2,50+0,30 = **13,30**, markup oculto 0,50 só settlement | **13,30** ✓ |

**Auditoria parceiro (missão 3):** exibido = cobrado ✓. O cliente paga preço de menu puro
+ 5% serviço + entrega + saco; os 10% comissão e 5% markup oculto são settlement
(colunas próprias), nunca somados ao total do cliente. **Percentagens intocadas.**

### ⚠️ Divergências REPORTADAS (não mexi — dinheiro é sagrado, decisão do Danilo)
1. **Opções pagas (price_add) NÃO são cobradas pelo servidor**: o `create_order` soma só
   `products.price`; um açaí com toppings +€1 mostra o valor com toppings mas cobra sem
   eles (perda de receita Bora em fast-food com opções — McD/BK/KFC/Açaí). Fix = somar
   `selected_options`/price_add no loop do create_order (migration pequena; posso
   preparar quando autorizares).
2. **Promoções não honradas**: 14 produtos Lidl com `is_on_sale`+`discount_price`, mas o
   servidor cobra `price` cheio. O card mostrava o desconto riscado e cobrava o cheio
   (enganoso) → o card passou a mostrar o preço cobrado. Decidir: (a) servidor honra
   discount_price, ou (b) desligar is_on_sale no scraper Lidl.
3. **Bag fee parceiro**: o servidor cobra €0,30 (restaurant) e €0,10×sacos
   (storeShopping) também a parceiros — business_rules §2.5 diz "parceiro absorve".
   Display Flutter espelha o servidor (consistente entre si); docs a reconciliar.
4. `quote_order_pricing` no checkout (usado só para dívida wallet) recebe cartInput sem
   `product_lines`/`subtotal` → calcula fees sobre 0. Inofensivo hoje (só
   `debt_settle_cents` é consumido); a corrigir se alguém for usar o resto do quote.

### BÓNUS (missão 5) — duplicados e nomes HTML, quantificados
- Prefixos: **1.317 `cnt-`** vs **10.950 `cont-`**; **383 pares duplicados** com o MESMO
  código Continente (cnt-4603911 + cont-4603911) — padrão sistémico de 2 gerações de
  crawler. Proposta: skill `dedupe-market-products` (soft-delete is_available=false do
  par mais pobre, backup CSV antes) — **nada apagado nesta sessão**.
- **681 nomes com entidades HTML** (&Oacute; etc.) — proposta: UPDATE com decode
  (xml entities) em lote único com backup; posso preparar o script para aprovação.

---

## B2 — Agenda parceiro Serviços + push marcação ✅ (commit `ee70325`)

### Causa-raiz 1 — "Não foi possível carregar a agenda"
`AppointmentModel.fromSupabase` fazia `row['service_id'] as String` (**cast
não-nullable**), mas slots de **"Bloquear horário"** gravam `service_id = NULL` →
TypeError no parse → catch genérico. Rebentou hoje às 13:49 quando bloqueaste um
horário (a linha blocked entrou na vista Hoje). RLS estava OK — o SELECT direto via
MCP funcionava porque o erro era de **desserialização Flutter**, não de query/policy/join.
Fix: `serviceId` nullable (não é usado fora do modelo).

### Causa-raiz 2 — sem push ao barbeiro
O pipeline server está **completo** (cartão E MBWay → `client_confirm_appointment_payment`
→ `_appt_notify_partner` → in-app + Edge `notify-service-provider` FCM multi-device),
MAS `partner_push_tokens` tinha **0 tokens** do user da barbearia — e 1 token (0 ativos)
em TODA a produção:
- `PushTokenService.registerForRole` **rejeitava o role 'partner'** no guard client-side
  (o RPC `register_push_token` sempre o suportou);
- o parceiro só-serviços nunca chamava registo de token (o `saveTokenForPartner` exige
  restaurantId e só corre no fluxo restaurante).

Fix: guard aceita 'partner' + novo `savePushTokenForServicePartner()` (consent-gated) +
registo defensivo no initState do hub Marcações. Bónus: restaurantes passam a registar
multi-device também.

### Agenda UX
A tua marcação real (**18/06 09:30, Tiago, Corte de Cabelo, sinal pago**) ficava fora da
vista Semana (hoje+6d) sem forma de a ver → novo segmento **Mês** (30 dias) e as vistas
Semana/Mês mostram **dd/MM** além da hora.

### Teste do resto do menu (user real 7be9bec8 via MCP)
| Item | Estado | Evidência |
|---|---|---|
| Adicionar marcação | ✅ | walk-in criado por ti hoje 13:50 em produção |
| Bloquear horário | ✅ | slot blocked 13:49 (foi ele que revelou o bug do parse) |
| Serviços | ✅ | 7 serviços, policy `true`, modelo defensivo |
| Barbeiros | ✅ | 2 barbeiros (Tiago + …), idem |
| Financeiro | ✅ | grants ok no RPC semanal; 0 payouts = lista vazia legítima |

---

## B4 — Headers brancos: diagnóstico REAL + fix em 33 ecrãs ✅

### Causa-raiz (provada com teste de pixels — Flutter 3.41.2, local = CI)
O padrão `AppBar(backgroundColor: Colors.transparent, flexibleSpace: const
DecoratedBox(gradient))` **não pinta o gradiente** no Flutter 3.41: `DecoratedBox` sem
child colapsa para tamanho zero com as constraints loose que o AppBar dá ao
flexibleSpace. Resultado: header transparente → título/ícones brancos sobre o fundo
claro do Scaffold (#F0F2EF).

**PROVA** (`test/appbar_paint_probe_test.dart`, leitura de pixels da toolbar):
- ANTES: pixels = **#F0F2EF** (fundo claro) — em AMBOS os padrões (BoraScreenAppBar e inline)
- DEPOIS: pixels = **#16A34A** (verde Bora) — **All tests passed**

A sessão anterior ("só 1 divergente") falhou porque procurou diferenças ENTRE ecrãs —
mas era o padrão PARTILHADO que estava partido: **todos os 33 sites estavam ilegíveis**,
não só os 3 reportados ("Marcações", "Agenda" e "Sugestões do Robot" usam todos
`BoraScreenAppBar`).

### Fix estrutural
`backgroundColor: AppColors.primary` (sólido) em todos — visualmente IGUAL ao
headerGradient (que é `[primary, primary]`) e o header **nunca mais pode ficar claro**:
- `BoraScreenAppBar` (+ `surfaceTintColor: transparent`, `scrolledUnderElevation: 0`)
  → cobre Marcações, Agenda, Sugestões do Robot e ~15 ecrãs admin
- 30 AppBars inline: client_home, driver_home, login, partner_login, register_*,
  restaurant_menu (2), restaurant_dashboard (2), partner_dashboard,
  partner_call_driver, support_chat, welcome_address, client_reservations,
  my_reservation_lists, partner/reservations (3), add_product, admin_* (13)

---

## B3 — Fotos dos produtos para o estafeta ✅

- Thumbnail 44×44 por item na lista de compra (driver_map_screen), carregada com
  **1 query** `products.select(id, photo_url)` ao abrir o sheet — funciona para pedidos
  antigos e novos, zero mudança de modelo/checkout.
- Tap → fullscreen preto com **InteractiveViewer** (pinch-zoom 5×) + nome + fechar.
- **Resposta à tua dúvida: o Supabase aguenta tranquilo** — são as URLs já existentes do
  catálogo (CDN), zero custo extra de storage; só leitura de uma coluna já pública.
- Botões ✅ Comprado / ❌ Não há / ➕ adicionar produto intactos.

---

## CHECKLIST DE TESTES PARA O DANILO (build seguinte, ≥279)

**B1 (mercado — repete o pedido Continente):**
1. Abre o Continente → produto Óleo Gesi cnt-4603911: card mostra **€1,78** (não 1,55).
2. Adiciona ao carrinho → linha mostra €1,78; Subtotal **€1,78**.
3. Resumo de pagamento: Subtotal 1,78 + Taxas 2,50 + Entrega 2,50 + **Saco para viagem
   0,10** = **Total 6,88** = Stripe ao cêntimo (cartão pré-autoriza 6,88×1,15=7,91 e
   captura 6,88).
4. Restaurante parceiro: preços do menu inalterados; taxa 5% + entrega como antes.
5. Histórico do pedido novo: preço do item = o que pagaste (não o preço base).

**B2 (barbearia):**
1. Login barbearia.nobre → Marcações → **Agenda**: carrega SEM erro; vista Hoje mostra
   o walk-in "Faltou" + o "Bloqueado" de hoje; vista **Mês** mostra a marcação
   **18/06 · 09:30 Danilo (Confirmada)**.
2. Abre o hub Marcações 1× (regista o token) → faz nova marcação de teste como cliente
   e paga o sinal → o telemóvel do parceiro recebe **push "Nova marcação"**.

**B4 (headers):**
1. Marcações, Agenda e admin → Sugestões do Robot: título BRANCO sobre **VERDE** ✓.
2. Spot-check: login, registo, home cliente, home estafeta, detalhe pedido admin.

**B3 (estafeta):**
1. Pedido de mercado → como estafeta abre a lista de compra: cada item tem foto;
   tap na foto amplia com zoom; ✅/❌/➕ funcionam como antes.

## Pendentes que ficaram para ti (decisões)
1. Aprovar fix server das **opções pagas** (create_order não as cobra) — preparo a migration.
2. Promoções Lidl: honrar discount_price no server OU desligar is_on_sale.
3. Dedupe 383 pares cnt-/cont- + decode de 681 nomes HTML (proposta pronta, nada apagado).
4. Bag fee de parceiro: server cobra, business_rules diz que absorve — reconciliar docs/regra.
