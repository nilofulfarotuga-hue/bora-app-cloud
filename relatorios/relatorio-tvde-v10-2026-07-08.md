# TVDE v10 — mapa leve · pagamento = delivery · regras do plano · auditoria — 2026-07-08

Branch `autonomous-night-2026-04-29`. 7 frentes. Kill switch `tvde_card_payments_enabled` = **ON**
(não desliguei). RPCs TVDE e zonas protegidas intactas. App PT-PT.

---

## 1) 🔴 Performance do mapa do motorista — MAIS LEVE
Ficheiro: `lib/screens/driver/tvde/tvde_ride_active_screen.dart`.

**O que pesava:**
- `animateCamera` a CADA tick de GPS, **sem throttle** — o `DriverStore` interpola a posição em
  passos (`Timer.periodic` + `notifyListeners`), o ecrã fazia rebuild várias ×/seg e cada rebuild
  disparava uma nova `animateCamera`. Fila de animações de câmara = a "trava".
- `Set<Marker>` **recriado em cada `build()`** — alocação nova + diff de marcadores empurrado ao
  canal nativo mesmo quando o rebuild era por outra coisa (badge de chat, `busy`…).
- Saltos de câmara instantâneos (sem duração curta).

**O que mudei:**
- **Throttle** da câmara: só reposiciona se o motorista andou **≥15 m** OU passou **≥1 s** desde o
  último movimento (de várias/seg → ~1/seg). Campos `_lastCamMove`/`_lastCamTarget`.
- **Glide suave**: `animateCamera(..., duration: 400ms)` (mantém animação, não salto).
- **Set de marcadores reutilizado**: cacheado por assinatura barata (fase/alvo/pos~1m/bearing°) →
  mesma identidade quando o rebuild não é de movimento → sem churn de alocação/diff.
- `_recenter` regista o estado do throttle (não duplica animação logo a seguir).
- **Preservado** (validado pelo Danilo): matemática do bearing, lógica ≥5 m, flags
  gesto-vs-programático. `flutter analyze` 0 erros (infos pré-existentes).

## 2) 🔴 Autocomplete na "Adicionar parada" — JÁ ESTAVA
Ficheiro: `lib/screens/client/tvde/tvde_ride_tracking_screen.dart`. Verificado: `_addStop` já abre o
`_AddStopSheet` com o **mesmo `AddressAutocompleteField`** corrigido (o do destino) → devolve
lat/lng → `TvdeStore.addStop(ride.id, lat, lng, label)` → RPC `tvde_add_stop`. `p_segment_km=0`
(default; a taxa da parada é flat €2 — não se mexe em preço). Guarda de máx. paradas + SnackBars de
erro presentes. **Analyzer limpo, sem alteração necessária** (landou no commit `16fe7ae`).

## 3) 🔴 Pagamento TVDE = ORDEM do delivery
Ficheiro: `lib/screens/client/tvde/tvde_request_ride_screen.dart`. Antes: o `TvdePaymentSelector`
estava **inline/cedo** no ecrã (métodos sempre à vista). Agora, **igual ao checkout do delivery**
(cart → "Finalizar" → tela de métodos):
- O selector inline **saiu**. Carregar em **"Solicitar corrida"** abre uma **folha de pagamento**
  (`_TvdePaymentSheet`) que mostra o **valor final + os métodos** e só aí se confirma.
- Cash → cria a corrida; Cartão/MB Way → `requestRidePaid` (Edge Function cobra no Stripe e cria a
  ride), reusando o `PaymentService().processPayment` do delivery.
- Corrida **grátis** (coberta ≤6km) **não abre folha** — cria já.

## 4) 🔴 Regras do plano na UI + mensagens (espelha o `tvde_finish_ride`)
Li o `tvde_finish_ride` e as `platform_settings` (base €5 / 6 km / €0,50 km / extra €4,50) e
repliquei a matemática para o cliente ver ANTES (nunca cobrar sem ver). 4 casos:

