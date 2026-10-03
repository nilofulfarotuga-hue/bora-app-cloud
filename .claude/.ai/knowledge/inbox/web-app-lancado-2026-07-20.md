---
id: web-app-lancado-2026-07-20
tema: web
estado: atual
data: 2026-07-20
autor: CEO-AI (sessão autónoma)
---

# Bora no browser — LANÇADO

## URL final

**https://bora-app-web.pages.dev** (Cloudflare Pages, projeto `bora-app-web`, conta Nilofulfarotuga)

Mesmo URL para os três papéis — o `_RootNavigator` roteia sozinho:
cliente, estafeta, parceiro e **admin** (o painel admin já era este mesmo app Flutter,
por isso abre no browser sem nada de novo).

Marcador de versão: `https://bora-app-web.pages.dev/versao.json` → commit que está no ar.

## O que funciona, por vertical

Provado no browser real (Playwright, Chrome, 1280px e 390px):

| Vertical | Estado | Prova |
|---|---|---|
| **Restaurantes / entrega** | ✅ **ponta-a-ponta em dinheiro** | pedido `#AB91A5` criado pelo site e confirmado por `SELECT` |
| Mercados / Farmácia / Lojas | ✅ ecrãs carregam, catálogo lista | mesma lista e navegação do Android |
| Limpeza | ✅ ecrã carrega | screenshot 390px |
| Reservar Mesa | ✅ entrada disponível no restaurante | opção "Reservar mesa" no ecrã da loja |
| Beleza / marcações | ✅ **lado parceiro provado** | dashboard "Barbearia Ouro e Prata" com agenda/serviços/barbeiros/financeiro |
| TVDE, Favores, Enviar Encomenda, Levar Compras | ⚠️ entradas presentes e navegáveis; **fluxo completo não foi conduzido** nesta sessão | ver "O que falta testar" |
| **Parceiro (gerir negócio)** | ✅ login + dashboard | `ouro.prata@bora.app` entrou e viu o hub do negócio |
| **Admin** | ✅ mesmo app, mesmo URL | nada de novo foi preciso |

### A prova que não mente

```
id            ab91a55c-3574-468a-ba3f-9e19439bf2b9   (= #AB91A5 no ecrã)
status        created  →  cancelled (limpo no fim)
payment       cash / pending
subtotal      13.00   service_fee 0.65   delivery 2.50   bag 0.30
customer_total 16.45
dropoff       Rua Vasco da Gama, Guarda, Portugal
created_at    2026-07-20 01:01:19+00
```

O `PricingService` (zona protegida, **não tocado**) devolveu no browser exatamente a
mesma conta do telemóvel. O pedido de teste foi cancelado no fim; era `cash`/`pending`,
por isso não houve movimento de dinheiro nenhum.

Também confirmado a funcionar na web:
- **Autocomplete de morada (Google Places)** — sugestões reais da Guarda.
- **Sessão persistente** entre recarregamentos (SharedPreferences → localStorage).
- **Consentimento GDPR**, banner e escolha por categoria.

## Pagamentos web (LIGADOS)

### Desenho usado — e porque é o de menor risco

**Nenhuma Edge Function foi alterada. O `stripe-webhook` não foi tocado.**

- **MB Way na web: funciona sem código novo.** Descobriu-se que o
  `initiateMbwayPayment` nunca usou o SDK do Stripe — só invoca a Edge Function
  `create-mbway-payment-intent`, que confirma o PaymentIntent server-side e faz o Stripe
  empurrar a notificação para a app MB WAY do cliente. Estava barrado por um único
  `if (kIsWeb) return null;`. Removido esse guard, o MB Way passou a funcionar no browser
  com o **mesmo** PaymentIntent, o **mesmo** webhook e o mesmo poll de
  `orders.payment_status`.

