# Relatório — Serviços: notificações, cobrança, horário e QR (2026-07-28)

Branch `autonomous-night-2026-04-29` · commit **`fd042ba`** (confirmado no GitHub).
`flutter analyze lib` → **0 erros e 0 warnings** em todos os ficheiros tocados.

O reagendamento (BLOCO E do adendo) está em [`RELATORIO_reagendamento_2026-07-28.md`](RELATORIO_reagendamento_2026-07-28.md).

---

## ⚠️ O QUE ESPERA O TEU "VAI"

**Migration `supabase/migrations/20260728120000_appointment_booking_payment_mode.sql` — ESCRITA, NÃO APLICADA.**

ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Porquê: descobri que **não é o app que preenche `deposit_cents`** — é a RPC
`client_book_appointment`, que grava sempre `platform_settings.appointment_deposit_cents`
(300). O prompt assumia que era o app. Sem esta migration, o ecrã do cliente já diz
"Pagas agora €15,00 — valor total do serviço" (Ouro e Prata está em `booking_payment_mode='full'`)
mas o Stripe continua a cobrar €3.

A migration muda **uma única linha de valor**: em modo `full`, `deposit_cents = price_cents`
do serviço. Não toca em `appointment_deposit_cents`, nem no split
`appointment_deposit_bora_cut_cents`/`_partner_cut_cents`, nem na Edge
`create-appointment-payment-intent` (essa já cobra `appt.deposit_cents`).

**Aplicar ao mesmo tempo que a build entra no ar** — enquanto não aplicares, o texto e a
cobrança contam histórias diferentes.

---

## BLOCO A — push do parceiro de Serviços

O backend já estava certo (Edge v3 data-only). O que faltava era do lado do app, e havia
**duas causas independentes** para os prestadores sem token:

| Ficheiro | O que mudou |
|---|---|
| `lib/screens/partner_login_screen.dart` | Regista o token FCM **também no ramo só-serviços**. Até aqui só o `initState` do hub registava — quem ficasse noutro ecrã (ou em análise) nunca aparecia em `partner_push_tokens`. Provado por SQL: 3 dos 5 prestadores com **zero** linhas. |
| `lib/services/push_token_service.dart` | A chave de dedup de sessão era só `(token, role)`. Num device partilhado — logout do parceiro A, login do B — token e role são iguais, o UPSERT era saltado, e o parceiro B ficava **sem pushes**. Passa a incluir o utilizador autenticado. |
| `lib/services/notification_service.dart` | `appointment_cancelled` e `appointment_rescheduled` entram em `_kPersistentCategoryTypes`. `title`/`body` passam a ser lidos de dentro de `data` (`data['title'] ?? notification?.title`, com o fallback defensivo). `appointment_new` passa ao canal insistente `bora_orders_urgent_v3` (som em loop — é oferta de trabalho); cancelamento e reagendamento ficam em `bora_orders`. Novo `openPartnerAgendaFromNotification()`: o tap abre a **agenda**, não a home — incluindo cold start (app morta). `savePushTokenForServicePartner` passa a ligar `_boundRole='partner'`. |

**Nota sobre o trigger:** segui o adendo — `trg_appointments_notify_provider` foi removido e
quem notifica é `public._appt_notify_partner()`, chamada pelas RPCs. Confirmei por SQL que a
tabela `appointments` só tem o trigger `trg_appointments_updated`. Os comentários no código
referem a função, não o trigger.

### Teste real — NÃO FEITO (bloqueado)

`adb devices` → **lista vazia**, nenhum telemóvel ligado por USB. Não inventei evidência.

Além disso, mesmo com o telemóvel ligado, o teste **só é válido depois de instalar a build
nova** — o APK que está no telemóvel não tem o tratamento data-only. A build Android arrancou
no CI com este commit.