| Caso | Condição | Cliente paga | Mensagem (PT-PT) | Folha? |
|---|---|---|---|---|
| **Grátis** | coberta & ≤6 km | €0 | "Incluída no teu plano · N.ª de M hoje" | **não** |
| **Excesso** | coberta & >6 km | só km acima de 6 × €0,50 | "Corrida do plano — só pagas o excesso: X km acima de 6 = €Y" | sim (dinheiro) |
| **Extra** | membro sem corridas hoje | €4,50 + excesso | "Já usaste as corridas de hoje — esta fica €Z (preço de membro)" | sim (dinheiro) |
| **Normal** | sem plano (ou fim-de-semana não-membro) | tarifa cheia (`tvde_calculate_fare`) | — | sim (3 métodos) |

O `_EstimateCard` mostra "Grátis" ou "€X" + a linha do porquê. Os valores batem com o backend
(mesmos settings).

**⚠️ Decisão de dinheiro (importante):** para **Excesso** e **Extra**, a folha oferece **só
dinheiro**. Motivo: a Edge Function `tvde-payment` cobra online a **tarifa cheia**
(`tvde_calculate_fare`) — para uma corrida do plano isso seria **mais** do que o devido (excesso/
extra). Em dinheiro o motorista cobra o valor certo (consumido no fim, como o backend já faz). Ver
frente 5 §proposta para pôr 3 métodos também no plano (mexe em dinheiro → aguarda "vai").

## 5) 🔴 Auditoria cruzada — pagamento por vertical

| Vertical | Fluxo = delivery (paga só após botão, tela dedicada)? | 3 métodos? | Valor final ANTES? | Executor vê badge? | Matemática = backend? |
|---|---|---|---|---|---|
| Delivery restaurante | ✅ cart→`PaymentMethodScreen` | ✅ | ✅ PricingService | ✅ CollectBadge | ✅ recalc no `create_order` |
| Mercados | ✅ mesmo caminho | ✅ | ✅ | ✅ | ✅ |
| Favores | ✅ `errand_form`→`PaymentMethodScreen` | ✅ | ✅ quote servidor | ✅ | ✅ |
| Reservas de mesa | ✅ sheet após "Pagar €3" | ⚠️ só card/mbway (pré-pago, por design) | ✅ €3 | N/A | ✅ |
| Serviços/barbearia | ✅ wizard→sheet €3 | ⚠️ só card/mbway (por design) | ✅ €3 | N/A | ✅ |
| Limpeza | ⚠️ método no wizard, depois `CleaningPaymentFlow` | ✅ | ✅ total booking | ✅ CollectBadge | ✅ |
| **TVDE normal** | ✅ **corrigido** (folha após "Solicitar") | ✅ normal / dinheiro no plano | ✅ `_EstimateCard` | ✅ TvdePayBadge | ✅ espelha `tvde_finish_ride` |
| TVDE ida-e-volta | ⚠️ toggle + botão €8 (pré-pago card/mbway) | ❌ pré-pago €8 | ✅ €8 no botão | ✅ coveredByPlan | ✅ fixo |

**Rápidos já feitos:** TVDE normal alinhado ao delivery (frentes 3+4); badge unificado já em
delivery/TVDE/limpeza (sessão anterior). **Refactor grande (não feito, com estimativa):**
- *Tela cheia dedicada p/ TVDE* (mirror do `PaymentMethodScreen`, que está acoplado ao `CartStore`)
  em vez de folha — ~1-2 h. A folha atual resolve a UX; a tela cheia é cosmética.
- *3 métodos no plano (excesso/extra)* — precisa a EF calcular o valor do plano server-side
  (excesso/extra) em vez da tarifa cheia. **Mexe em dinheiro** → proposta abaixo.

## 6) 🔍 Play Console (track fechado + testadores)
Via Play Developer API (SA `boraapp-d2bea`, package `pt.boraapp.bora`):
- **Track `alpha` (fechado): versionCode 387, status `completed`, rollout 100%** (`userFraction`
  null = 100%). O CI está a publicar bem (370→383→…→387).