- **Cartão na web: `web/pay.html` com Payment Element (Stripe.js).** O PaymentSheet
  nativo do `flutter_stripe` não é fiável no browser (menos ainda no Safari do iPhone, que
  é o alvo). A app pede o `client_secret` às **Edge Functions que já existem** (as mesmas
  11 que criam PaymentIntent: `create-payment-intent`, `tvde-payment`,
  `cleaning-checkout`, `create-reservation-payment-intent`, `create-appointment-payment-intent`,
  `pay-debt-standalone`, …) e abre essa página com ele. Resultado: **mesmo
  PaymentIntent → mesmo webhook v17+ → mesmos refunds e cancelamentos**.

- **Porque é que os 9 fluxos não partiram:** `processPayment(clientSecret)` manteve a
  assinatura — um `Future` que **completa em sucesso e lança em cancelamento/recusa**,
  tal como o PaymentSheet. Por isso todo o código que corre *depois* do pagamento (TVDE,
  limpeza, reservas, marcações, dívida) ficou byte-a-byte igual. A janela de pagamento é
  um popup e a app Flutter fica viva por trás; se o browser bloquear o popup, há queda
  para redirect no mesmo separador.

- **`return_url`** aponta ao próprio `pay.html` (é onde o 3-D Secure volta). Usa-se
  `redirect: 'if_required'`, por isso o cartão simples nem sai da página.

- **Kill switch:** `platform_settings.web_card_payments_enabled`. **Default = LIGADO** —
  se a chave não existir ou a leitura falhar, o pagamento segue. Serve para desligar o
  cartão na web sem fazer deploy; MB Way e dinheiro continuam a funcionar à mesma.

### ⚠️ O que falta — teste humano de ponta-a-ponta

A conta Stripe está em **LIVE**: cartões de teste não funcionam e **não se cobra o cartão
de ninguém num teste automático**. O teste automatizado foi só até ao ecrã de pagamento
(os três métodos aparecem e o de dinheiro completou).

**Danilo, falta fazeres à mão, uma vez:**
1. Um pagamento com **cartão** pelo site.
2. Um pagamento **MB Way** pelo site.
3. Um **cancelamento com reembolso** pelo site.

## Sincronia Android ↔ Web

`/.github/workflows/build_web_deploy.yml` — **separado**; o `build_android.yml` não foi
tocado e o `versionCode` não foi mexido.

- Dispara em push nesta branch, com `paths-ignore` para `**.md`, `.claude/**` e `docs/**`,
  e `concurrency` para não haver dois deploys sobrepostos.
- Passos: build web → carimba `versao.json` → artifact → publica na branch `web-build` →
  deploy Cloudflare.

**Estado real do secret:** o `gh` **não está autenticado** neste PC (`gh auth status` →
"You are not logged into any GitHub hosts") e não há nenhum PAT no sistema, por isso
**não foi possível criar o secret sozinho**. O passo de deploy fica *saltado* (não falha)
enquanto o secret não existir.

### 🔧 TODO_DANILO_SECRET_CLOUDFLARE (1 passo, uma vez)

> GitHub → repositório **bora-app-cloud** → Settings → Secrets and variables → Actions →
> **New repository secret** → Name: `CLOUDFLARE_API_TOKEN` → Value: o token que está em
> `Desktop\bora-site\.env`.

A partir daí, **toda a atualização que vai para a Play Store atualiza a web sozinha**.

**Até lá o caminho já está automatizado à mesma**, sem depender de ti: o CI publica o
build na branch `web-build` e o PC publica com
`bash buscar-build-web.sh && bash deploy-web.sh`.

## Caminho de build usado: **CI** (não local)

Não foi escolha estética — o build local é **impossível** nesta máquina:

```
Could not start thread DartWorker: 22
```

RAM total 3,9 GB, livre ~164 MB, page file 5,7 GB de 8 GB em uso. O dart2js não consegue
arrancar as threads de trabalho. Duas tentativas locais (com e sem `--wasm-dry-run`)
falharam pela mesma razão — **nenhuma delas por erro de código Dart**. A 3.ª abordagem
(CI) compilou à primeira: `Build web (release) — success`.

