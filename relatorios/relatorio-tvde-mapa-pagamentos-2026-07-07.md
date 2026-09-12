# TVDE — mapa heading-up + paridade de pagamento — 2026-07-07

Branch: `autonomous-night-2026-04-29` · Partes 1-4 IMPLEMENTADAS · Parte 5 = **PLANO (não aplicado)**.
Zonas protegidas intactas (dispatch, pricing_service, finalizePurchase, tokens, Stripe webhook, RLS).

## Resumo

| Parte | Estado | O quê |
|---|---|---|
| 1 — Mapa roda de verdade (heading-up) | ✅ Implementado (falta ver no CI) | Câmara segue o motorista e RODA com a direção, contínuo (Waze) |
| 2 — Motorista vê método + matemática | ✅ Implementado | Badge 💵 Dinheiro + "cobrar €X" + breakdown no histórico |
| 3 — Ida-e-volta em dinheiro | 📋 Só plano (mexe em liquidação) | Sem spec no repo → desenho na Parte 5, NÃO inventado |
| 4 — Auditoria dos 3 métodos | ✅ Feito + 1 fix | Delivery/mercados/favores com paridade total; fix na Limpeza |
| 5 — Card + MB Way no TVDE | 📋 Plano + SQL proposto | `relatorios/proposta-tvde-card-mbway.sql` (NÃO aplicado) |

---

## PARTE 1 — 🔴 Mapa heading-up contínuo (Waze)

**Causa do `26ab3da` não ter resolvido:** o fix anterior tocou o ecrã do **cliente**
(`tvde_ride_tracking_screen`) e a rotação do **marcador** (a seta), mas no ecrã do **motorista a
navegar** (`tvde_ride_active_screen` — o principal, "pro motorista seguir o mapa") a **câmara nunca
seguia**: `_recenter` (botão mira) aplicava zoom+tilt mas **sem bearing**, e só quando o motorista
carregava na mira. Resultado: 3D/tilt OK, mas o **norte fixo** — o mapa não rodava ao virar.

**Fix (ecrã do motorista, `tvde_ride_active_screen.dart`):**
- **Follow contínuo:** a cada posição GPS nova, a câmara anima para
  `CameraPosition(target: carro, zoom: 17.5, tilt: 45, bearing: _bearing)` → o mapa **RODA** com a
  direção de marcha, continuamente (não uma vez só).
- **Bearing fiável só em movimento:** atualiza quando andou **≥ 5 m** (`Geolocator.bearingBetween`
  de posições cruas); parado mantém o último — **não gira à toa**. Movimento pequeno (≥1 m) segue a
  posição sem mexer na rotação.
- **Gesto pausa, mira religa:** arrastar o mapa desativa o follow (`onCameraMoveStarted` com a flag
  `_progCamMove` a distinguir gesto de animação nossa); o botão mira volta a ligar e recentra com
  bearing. `onCameraIdle` repõe a flag.
- A seta do motorista é `flat: true` com `rotation: _bearing` → com a câmara já rodada, aponta
  sempre para cima (correto, sem duplo-giro).

**Ecrã do cliente** (`tvde_ride_tracking_screen`): já fazia follow contínuo com o mesmo padrão
(threshold 5 m + `_followDriver` a cada poll) desde o `0e39a71` — **confirmado, nada a mudar**.

⚠️ **Verificação no device:** o Redmi tem a **build 370** (anterior a estas mudanças) e a build
local dá **OOM** (4 GB) → **não é possível provar a rotação a conduzir esta sessão**. A lógica é o
port direto do padrão já comprovado no ecrã do cliente. Ver no mapa a rodar fica para a **próxima
build do CI** (mock location / conduzir).

---

## PARTE 2 — 🔴 Motorista vê o método + a matemática

Novo widget partilhado **`lib/widgets/tvde/tvde_pay_badge.dart`** (`TvdePayBadge`), espelhando o
padrão do estafeta do delivery ("COBRAR EM DINHEIRO: €X"):

- **Oferta** (`tvde_offer_screen`): badge **💵 Dinheiro** por baixo do ganho — o motorista vê o
  método antes de aceitar.
- **Corrida ativa** (`tvde_ride_active_screen`): badge **"Dinheiro · cobrar €X ao passageiro"**
  (`final_fare_cents` depois do finish; `est_fare_cents` com "~" antes). Corrida **coberta pelo
  plano** → **"Coberta pelo plano — NÃO cobrar o passageiro"**.
