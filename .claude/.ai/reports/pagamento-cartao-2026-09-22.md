# Pagamento com cartão — missão `pagamento-cartao-2026-09-22`

> Motor: Opus 5 (o Fable não estava disponível nesta sessão). Porta: Claude Code.
> Ramo `autonomous-night-2026-04-29`. Commit **`8e7c91e3`**.
> RAM medida no arranque: **1345 MB** (acima do portão pesado de 800).
> Linhas no `e2e_log`: 2183–2197, `run_id = pagamento-cartao-2026-09-22`.

---

## Em três linhas

O cartão já aparece no iPhone — era isso que fazia a cliente Priscila ir-se embora.
O cartão guardado deixou de cobrar em silêncio: passa a haver sempre uma folha com o
valor e um Confirmar, e um recibo depois. E o painel admin passou a ter a lista de
quem tentou pagar e não conseguiu, com telefone: **10 pessoas desde 30 de Agosto**.

---

## O que estava partido, e porquê

### 1. O cartão nunca aparecia no iPhone

`lib/services/web_checkout_web.dart` abria o `pay.html` numa janela nova. O Safari do
iPhone bloqueia o `window.open` que não venha colado a um toque — e aqui não vinha
(entre o toque e o open há a biometria e a chamada à Edge Function).

O código fazia isto:

```dart
try { blocked = popup.closed ?? true; }
catch (_) { blocked = false; }   // "cross-origin = está viva"
```

Com a janela bloqueada, `popup` é `null`, `popup.closed` **atira**, e o `catch`
concluía que estava viva. A app ficava à espera para sempre de uma janela que nunca
existiu. O watchdog de 700 ms tinha o mesmo `catch` e fazia exactamente o mesmo.

### 2. O cartão guardado cobrava sem folha nenhuma

`SavedCardCheckout.authorize()` só corria a biometria. O PaymentIntent do cartão
guardado nasce já confirmado `off_session`: não há PaymentSheet, não há CVV, não há
nada entre o botão e a cobrança. E o TVDE chamava `authorize()` **sem `amountEur`**,
por isso até o diálogo do sistema saía seco ("Confirma o pagamento").

Pior, `payment_biometric_gate.dart` tinha `if (!await _isCapable()) return true;` —
aparelho sem biometria configurada cobrava sem perguntar nada a ninguém.

### 3. A corrida morria em silêncio quando o pagamento ficava a meio

A oferta de "Pagar de novo" só aparecia se a falha *se parecesse* com uma desistência
(`s.contains('cancel')`). O Ricardo perdeu a corrida `f423e98e` a 21/09 com o
PaymentIntent parado em `requires_action` — a confirmação do banco não se completou,
a excepção não trazia a palavra "cancel", e a corrida morreu sem lhe dizerem nada.

---

## O que mudou, ficheiro a ficheiro

### Bloco 1 — o cartão aparece no iPhone

| Ficheiro | O que lá está |
|---|---|
| `lib/services/web_checkout_regras.dart` **(novo)** | `escolherCaminhoDoCheckout()` e `avaliarEspera()`. Puro, sem `dart:html`, por isso corre na suite normal. A decisão que falhou passou a ser testável. |
| `lib/services/web_checkout_web.dart` | Telemóvel nem tenta o popup. `null` **ou** excepção = BLOQUEADA, nunca "viva". Só se assume viva depois do `pronto` (≤ 1,5 s). Estado pendente em `localStorage` (30 min). Tecto de 90 s sem sinal, 10 min depois de "Pagar". |
| `web/pay.html` | Ping `pronto` no `<head>` **antes** do Stripe.js, batimento `vivo` de 10 s, aviso `a-pagar` no submit, regresso à rota `&volta` (nunca à raiz), tecto de 20 s na montagem do formulário, guarda se o Stripe.js não carregar. |
| `lib/services/retoma_pagamento_web.dart` **(novo)** + `lib/main.dart` | Retoma no arranque: pergunta ao servidor, segue para o acompanhamento se pago, ou dá "Pagar de novo"/"Cancelar". Nunca cancela sem o servidor responder. |
| `lib/services/payment_service.dart` | `processPayment` aceita `vertical`/`referenciaId`/`paymentIntentId` (opcionais — os 10 call-sites não precisaram de mudar). |

**Pormenor que quase correu mal:** o caminho do mesmo separador devolve um `Future`
que **nunca completa**, de propósito. A primeira versão que escrevi atirava uma
excepção — e isso faria o `catch` do ecrã correr `cancelRide` antes de o browser
sequer navegar. Corrigido antes de sair do sítio.