Quando o telemóvel estiver ligado e com a build nova, o teste é:
```bash
adb logcat -c && adb logcat -s NotificationService:V PushTokenService:V flutter:V
```
e fazer uma marcação no Ouro e Prata. Espera-se: `✓ token registered for partner`,
`persistent notif posted type=appointment_new`, notificação presa no ecrã até tocar, som em loop.

**Sinal indirecto de que o diagnóstico está certo:** o único token do Ouro e Prata foi criado
em 2026-07-19 05:56 e tem `last_used_at` 2026-07-19 06:09 — nunca mais foi renovado. É
exactamente o padrão de "só regista quando abre o hub".

---

## BLOCO B — cobrança do valor cheio (por parceiro)

Lido de `service_providers.booking_payment_mode`; todos os outros parceiros continuam em
`deposit` sem uma única mudança de texto.

- `lib/models/service_provider_model.dart` — `bookingPaymentMode` + `isFullPaymentMode`.
- `lib/models/appointment_model.dart` — o modo do parceiro entra pelo JOIN (`providerPaymentMode`).
- `lib/screens/client/services/booking_flow_screen.dart` — `_kDepositEur` fixo em 3,00 dá
  lugar a `_amountDueEur`, usado nos **três** sítios que mostravam o valor (sheet de método de
  pagamento, autorização do cartão guardado, diálogo MB Way). Em modo `full` o texto é
  *"Pagas agora €15,00 — valor total do serviço. Não há mais nada a pagar na loja."* — sem
  qualquer menção a sinal ou a "€2 descontados na chegada".
- `lib/screens/client/services/my_appointments_screen.dart` — em modo `full` deixa de dizer
  "Sinal €15,00 pago" (mentira: sugeria que faltava pagar o resto) e diz "Total €15,00 pago";
  o detalhe mostra "Pago pela app".
- `lib/screens/partner/services/partner_agenda_screen.dart` — o card mostra
  `€15,00 · Pago pela app: €15,00 (valor total)` vs `€15,00 · Sinal: €3,00`.

## BLOCO C — horário de atendimento com pausa

**Confirmei por SQL o que o adendo diz:** o `business_hours` é vitrine. Quem gera os slots é
`get_available_slots`, que lê `staff_availability` (e `staff_availability_exceptions` com
prioridade). Já respeita a pausa, e o Gilberto já está com 09:00–20:00 / pausa 13:00–14:00 /
domingo fechado. **Não refiz nada disso.**

- **Novo** `lib/models/weekly_hours.dart` — `DayHours` da vertical Serviços, com validação
  (fecho > abertura; pausa dentro do horário aberto) e conversão para os dois destinos.
- **Novo** `lib/widgets/services/weekly_hours_editor.dart` — editor partilhado parceiro/admin
  (a mesma validação nos dois, para não haver duas verdades).
- **Novo** `lib/screens/partner/services/partner_service_hours_screen.dart` (PT-PT) — ligado
  ao hub como tile **"Horário de atendimento"** (não ficou casca sem fio). Grava as 7 linhas de
  `staff_availability` **e** espelha em `business_hours`. Com mais de um profissional há
  selector + "aplicar a toda a equipa".
- `lib/screens/admin/admin_service_provider_detail_screen.dart` — **a aba Horários escrevia só
  em `business_hours`**, ou seja, o admin editava horários que não mudavam um único slot
  reservável. Reescrita para o mesmo editor e para a fonte real, mais um cartão
  "Cobrança e cancelamento" com os toggles de `booking_payment_mode` e
  `booking_cancellation_policy`, cada opção com o efeito escrito por extenso.
- `lib/screens/admin/admin_platform_settings_screen.dart` — as 3 chaves operacionais de
  reagendamento passam a editáveis (não são dinheiro). `appointment_deposit_cents` continua blindada.

## BLOCO D — rota web `/registo-cliente`