- **Histórico** (`tvde_driver_earnings_screen`): breakdown por corrida —
  **"Cobrado €X · Bora €Y"** + o **€ganho** dele à direita (coberta → "Coberta pelo plano ·
  dinheiro"). `bora_cut = gross − driver_earn` (o modelo não traz `bora_cut_cents`; calcula-se).

*(Nota: o antigo [Item C] escondia o total do cliente ao motorista. O teu pedido explícito da
Parte 2 inverte isso — agora o motorista TEM de ver quanto cobrar. Feito.)*

---

## PARTE 3 — 🟡 Ida-e-volta em dinheiro → PLANO (não implementado)

**Não encontrei spec** de "cash ida-e-volta / vale-volta dinheiro" no repo nem no vault. O fluxo
atual (`_solicitarRoundtrip`) **paga €8 via Stripe cartão** (`createRoundtripPayment` →
`PaymentService.processPayment` → `requestRide` → `activateRoundtrip(id, paymentIntentId)`). Fazer
a versão **dinheiro** obriga a mexer na **liquidação** (o `activateRoundtrip` exige um
`paymentIntentId` Stripe; em cash o motorista cobraria ida+volta e isso entra no
`tvde_driver_balances`) → **é dinheiro real = LISTA VERMELHA = PROPOSE-ONLY**.

Conforme a regra ("não inventar"), **não implementei** e **não deixei um toggle cash meio-ligado**
(seria um bug de dinheiro). O desenho vai na Parte 5. Recomendação: implementar **junto** com o
backend aprovado — cash = motorista cobra ida+volta na ida; vale expira em 6 h como o pré-pago.

---

## PARTE 4 — 🔍 Auditoria dos 3 métodos (× o que o executor vê)

| Vertical | Backend | Métodos no checkout | Executor vê (cash → "cobrar €X"?) |
|---|---|---|---|
| Delivery parceiro | cash/card/mbway | Cartão·MBWay·Dinheiro | Estafeta: **"COBRAR EM DINHEIRO: €X"** ✅ · Parceiro: "Receber €X na loja" ✅ |
| Delivery não-parceiro | cash/card/mbway | Cartão·MBWay·Dinheiro | Estafeta: "COBRAR EM DINHEIRO: €X" ✅ |
| Mercados | cash/card/mbway | Cartão·MBWay·Dinheiro | Estafeta: "COBRAR EM DINHEIRO: €X" ✅ |
| Favores | cash/card/mbway | Cartão·MBWay·Dinheiro | Estafeta: "Cobrar €X" + input "Dinheiro recebido" ✅ |
| Reservas de mesa | card/mbway (cash excluído **por design**) | Cartão·MBWay | Pré-pago; parceiro só marca chegada ✅ (n/a) |
| Serviços/barbearia | card/mbway (pré-pago €3) | Cartão·MBWay | Pré-pago; sem cash ✅ (n/a) |
| **Limpeza** | cash + card/mbway (atrás de flag) | Dinheiro·Cartão·MBWay | Cleaner **NÃO via o total a cobrar** → **CORRIGIDO** (ver abaixo) |
| **TVDE corrida** | **só cash** | (sem seletor) "dinheiro ao motorista" | Motorista agora vê "cobrar €X" (Parte 2). Card/MBWay = Parte 5 |
| **TVDE ida-e-volta** | vale €8 = card/mbway; corridas = cash | Cartão/MBWay (só o vale) | Igual TVDE. Cash da volta = Parte 3/5 |

**Conclusão:** delivery/mercados/favores têm **paridade total** dos 3 métodos no cliente E o padrão
"COBRAR €X" no executor — nada escondido. Reservas/serviços são cash-excluídos **por design**.

**Fix aplicado (UI-only) — Limpeza:** o profissional de limpeza numa marcação **cash** cobra o
total na hora mas o cartão da agenda só mostrava o **ganho** dele. Acrescentei
**"COBRAR EM DINHEIRO: €X"** (`b.totalCents`) em `cleaner_home_screen.dart`, laranja/negrito, igual
ao estafeta. Sem lógica nova.

**Gaps de backend (para o plano):** (1) corrida TVDE = só cash → Parte 5; (2) Limpeza card/MBWay
depende da flag `stripeEnabled`/`platform_settings` — confirmar se está ligada em produção (o teu
"vai 2026-07-05" sugere que sim; validar via MCP).

---

## PARTE 5 — 📋 PLANO (NÃO IMPLEMENTAR): Card + MB Way nas corridas TVDE

⚠️ **Mexe em Stripe + liquidação → LISTA VERMELHA. Nada aplicado. Espera "vai".**
SQL proposto (comentado, com DROP+CREATE p/ evitar overload): **`relatorios/proposta-tvde-card-mbway.sql`**.

**1. Fluxo de cobrança (estilo Uber).**
- **Cartão:** no pedido, **autoriza** (PaymentIntent `capture_method='manual'`, montante = tarifa
  estimada). No finish, **captura** o valor final: `final < auth` → captura parcial; `final > auth`
  → captura o auth + PI extra (padrão `charge-extra`). Guarda `payment_intent_id`/`payment_status`.
- **MB Way:** não tem auth/capture. **Cobrar o estimado no PEDIDO** (como o vale-volta já faz) e
  acertar a diferença no finish (refund do excesso / charge-extra se subiu). Cobrar só no fim
  arrisca o cliente não aprovar o push MB WAY no destino → corrida por pagar (inaceitável).

**2. Liquidação INVERTIDA em `tvde_driver_balances` (sinal em EUR).**
- `> 0` = **motorista deve à Bora** (cash: recebeu tudo, deve o corte). `< 0` = **Bora deve ao
  motorista** (card/mbway: Bora recebeu online, deve o earn). `= 0` = quites. Cash e card do mesmo
  motorista fazem **netting** na mesma coluna. No finish, `v_settle` ganha sinal: cash `+bora_cut`;
  card/mbway `−driver_earn`. **Payout admin:** saldo negativo → transferir |saldo| ao motorista;
  positivo → cobrar (fluxo de dívida atual).

**3. Cancelamento/no-show com cartão.** Ligar a `tvde_cancel_ride` (já calcula `cancel_fee_cents`,
incl. os **€3.50** da corrida coberta cancelada tarde). Taxa = 0 → `void` da autorização; taxa > 0
→ **captura parcial** (cartão) ou **refund parcial** (MB Way). A decisão vive na Edge Function nova,
lendo `cancel_fee_cents` — **sem** tocar `tvde_cancel_ride`.

**4. Admin.** Expor `payment_method` (+ `payment_status`) na listagem de corridas; relatório de
liquidação **por método**: cash (a receber dos motoristas) vs card/mbway (a pagar) + `bora_cut`
como receita. Paridade → convocar o agente `admin`.

**5. Ida-e-volta em dinheiro (Parte 3).** Cash = motorista cobra **ida + volta** juntos na ida;
vale expira em **6 h** como o pré-pago. `activateRoundtrip` ganha um ramo cash (sem `paymentIntentId`),
e o valor do pacote entra no balance do motorista como dívida (mesma semântica do ponto 2).

**6. Estimativa + riscos.** RPCs ~2 h · Edge Function `tvde-ride-payment` (authorize/capture/charge/
void/refund) ~6-8 h · UI cliente (escolher método) + estafeta/admin ~4-6 h · testes ~3 h →
**~15-19 h**. Riscos: captura parcial e `final>auth`; MB Way sem capture (idempotência de
refund/charge-extra); netting cash+card num só saldo (o relatório admin tem de separar por método);
NÃO tocar webhook/`create-payment-intent`/`pricing_service`/`bora_tokens`.

---

## Validação

- **`flutter analyze`** nos 6 ficheiros alterados: **0 erros, 0 warnings**. Restam só `info`
  (prefer_const) — os que introduzi foram postos `const`; os restantes são pré-existentes nesses
  ficheiros (baseline do projeto).
- Verificação **visual/on-device** (mapa a rodar; badges no motorista) → **próxima build do CI**
  (device na 370, build local OOM).

## Ficheiros

**Implementado:** `tvde_ride_active_screen.dart` (mapa + badge), `tvde_offer_screen.dart` (badge),
`tvde_driver_earnings_screen.dart` (breakdown), `widgets/tvde/tvde_pay_badge.dart` (novo),
`cleaner_home_screen.dart` (Limpeza: cobrar €X). **Proposta (não aplicada):**
`relatorios/proposta-tvde-card-mbway.sql`.

## Admin — aviso

A listagem admin de corridas mostra `final_fare ?? est_fare`; **confirmar via MCP se a RPC admin
devolve `payment_method`** (hoje todas cash, mas ao ligar card/mbway o admin precisa do campo).
Se não devolver → ajustar a RPC/consulta (o Danilo faz via MCP).