### Bloco 2 — o cartão guardado não cobra em silêncio

| Ficheiro | O que lá está |
|---|---|
| `lib/widgets/payments/folha_confirmar_cartao.dart` **(novo)** | "Pagar 5,00 €" em grande, `Visa •••• 4242`, três saídas: Confirmar / Trocar de cartão / Outro método. Arrastar para baixo conta como "Outro método", nunca como autorização. |
| `lib/services/saved_card_checkout.dart` | `authorize()` passou a exigir `context` **e** `amountEur`. Esquecer o valor **deixou de compilar** — era esse o bug do TVDE. Ordem nova: cartão padrão → folha → biometria. O gate biométrico foi **mantido**; a folha é por cima, não em vez de. |
| 7 call-sites | carwash, cleaning, reservation_checkout, reservation_flow, booking_flow e os **dois do TVDE** (os únicos que não passavam valor). |
| `lib/widgets/tvde/recibo_pago.dart` **(novo)** | "Pago 5,00 € · cartão •••• 4242" no acompanhamento e, em uma linha, no histórico. Só quando o servidor já confirmou. |

### Bloco 3 — pagamento que fica a meio

- A oferta de "Pagar de novo" deixou de depender de a falha se parecer com desistência.
  Nada foi cobrado em nenhum destes casos, logo quem decide é o cliente.
- `_pagamentoAbandonado` pergunta **primeiro ao servidor**: se já estava pago segue sem
  perguntar nada, e é o `payment_status` verdadeiro que escolhe as palavras —
  `requires_action` passa a dizer *"O teu banco não confirmou"*, não "recusado".
- Três saídas: Pagar de novo (mesmo PaymentIntent, não nasce cobrança nova) / Escolher
  outro método (larga a corrida e reabre a folha) / Cancelar corrida.
- MB Way não aprovado passou de aviso técnico a *"Não aprovaste o pagamento a tempo na
  app do teu banco"* + Tentar outra vez / Agora não.

### Bloco 4 — painel admin (PT-BR)

- Migration `admin_tvde_pagamentos_list_2026_09_22` — RPC **só de leitura**, guarda
  `_admin_op_guard()`, scopes `todos | pagos | falhados`. `REVOKE` a PUBLIC e anon.
  **Não mexi** na `admin_tvde_rides_list` existente, de propósito.
- `lib/screens/admin/admin_tvde_pagamentos_screen.dart` — aba **Pagos** (estado, valor,
  método, cliente, PaymentIntent copiável, botão Estornar ligado à acção `refund` da
  Edge `tvde-payment` **que já existia**) e aba **Não conseguiram pagar** (nome,
  telefone copiável, motivo em português). Rota `/admin/tvde/pagamentos` + entrada no
  menu a seguir a "Corridas".

---

## Provas

### Testes

```
flutter analyze   → 0 erros em lib/
flutter test      → 623/623 verdes, 0 falhas
```

