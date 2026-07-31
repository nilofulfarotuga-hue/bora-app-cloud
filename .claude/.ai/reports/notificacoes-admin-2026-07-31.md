# Notificações do Admin + Auditoria Geral — 2026-07-31

Branch `autonomous-night-2026-04-29` · Supabase `ojykpzwqrtusfeakzrna`

---

## TAREFA 1 — Notificação persistente do admin

### A suspeita principal estava ERRADA (e isso importa)

O pedido dizia: *"se `bora_admin_urgent` não estiver lá, achaste"*.

**Está lá.** `lib/main.dart:162` cria o canal `bora_admin_urgent` (Importance.max,
som, vibração) desde a PARTE A de 2026-07-17. Canais que o app cria mesmo:

| Canal | Onde é criado |
|---|---|
| `bora_orders_urgent_v3` | `main.dart:141` (Dart) + `MainActivity.kt:152` (nativo, com `bora_alert` + bypass DND) |
| `bora_admin_urgent` | `main.dart:162` |
| `bora_reservations` | `MainActivity.kt:117` |
| `bora_service` | `foreground_service.dart` |
| `bora_bubble` | `floating_bubble_service.dart` |
| `bora_orders` | **só on-demand** — corrigido hoje, ver Tarefa 2 |

O `MainActivity.kt:136-137` **apaga** `bora_orders_urgent` e `bora_orders_urgent_v2`
a cada arranque. Mas o `AndroidManifest.xml:86` tem
`default_notification_channel_id = bora_orders_urgent_v3`, por isso um push para
canal morto **não é descartado** — cai no v3. Foi por isso que o `notify-partner`
continuou a funcionar. Canal morto aqui é um problema de UX (som errado), não de
entrega.

### Causa raiz real: bloco `notification` no payload FCM

A Edge Function mandava **`notification` + `data`** ao mesmo tempo. Com o bloco
`notification` presente, no Android:

- **app fechada / em segundo plano** → quem desenha é o *tray* do sistema. O
  handler Flutter `_firebaseMessagingBackgroundHandler` não corre, e portanto a
  notificação local **persistente** (`ongoing:true` / `autoCancel:false`) nunca é
  postada. Resultado: notificação efémera, que desaparece sozinha.
- **app aberta noutro ecrã** → o sistema **não** desenha nada (é a regra do FCM em
  foreground) e o `msg.notification` também não é auto-exibido. Resultado: nada.

Isto é **exatamente** a mesma causa raiz já apanhada e corrigida no
`notify-service-provider` v3 a 2026-07-28 — está escrita no próprio código, em
`lib/services/notification_service.dart:863-867`:

> *"passou a DATA-ONLY (foi essa a causa raiz do parceiro não receber nada: com
> bloco `notification`, o Android desenhava a notif efémera e o handler Flutter
> nunca corria)"*.

O `notify-admin-urgent` ficou de fora dessa correção. A suspeita do Danilo no
ponto 2 do pedido ("agravantes") era a certa; a do ponto 1 (canal em falta) não.

### O que ficou aplicado

**1. Edge Function `notify-admin-urgent` → v15, DATA-ONLY** *(deployed, `verify_jwt=true` preservado)*
- Removido o bloco `notification`.
- `title` / `body` passam a viajar dentro de `data` (não há de onde os ler noutro sítio).
- `android.priority: high` mantido; `apns` passa a `content-available` puro.
- O antigo `sticky` vira `data.persistent`.

**2. `lib/services/notification_service.dart`**
- `admin_generic` / `crosstalk_critical` leem `data['title']` / `data['body']`,
  com `notif?.*` como fallback defensivo para Edges antigas.
- Passam a usar o canal **`bora_admin_urgent`** (antes caíam em `bora_orders`,
  Importance.high) com `Importance.max` + `Priority.max`.
- `_showPersistentStatusNotification` ganhou `channelOverride` /
  `channelNameOverride`.

Ambos os caminhos já existiam e continuam ligados:
- fundo/fechada → `_kPersistentCategoryTypes` (linha 277) → notificação persistente;
- foreground → `onMessage` (linha 1294) → a mesma notificação;
- toque → `AdminPushService._routeForMessage` → rota em `data.route` (`/admin…`).

### Prova — o que consegui e o que NÃO consegui

Consegui, do lado do servidor:

```
-- disparo real depois do deploy v15
select public.notify_admin_urgent_push('teste','TESTE PERSISTENTE — data-only v15',
                                       'teste','t1','{}'::jsonb,'/admin');
-- → d20986b3-43a7-471c-8581-319f60d4f19a

-- token NÃO foi limpo (logo o FCM aceitou a mensagem)
select count(*), max(last_used_at) from admin_push_tokens;
-- → 1 | 2026-07-31 21:52:30+00
```

Token registado: device `android BP4A.251205.006.A366BXXSACZF1` (Samsung Galaxy
A36, Android 16), criado 2026-07-31 21:20, fresco.

**NÃO consegui o screenshot.** `adb devices` devolveu lista vazia — nenhum
telemóvel ligado por USB durante toda a sessão:

```
List of devices attached
(vazio)
```

Sem device não há screenshot, e sem screenshot **isto não está fechado** — é a
própria regra do pedido e não a vou contornar. O que falta é mecânico:

1. Ligar o telemóvel por USB com depuração ativa.
2. Instalar o build novo (o push desta sessão gera-o no CI).
3. Fechar a app → disparar a query acima → screenshot.
4. Repetir com a app aberta noutro ecrã.

⚠️ **Nota de janela de risco:** a Edge já está data-only, mas o telemóvel ainda
tem o APK antigo. Nesse APK o handler lê `notif?.title`, que agora vem nulo → até
o build novo chegar, o push admin aparece como **"🔴 Bora Admin" com corpo vazio**
(persistente, mas sem texto). Assim que o build desta sessão for instalado, fica
com título e corpo corretos.

---

## TAREFA 2 — Auditoria de todas as notificações

`notifBlock` = manda bloco `notification` (mau: impede o handler Flutter de correr).
`type roteado` = o `type` está em `_kPersistentCategoryTypes`, ou seja o app
**quer** desenhar a notificação ele próprio — e o bloco `notification` impede-o.

| Vertical | Edge Function | Canal | Canal existe? | Data-only? | `type` roteado? | Veredito |
|---|---|---|---|---|---|---|
| Entregas — estafeta | `notify-driver` | `bora_orders_urgent_v3` | ✅ | ❌ | — (UI própria) | ✅ OK |
| Entregas — cliente | `notify-client` | `bora_orders` | ⚠️→✅ corrigido | ❌ | ❌ `order_status` | ✅ OK (tray basta) |
| Entregas — parceiro | `notify-partner` | `bora_orders_urgent_v2` | ❌ morto → fallback v3 | ❌ | ❌ | ⚠️ som do canal errado |
| Mercados / compras | `notify-purchase-finalized` | `bora_orders` | ⚠️→✅ corrigido | ❌ | ✅ `purchase_finalized` | ❌ **mesmo bug da T1** |
| TVDE — motorista | `notify-tvde-driver` | (default v3) | ✅ | ✅ | ✅ | ✅ OK |
| TVDE — cliente | `notify-tvde-client` | `bora_orders` | ⚠️→✅ corrigido | ❌ | ✅ `tvde_ride_status` | ❌ **mesmo bug da T1** |
| Reservas | `notify-partner` (kind) | `bora_reservations` | ✅ (nativo) | ❌ | ❌ | ✅ OK |
| Serviços / Beleza | `notify-service-provider` | `bora_orders_urgent_v2` | ❌ morto → fallback v3 | ⚠️ local diz que não; deployed v3 diz que sim | ✅ `appointment_*` | ⚠️ local vs deployed divergem |
| Limpeza | `notify-cleaner` | `bora_orders_urgent_v3` / `bora_orders` | ✅ | ❌ | ✅ `cleaning_*` | ❌ **mesmo bug da T1** |
| Favores / errands | — | — | — | — | — | ⚠️ sem Edge própria |
| Chat | `notify-chat-message` | (default v3) | ✅ | ✅ | ✅ `chat` | ✅ OK |
| Wallet / reembolsos | `notify-admin-reimbursement` | `bora_admin_urgent` | ✅ | ❌ | ✅ `admin_reimbursement` | ❌ **mesmo bug da T1** |
| Avaliações parceiro | `notify-partner-low-rating` | `bora_partner_ratings` | ❌ **não existia** →✅ criado | ❌ | ✅ `low_rating` | ❌ **mesmo bug da T1** |
| Admin — urgente | `notify-admin-urgent` | `bora_admin_urgent` | ✅ | ✅ **v15 hoje** | ✅ `admin_generic` | ✅ **corrigido** |

### Corrigido nesta sessão (risco zero, aplicado)

- **`bora_partner_ratings` não existia em lado nenhum** (nem Dart nem Kotlin). O
  `notify-partner-low-rating` mandava para um canal fantasma; só aparecia por
  causa do fallback do Manifest, e com o som insistente do canal de ofertas.
  → criado em `main.dart`.
- **`bora_orders` só nascia on-demand** dentro de `_showPersistentStatusNotification`.
  Numa instalação nova ainda não existia quando o primeiro push chegava → mesmo
  fallback errado. → criado no arranque, em `main.dart`.

### Fica listado, NÃO aplicado (é maior e não posso verificar sem o telemóvel)

Cinco Edge Functions têm **exatamente** o bug da Tarefa 1 — mandam bloco
`notification` num `type` que o app quer desenhar ele próprio de forma persistente:

| Edge Function | `type` | Efeito hoje |
|---|---|---|
| `notify-cleaner` | `cleaning_offer` / `cleaning_status` | oferta de limpeza desaparece sozinha |
| `notify-tvde-client` | `tvde_ride_status` | estado da corrida efémero |
| `notify-purchase-finalized` | `purchase_finalized` | fecho de compra efémero |
| `notify-admin-reimbursement` | `admin_reimbursement` | reembolso admin efémero |
| `notify-partner-low-rating` | `low_rating` | avaliação baixa efémera |