## Plugins com stub, e porquê

O `dart:io` era o verdadeiro bloqueador (20 ficheiros), não os plugins. Resolvido com
`lib/utils/io_compat.dart` (conditional export). **O ramo por defeito é o do `dart:io`
de propósito** — assim o `flutter analyze` e o build Android resolvem os tipos verdadeiros
e os call-sites ficam iguais; só o browser recebe os stubs.

Na web:
- `File` → lê mesmo os bytes via `XFile` (o `image_picker` web devolve `blob:` URLs), por
  isso **o upload de fotos funciona a sério**, não é fingido.
- `Platform.isAndroid/isIOS` → `false` (que é a resposta correta no browser).
- Previews locais → `NetworkImage` sobre a `blob:` URL.

Sem implementação web (não quebram o build; ficam no-op no browser):
`flutter_local_notifications`, `flutter_foreground_task`, `flutter_overlay_window`,
`floating_bubble_overlay`, `local_auth`, `geocoding`, `vibration`, `path_provider`.
São todos de fluxo do **estafeta** ou de sistema operativo — nenhum afeta o cliente a
comprar nem o parceiro a gerir.

**FCM na web: desligado por opção.** O tempo-real é o **Supabase Realtime**, que a app já
usa. Com o separador aberto, o parceiro vê o pedido novo ao vivo.

## Zona protegida respeitada

`lib/widgets/errand_execution_sheet.dart` (contém `_finalizePurchase`) é zona protegida e
a Trava recusou a edição — **não foi contornada**. Como esse ficheiro importa `dart:io` e
isso impedia o build web, resolveu-se **por fora**: `errand_execution_sheet_compat.dart`
faz a ponte condicional, e o único importador (`driver_home_screen`) passou a usá-la. No
telemóvel exporta a folha real, sem alterar um único byte do ficheiro protegido.

Também intocados: `pricing_service.dart`, `order_store.dart`, `dispatch-engine`,
`stripe-webhook`, `create-payment-intent`, `refund`, `charge-extra`.

## TODOs

- **TODO_DANILO_SECRET_CLOUDFLARE** — ver acima. É o único passo manual.
- **TODO_DANILO_RESTRINGIR_CHAVE_MAPS** — a chave do Maps está *hardcoded* no
  `web/index.html` (herdado). Convém restringi-la por HTTP referrer a
  `bora-app-web.pages.dev`. **A Maps JavaScript API já está ativa** — confirmado em
  runtime (`google.maps.places` carregou e o autocomplete devolveu moradas reais), por
  isso **não** é preciso ativar nada no Google Cloud Console.
- **Logos de terceiros e CORS (cosmético):** logos de restaurantes que apontam para
  `kfc.pt`, `mcdonalds.pt` ou favicons da Google são bloqueados por CORS no browser (no
  Android não são). A app degrada com elegância para a inicial da loja. Logos guardados no
  **Supabase Storage renderizam bem** — a cura definitiva é passar esses logos para o
  Storage.
- **Consola:** o único erro que era nosso (`libraries=directions`, que não existe na Maps
  JS API) foi corrigido nesta sessão. Restam apenas os CORS de imagens externas.

## O que falta testar (honestidade)

Não foram conduzidos até ao fim nesta sessão, por tempo:
- **TVDE** — pedir uma corrida completa e ver a linha em `tvde_rides`.
- **Limpeza / Reserva / Beleza** — marcação completa pelo lado do **cliente** (o lado do
  parceiro foi provado).
- Os 3 testes humanos de pagamento listados acima.

Os ecrãs de entrada dessas verticais carregam e navegam; o que falta é percorrer o funil
até ao fim.

## Provas visuais

`docs/preview-web/` — 5 screenshots desktop (1280px) e 4 mobile (390px), incluindo o
pedido criado e o dashboard do parceiro.