Os 18 testes novos prendem as duas regras: `test/web_checkout_regras_test.dart`
(*"janela bloqueada = mesmo separador, nunca esperar para sempre"*, e *"janela que
nunca deu sinal NÃO é cancelamento do cliente — é bloqueio"*) e
`test/saved_card_checkout_test.dart` reescrito para o contrato novo.

### No navegador, com o `pay.html` real

Servido em `127.0.0.1:8898` a partir de uma cópia **byte-a-byte** (confirmada por `cmp`).

| O quê | Resultado |
|---|---|
| Detecção com o user-agent **exacto da cliente** (`iPhone; CPU iPhone OS 18_7 … Safari/604.1`) | `telemovel=true` → **mesmo separador** |
| iPhone Chrome, Android, iPad-que-se-diz-Macintosh (5 toques) | todos telemóvel |
| Mac de secretaria sem toque, Windows Chrome | janela nova |
| Fluxo em 375×812 | não se tentou `window.open`; pendente gravado; navegou no mesmo separador |
| `loaderror` do Stripe (clientSecret inválido) | "Não foi possível carregar o pagamento" + saída |
| **Tecto de 20 s** (duplo do Stripe.js cujo `mount()` pendura — a falha silenciosa que a cliente viu) | aos 5 s ainda rodava; aos ~23 s **"O formulário de pagamento não abriu"** + saída |
| Saída | voltou a `/opener.html` — a **rota de origem**, não a raiz — com o pendente intacto |
| Computador | o `window.open` foi bloqueado e devolveu `null` → mesmo separador. O caminho da janela bloqueada provou-se sozinho. |

### No ar

`/versao.json` = `8e7c91e37233b174a2b5bd77cdae86170d309133`, run 144, `2026-09-22T14:01:29Z`
(61 s depois do push; antes estava `317db0c7` de 21/09). Workflow **verde**.

O ecrã novo do painel também foi: o `main.dart.js` publicado contém "Pagamentos das
corridas", "conseguiram pagar", `admin_tvde_pagamentos_list`, `tvde-payment`/`refund`,
o aviso "dinheiro de verdade" e a entrada do menu.

### As três pernas de um só push

| Perna | Estado | Prova |
|---|---|---|
| **Web** (Cloudflare) | ✅ verde às 14:02 | `/versao.json` com `8e7c91e3`, run 144 |
| **Android** (Play) | ✅ verde às 14:38 (~40 min) | o CI empurrou `58885cea ci: bump versionCode to 616`, e `platform_settings.app_latest_version_code` passou de **615 → 616** |
| **iOS** (App Store Connect) | ✅ verde às 15:25 (1h24) | build **133** enviada; todos os passos do job B `success`, incluindo *"Enviar para o App Store Connect"* |

O **portão do Danilo de 10/09 foi respeitado**: no run do Android o job
*"Autoteste 3 perfis (emulador Android + Play)"* ficou `success` **antes** de o job
*"Build AAB & upload"* arrancar. Nenhuma build saiu sem ele.

> **Armadilha nova, para quem vier a seguir:** o `updated_at` da linha
> `app_latest_version_code` continua a dizer **2026-08-16** apesar de o valor ter mudado
> hoje. Quem julgar a frescura pela data é enganado — a prova é o **valor** e o commit
> do CI.

Isso prova o deploy, não o código — por isso confirmei os dois no ar:

- `pay.html`: `window.boraAvisar('pronto')` no char **1012**, `<script src=js.stripe.com>`
  no char **1197**. O sinal de vida corre antes. Mais o batimento, o `a-pagar`, o
  `&volta`, o tecto de 20 s e a guarda do Stripe.
- `main.dart.js` (9783 KB): contém "Trocar de cartão", "Outro método", "Pago",
  "aprovaste o pagamento a tempo", o texto do 3-D Secure, `bora.pagamento_pendente` e
  "deixou de responder".

> A minha primeira verificação do ping deu **falso negativo**: o `indexOf` apanhou as
> palavras dentro do *comentário* do ficheiro, não do código. Repetida a ignorar
> comentários, dá sim. Fica escrito porque é exactamente o tipo de engano que a regra
> da prova material existe para apanhar.

---

## O que encontrei pelo caminho (não corrigi, como mandado)

1. **Houve uma terceira corrida perdida hoje**, depois dos dois casos da ordem:
   `fa4e4354`, 22/09 às **14:27**, Ricardo (`960386302`), 5,00 €, cartão,
   `requires_payment_method` → `payment_failed`. Esse Ricardo já falhou **três vezes**
   (21/09 16:26, 21/09 18:47, 22/09 14:27) e nunca fez uma corrida.
2. **A lista completa é maior do que se pensava** — 10 pessoas desde 30/08:
   Ricardo ×3, Sandra Nicolau ×2 (30/08), Snayra dos Santos ×2, Julio César Villarroel
   Bonalde, Priscila Prates, e o próprio Danilo. Todas com telefone no painel novo.
3. **O cron tem dois buracos** (`tvde_sweep_abandoned_payments`, de 10 em 10 min):
   não apanha `payment_status = requires_action` (uma corrida presa no 3-D Secure fica
   pendurada se a app não a matar), e só olha para `status = solicitada`, não para as
   paradas em `aguarda_pagamento`. **Não lhe toquei.**
4. **`create-payment-intent` v34 já não aceita `order_id` de stub** ("Order not found").
   Não é defeito — é a função a proteger-se. Mas significa que não há forma de montar
   o Payment Element sem um pedido real, o que limita as provas (ver abaixo).
5. **A diferença entre o cobrado e o final continua por cobrar.** Em corrida paga
   online cobra-se o `est_fare` no início e o valor final é recalculado pela distância
   real no fim; se passar do tecto, ninguém cobra a diferença. Já estava avisado no
   digest de hoje — é zona 🔴, não toquei.
6. **O travão de emergência do cartão na web não existe como linha.**
   `PaymentService.isWebCardPaymentEnabled()` lê
   `platform_settings.web_card_payments_enabled` — e essa chave **não está lá**
   (`count(*) filter (where key = 'web_card_payments_enabled')` → **0**). O código
   trata a ausência como "ligado", que é o estado seguro e o que está a acontecer
   agora. Mas significa que, se um dia for preciso desligar o cartão na web sem fazer
   deploy, o interruptor não está disponível: alguém tem de criar a linha primeiro.
   É chave de pagamentos — **não a criei**.

---

## O que ficou por provar, e porquê

**O formulário de cartão a montar de verdade.** Faltava um `clientSecret` válido, e o
`create-payment-intent` no ar exige um pedido real. Criar um pedido a sério em produção
arriscava oferecê-lo a estafetas reais (cicatriz conhecida), e não o fiz. Ficou provado
todo o caminho **até** ao formulário e **todos** os caminhos de falha.

**A retoma no arranque** está escrita e testada por leitura, mas não foi percorrida
ponta-a-ponta com um pagamento real — pela mesma razão. Ela só corre quando o
pagamento sai pelo mesmo separador, e é idempotente por construção: pergunta sempre ao
servidor antes de decidir, e o "Pagar de novo" reusa o mesmo PaymentIntent.

**A retoma só sabe perguntar pelo TVDE.** As outras verticais caem numa mensagem neutra
("vê o estado do teu pedido no ecrã dele") porque o ecrã delas já faz o seu próprio
poll. Foi decisão consciente: o TVDE era o bug provado.

---

## O iPhone

A build **133** (`CFBundleVersion` = `github.run_number`) está no App Store Connect,
feita do commit `8e7c91e3`. Run `35737371903`, 14:01 → 15:25 (**1h24**). A anterior no
ASC era a 132.

O portão foi respeitado: o job A (*"Compila e corre no simulador"*) ficou `success` —
análise estática, testes unitários, goldens e a **varredura de ecrãs (portão, sem
escape)** — e só então correu o job B, cujos passos passaram todos, incluindo
*"Conferir que os segredos de assinatura existem"*, *"Construir o IPA"* e **"Enviar para
o App Store Connect"**.

> **Limite desta prova:** o que está provado é que o **CI enviou**. A chegada da build
> ao TestFlight depende do processamento da Apple (10–30 min) e não pude confirmá-la
> daqui — a chave `.p8` vive nos segredos do GitHub, não neste PC.

**Decisão que tomei e porquê:** não fiz avançar `origin/ios-lancamento`. Está **153
commits atrás** da produção e **0 à frente** (um fast-forward bastava), parado desde
13/09, e é o ramo de onde nascem as builds aprovadas pela Apple. Mexer-lhe é acto de
publicação, e há uma ordem em fila — `iphone-automatico-2026-09-22` — que existe
precisamente para tratar deste pipeline. Disparar o build na branch de produção entrega
a build ao App Store Connect sem tocar nesse ramo nem submeter nada a revisão.

**O que fica à espera da Apple:** a build está no ASC e fica lá parada. Para chegar ao
iPhone do Danilo falta atribuí-la ao grupo de testadores internos do TestFlight; para
chegar aos clientes falta submetê-la a revisão. **Nenhuma das duas acontece sozinha
hoje** — é exactamente o que a ordem em fila vai resolver.

---

## A ordem que chegou a meio

A `iphone-automatico-2026-09-22` chegou durante esta sessão. A própria ordem diz *"só
colar isto depois de a missão `pagamento-cartao-2026-09-22` ter fechado. Uma ordem de
cada vez"* e *"abre uma sessão nova"* — por isso **não foi arrancada**. Ficou guardada
em `.claude/.ai/inbox/ORDEM-PENDENTE-iphone-automatico-2026-09-22.md`, com um apontamento
útil para quem a pegar: `ios-lancamento` está 153 commits atrás e 0 à frente.

---

## ⚠️ PARA O DANILO

1. **Liga aos que ficaram sem corrida.** Estão todos no painel novo, em
   *Bora Motorista → Pagamentos das corridas → "Não conseguiram pagar"*, com telefone
   para copiar. O Ricardo do `960386302` tentou três vezes.
2. **O estorno está ligado, mas é dinheiro a sério.** O botão chama a Stripe e não tem
   desfazer. A folha avisa antes.
3. **Os dois buracos do cron** (ponto 3 acima) — dizes se queres que se fechem.