**Porque não as converti já:** cada conversão exige a alteração emparelhada no
Dart (ler `title`/`body` do `data` — hoje só o `tvde_ride_status` e os
`appointment_*` já o fazem) e, sobretudo, **exige verificação no telemóvel**. Sem
device, converter cinco caminhos de notificação de uma app em produção — que a
partir de hoje publica automaticamente para todos os utilizadores reais (Tarefa 4)
— seria trocar um bug conhecido por cinco regressões não testadas. É o próximo
lote, a fechar com o telemóvel ligado.

### Outros achados

- **`notify-partner` e `notify-service-provider` usam `bora_orders_urgent_v2`**,
  canal que o `MainActivity.kt:137` apaga a cada arranque. Sobrevivem pelo
  fallback do Manifest, mas herdam o som de OFERTA (bypass DND, vibração longa).
  Deviam passar a `bora_orders_urgent_v3` explicitamente. Não toquei porque o
  ficheiro **local do `notify-service-provider` diverge do deployed** (a memória
  diz que o deployed é v3 data-only; o local ainda tem bloco `notification` e
  canal v2) — fazer deploy do local sobrescreveria a versão boa com uma antiga.
  **A resolver antes de mexer: reconciliar local ↔ deployed.**
- **Favores/errands não têm Edge Function de notificação própria.** Reaproveitam
  o caminho de entregas. Confirmar se cobre todos os eventos.
- **Só 1 de 2 parceiros de Serviços tem token** — continua verdade; é registo de
  token, não é caminho de envio. Fica em aberto.

---

## TAREFA 3 — Deploy web

**Está a funcionar.** Todo o push corre `build_web_deploy.yml`.

| Run | Estado | Quando |
|---|---|---|
| 30665071727 | ✅ success (2m59s) | 2026-07-31 21:01 |
| 30663179903 | ✅ success (2m40s) | 2026-07-31 20:31 |
| 30530662071 | ✅ success (5m11s) | 2026-07-30 09:26 |

Produção verificada ao vivo:

```
https://bora-app-web.pages.dev/            → HTTP 200
https://bora-app-web.pages.dev/version.json → {"version":"1.0.1","build_number":"505"}
```

O site tem o código de hoje. O `build_number` mostra 505 e não 506 porque o
commit que faz o bump do versionCode leva `[skip ci]` — o rótulo fica uma versão
atrás, o código não. Os dois commits mais recentes são só `.md`, apanhados pelo
`paths-ignore`. **Nada partido.**

---

## TAREFA 4 — Track de produção

`.github/workflows/build_android.yml`:

```diff
-          tracks: alpha,internal
+          tracks: internal,alpha,production
           status: completed
```

- `internal` mantido e **posto em primeiro** — é por aí que o telemóvel do Danilo
  recebe primeiro (entrega sem revisão).
- `status: completed` — **nunca** `draft`; draft ficaria parado na consola à
  espera de um clique.

**Rollout faseado: NÃO aplicado.** A razão é mecânica, não preguiça. O
`r0adkll/upload-google-play@v1` aplica **um único** `status`/`userFraction` a
**todos** os tracks do mesmo step. Pôr `inProgress` + `userFraction: 0.1`
travaria também o `internal` e o `alpha` a 10% — o oposto do pedido, porque o
telemóvel do Danilo e os 12 testadores deixariam de receber de forma fiável.
Separar em dois steps também não serve: o segundo upload do **mesmo versionCode**
é rejeitado pela API (*"already exists"*). Para ter faseado a sério é preciso um
step extra que fale direto com a Play Developer API e atribua o versionCode já
carregado ao track de produção com `userFraction`. Fica como próximo passo.

### ⚠️⚠️ AVISO — LER

> **A partir deste push, cada push nesta branch vai para TODOS os utilizadores
> reais da Google Play, a 100%, sem revisão humana pelo meio, numa app que cobra
> dinheiro a sério (Stripe LIVE + MB Way).**
>
> Não há rollout faseado a amortecer. Um bug que passe o CI chega a toda a gente.
> Foi decisão explícita do Danilo nesta sessão.

`changesNotSentForReview` **não voltou** ao workflow.

---

## Validação

```
flutter analyze lib/services/notification_service.dart  → No issues found!
flutter analyze lib/main.dart                           → No issues found!
```

`versionCode` não foi tocado à mão — o CI trata.

---

## O que ficou por fazer

1. **Screenshot no telemóvel** (Tarefa 1) — bloqueado: nenhum device em `adb devices`.
   É o único passo que fecha a Tarefa 1.
2. **Converter as 5 Edge Functions** listadas na Tarefa 2 para data-only, com a
   alteração emparelhada no Dart.
3. **Reconciliar `notify-service-provider` local ↔ deployed** antes de qualquer
   deploy desse ficheiro.
4. **`notify-partner` / `notify-service-provider`: canal v2 → v3** explícito.
5. **Rollout faseado real** em produção, via Play Developer API num step próprio.
6. **Favores/errands** — confirmar cobertura de notificações.
