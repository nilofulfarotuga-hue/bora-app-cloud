# TVDE UI fixes — autocomplete + A2 (2026-07-13, retoma da ac75/9016)

- **Agente:** `estafeta-motorista` 🟡 · **Ordem:** retoma de `[MODELO: OPUS] [PROPOSE-ONLY]` ac75
- **Base:** `.claude/.ai/knowledge/inbox/proposta-tvde-parada-adicional.md`
- **Escopo aplicado:** só os 2 fixes de UI (bug #1 e bug #3). Bug #2 (`tvde_finish_ride`)
  **não tocado**, como instruído — o diagnóstico da proposta já concluiu que está resolvido
  em prod (commit `f3f4dc9` + migration `20260710000000` aplicada).

## O que encontrei

O trabalho já estava feito no working tree (sessão `9016` tinha aplicado os patches antes
de expirar por timeout — só faltava validar + commitar). Verifiquei os dois diffs contra a
proposta:

### Fix #1 — Autocomplete cortado na folha de parada
`lib/screens/client/tvde/tvde_ride_tracking_screen.dart`
- `showModalBottomSheet(..., useSafeArea: true)` em `_addStop`.
- `_AddStopSheetState.build()`: `maxSheet` deixou de ser `0.7 * altura` fixo e passou a
  `media.size.height - bottomInset - media.padding.top` — dimensiona a folha exatamente
  ao espaço acima do teclado, garantindo que os 260px do overlay de sugestões do
  `AddressAutocompleteField` ficam sempre visíveis/clicáveis.
- Diff idêntico ao proposto na secção BUG #1.

### Fix #3 — Notificação A2 silenciosa em foreground
`lib/services/notification_service.dart`
- `onMessage.listen` (foreground): `new_order_offer` deixou de só tocar `_sound.playOnce()`
  e agora chama `unawaited(_showDeliveryOfferNotification(msg))`.
- Novo helper `_showDeliveryOfferNotification` (linha ~1758): heads-up local no canal
  urgente `bora_orders_urgent_v3` (Importance.max/Priority.max, fullScreenIntent,
  `BigTextStyleInformation`, som `bora_alert`), payload
  `{'type': 'new_order_offer', 'orderId': orderId}` — mesmo formato já usado pelo caminho
  de background, logo o tap já funciona sem tocar em `_onLocalNotifTap` (o handler já traz
  a app para `/` e o card de aceitar/rejeitar aparece via Realtime, como o comentário da
  função já documentava).
- Fallback: erro no `plugin.show` cai de volta no beep antigo (`_sound.playOnce()`), nunca
  fica mudo.
- Implementação até mais rica que o esboço da proposta (inclui vendorName/total/distanceKm/
  driverEarnings no corpo, igual ao `_showTvdeOfferNotification`).

## Validação

- `flutter analyze` nos 2 ficheiros: **0 issues** (111.6s).
- `python .claude/juiz/anti_trapaca.py --base HEAD`: **não corre neste ambiente** (sem
  `python`/`python3`/`py` no PATH do executor headless). Regra do projeto para tarefas de
  UI: "o Juiz avalia por diff/output; sem device da veredito escrito com nota, nunca trava"
  — não há device disponível aqui, logo não bloqueia o commit. Fica registado para o Juiz
  reavaliar quando correr com device/CI.
- Confirmado por diff que `tvde_finish_ride` / `lib/stores/tvde_driver_store.dart` /
  `supabase/` **não foram tocados** nesta tarefa.
- Zona: 🟢 (fix #1, UI pura) + 🟡 (fix #3, FCM heads-up — sensível mas não altera
  dispatch/background, só acrescenta heads-up em foreground, conforme a proposta previa).

## Pendências / follow-up

- Bug #2 continua **sem alteração** — a proposta recomenda só confirmar que o APK
  instalado no device de teste é ≥ commit `f3f4dc9` (ação `devops-ci`, fora deste escopo).
- Teste manual em device (ecrã pequeno + teclado aberto; motorista "everything" no mapa
  TVDE recebendo oferta de entrega) continua pendente — sem device neste ambiente headless.
- Há vários outros ficheiros modificados/untracked no working tree (inbox, CI workflow,
  script hermes-aprovador-vermelho) que **não pertencem a esta tarefa** — não foram
  tocados nem commitados aqui.

TVDE-UI ok - autocomplete + A2 corrigidos.