- **Grupos ligados ao alpha:** `bora-app-testers@googlegroups.com` + `khadem-testers-service@googlegroups.com`.
- **O que a API NÃO dá (ver no Console/Groups):**
  - **Quantos dos 12 (PrimeTestLab, order #P08075612) fizeram opt-in e o progresso 12×14 dias:** a
    API não expõe contagem de opt-in nem o progresso do requisito. Ver: Play Console → **Testes →
    Teste fechado → alpha → Testadores** (mostra nº de opt-in) e a página **"Publicar > Visão geral
    do teste"** (progresso dos 14 dias).
  - **Membros do grupo (ex.: `boraappbora@gmail.com` está no grupo?):** a API só lista o *grupo*
    ligado, não os membros. Ver em `groups.google.com/g/bora-app-testers/members`.
  - ⚠️ **Nota importante:** `boraappbora@gmail.com` é a conta **dona** do Play Console. A conta
    developer, mesmo no grupo, muitas vezes **não recebe** o build como testador (o Play trata-a como
    publicador). Para testar, usar uma conta Google **não-developer** no grupo + link de opt-in.

## 7) ✅ Verificação: o pagamento entra mesmo?
- Kill switch `tvde_card_payments_enabled` = **true** (confirmado na `platform_settings`).
- EF `tvde-payment` **live**: com o switch ON, uma chamada anónima já **passa o gate** (deixou de dar
  `403 card_payments_not_enabled`) e cai no auth → **`401 not_authenticated`**. Prova que o caminho
  card/MB Way está aberto.
- **Passo de validação no Stripe (fazer com o telemóvel):** pedir 1 corrida **NORMAL** com Cartão →
  confirmar no PaymentSheet → ver o PaymentIntent em **Stripe → Payments** (estado `succeeded`, valor
  = tarifa mostrada) + a `tvde_rides` com `payment_intent_id`/`payment_status` + o motorista vê "JÁ
  PAGO NA APP". Repetir com **MB Way** (aprovar o push). **Cash** e **coberta ≤6km** não passam pelo
  Stripe (sem cobrança online). Cancelar uma corrida paga → refund no Stripe.

## ⚠️ PROPOSTA que MEXE EM DINHEIRO (aguarda "vai")
Para pôr **3 métodos** (cartão/MB Way) também nas corridas do **plano** (excesso/extra) sem
sobre-cobrar: a EF `tvde-payment` teria de **calcular o valor do plano server-side** (chamar
`tvde_preview_coverage` + settings, cobrar excesso ou €4,50+excesso em vez da tarifa cheia). Está
tudo mapeado; **não apliquei** porque altera o valor cobrado ao cliente.
**⚠️ ISTO MEXE EM PAGAMENTO. Confirma que eu aplico.**

## Admin
`admin_tvde_rides_list` devolve `payment_method`; o saldo do motorista já lê o sinal (negativo = Bora
deve). **A confirmar (via MCP):** se a lista admin devolve também `payment_status` (pago/refund) —
se não, ajustar a RPC.

## ✅ Checklist de teste (Danilo, Redmi por cabo)
- [ ] Mapa do motorista **leve/fluido** a seguir até ao destino (sem travar).
- [ ] "Adicionar parada" com **autocomplete** → parada entra com morada certa.
- [ ] Coberta ≤6km → **"Incluída no plano ✓"**, sem tela de pagamento, corrida criada.
- [ ] Coberta >6km → **"só pagas o excesso €Y"** → folha (dinheiro) → cria.
- [ ] 3.ª do dia (extra) → **"esta fica €Z (preço de membro)"** → folha (dinheiro).
- [ ] Normal (sem plano) → botão → **folha com Dinheiro/Cartão/MB Way** + valor.
- [ ] Cartão (normal) → PaymentSheet → Stripe `succeeded` + motorista "JÁ PAGO".
- [ ] MB Way (normal) → push aprovado → mesmos checks.
- [ ] Ida-e-volta → €8 mostrado antes → paga → cria.
- [ ] Cancelamento de corrida paga → refund no Stripe.

## Ficheiros alterados
`lib/screens/driver/tvde/tvde_ride_active_screen.dart` (perf), `lib/screens/client/tvde/tvde_request_ride_screen.dart`
(folha de pagamento + regras do plano). `flutter analyze` 0 erros nos ficheiros tocados (infos
pré-existentes). Front 2 sem alteração (já implementado).