- **Novo** `lib/screens/qr_client_signup_screen.dart` + rota em `lib/main.dart`.
- `https://bora-app-web.pages.dev/#/registo-cliente` cai **directo** no formulário de registo de
  cliente, sem o ecrã de escolha de papel. Com sessão activa, põe o papel a cliente e devolve o
  controlo ao `_RootNavigator` (padrão widget-rebuild — nunca navegar à mão para a home).
- URL tratada como canónica (constante `QrClientSignupScreen.routeName`, com o aviso no código).
- O deploy web sai do CI (`Build & Deploy Web`) neste mesmo commit — o PC não tem RAM para
  build web local.

**Publicado e verificado:**
```
$ gh run view 30380324477 --json conclusion   → WEB_DEPLOY: success
$ curl -s -o /dev/null -w "HTTP %{http_code}" "https://bora-app-web.pages.dev/#/registo-cliente"
HTTP 200
$ curl -s "https://bora-app-web.pages.dev/main.dart.js" | grep -c "registo-cliente"
1
```
O `grep` no bundle publicado é a prova que interessa: numa SPA o 200 sozinho não diz nada
(qualquer caminho devolve o `index.html`). A string da rota estar dentro do `main.dart.js`
em produção prova que o código novo está no ar.

**O que NÃO consegui verificar:** o ecrã a renderizar. O browser desta sessão não estava a
compositar frames (screenshot em timeout, árvore de semântica do Flutter vazia), por isso não
tenho captura do formulário de registo. Abre o link no telemóvel/Safari para confirmares a olho.

---

## Bugs encontrados fora do scope

1. **`notify-client` ignora o `kind` das marcações.** `_appt_notify_client()` envia
   `kind: 'appointment_cancelled'` e `type: 'appointment_status'`, mas a Edge `notify-client`
   tem `type: 'order_status'` **hardcoded** no payload FCM e ainda usa bloco `notification`.
   Resultado: o **cliente** recebe os avisos de marcação tipados como estado de pedido de
   entrega, e não persistentes. É a mesma lição do `licao-notify-canal-errado`.
   Não lhe toquei: essa função serve todos os fluxos de delivery e mudá-la sem teste é risco a
   sério. Merece ordem própria.
2. **`partner_cancel_appointment` não reembolsa nada.** Marca `status='cancelled'`, deixa
   `deposit_status='paid'` e levanta um alerta admin (`notify_admin_event`) para alguém
   processar à mão. O valor no alerta lê `deposit_cents`, portanto em modo `full` já diz €15 —
   mas **o reembolso é manual**. Como o adendo pediu, **não alterei a RPC**. Se queres o
   reembolso automático quando é o barbeiro que desmarca, é ordem separada (🔴, mexe em dinheiro).
3. **`_mapErrorPtPt` (services_store) nunca casava** — as RPCs sinalizam com
   `RAISE EXCEPTION 'slot_taken'`, o PostgREST devolve `code='P0001'` e as chamadas passavam
   `e.code`. **Todas** as mensagens de erro das marcações caíam no genérico "Ocorreu um erro".
   **Corrigido** (procura também dentro do texto), porque sem isso as mensagens do BLOCO E não
   funcionavam de todo.
4. Os dois bugs já conhecidos **persistem**, como pedido — não lhes toquei:
   `register_partner_screen.dart:33` (`_formKey` nunca lido) e
   `refund_choice_dialog.dart:65` (`_tokenValueCentsX100` órfão).
5. `service_providers` tem coluna `fcm_token` que ninguém escreve nem lê na vertical Serviços
   (o push usa `partner_push_tokens`). Coluna morta — candidata a limpeza.

## Ponto pendente de decisão (BLOCO B)

Reembolsar **€15 inteiros** num cancelamento tardio é risco financeiro maior do que devolver
€3. Hoje isso está mitigado por acidente: o Ouro e Prata está em `reschedule_only`, portanto o
cliente **não consegue** cancelar uma marcação paga — só reagendar. Se algum dia puseres um
parceiro em `full` + `refund`, a janela de 24h devolve o valor cheio. Confirma com o Gilberto
se é isso que ele quer.
