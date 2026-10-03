# Relatório — BLOCO E: reagendar em vez de cancelar (2026-07-28)

Branch `autonomous-night-2026-04-29` · commit **`fd042ba`** (confirmado no GitHub).
`flutter analyze lib` → **0 erros e 0 warnings** nos ficheiros tocados.

Backend já estava feito por MCP — consumi-o, não refiz nada. Confirmei por SQL:
`client_reschedule_appointment`, `appointment_reschedules`, as colunas
`reschedule_count` / `original_scheduled_at` / `last_rescheduled_at`,
`booking_cancellation_policy` (Ouro e Prata em `reschedule_only`) e as 3 chaves
`appointment_reschedule_*` (3h / 2 / 60 dias).

---

## 1. Ecrã do cliente — cancelar dá lugar a reagendar

`lib/screens/client/services/my_appointments_screen.dart`

- A política e o modo de pagamento do parceiro passam a vir no JOIN
  (`service_providers(..., booking_cancellation_policy, booking_payment_mode)`) —
  `AppointmentModel.isRescheduleOnly` é `reschedule_only` **e** `deposit_status='paid'`.
- Em `reschedule_only`: o botão **Cancelar desaparece** e surge **Reagendar**, com o texto
  *"Não podes vir? Reagenda para outro dia — o valor que pagaste fica reservado para a tua marcação."*
- Em `refund`: **tudo exactamente como estava** — botão Cancelar, o mesmo diálogo com a regra
  das 24h. Não mexi no fluxo que já funciona.
- Reagendamentos restantes: quando resta 1, diz *"Podes reagendar mais 1 vez."*; quando resta 0,
  *"Já não podes reagendar esta marcação."* (o máximo vem de
  `appointment_reschedule_max_count`, não está hardcoded).
- Marcação já reagendada mostra `Reagendada · era <horário original>` no card e no detalhe.

## 2. Fluxo de reagendamento — reutiliza o calendário existente

`lib/screens/client/services/booking_flow_screen.dart` ganhou o parâmetro `rescheduleOf`.
Com ele, o **mesmo** ecrã de marcação corre em modo reagendamento: serviço e profissional
vêm fixos da marcação original e o fluxo arranca directamente na escolha do dia
(`PageController(initialPage: 2)` — o PageView só existe depois do catálogo carregar, por isso
não dá para animar). Não foi construído um segundo selector de slots.

O botão final é **"Confirmar Reagendamento"** e chama **só**
`ServicesStore.rescheduleAppointment` → `client_reschedule_appointment`.
**Zero** marcações novas, **zero** `create-appointment-payment-intent`, **zero** Stripe — é a
mesma linha, logo o mesmo `deposit_pi`.

Confirmação: *"Marcação reagendada para quinta, 30/07 às 15:00. Não há nada a pagar — o valor
já está reservado."*

## 3. Mensagens de erro (PT-PT)

Todos os códigos da RPC estão mapeados em `ServicesStore._mapErrorPtPt`:
`reschedule_window_closed`, `reschedule_limit_reached`, `slot_unavailable`,
`reschedule_too_far`, `cannot_reschedule_status`.

`cancellation_not_allowed_reschedule_only` tem tratamento próprio: `cancelAppointment` lança
`RescheduleOnlyException` e o ecrã mostra *"Esta marcação não pode ser cancelada, mas podes
reagendá-la."* **com um botão "Reagendar"** que abre o fluxo.

> ⚠️ **Bug que tinha de ser corrigido primeiro:** o mapeamento nunca funcionou. As RPCs
> sinalizam com `RAISE EXCEPTION 'slot_taken'`, o PostgREST devolve `code='P0001'` com o texto
> em `message`, e as chamadas passavam `e.code ?? e.message` — ou seja, `'P0001'`. **Todas** as
> mensagens das marcações caíam no genérico "Ocorreu um erro. Tenta de novo.". Corrigido
> (procura também dentro do texto). Sem isto, nenhuma das mensagens acima apareceria.

## 4. App do parceiro

- `appointment_rescheduled` entra nas categorias persistentes de `notification_service.dart`,
  canal `bora_orders` — mesmo padrão do `appointment_cancelled`. O tap abre a agenda.
- `partner_agenda_screen.dart`: etiqueta **"Reagendada"** ao lado do estado e a linha
  `Reagendada · era 29/07 15:00` (lida de `original_scheduled_at`).

## 5. Painel admin (PT-BR)

- `admin_service_provider_detail_screen.dart` — cartão **"Cobrança e cancelamento"**: alterna
  `booking_cancellation_policy` entre *Cancelamento com reembolso (padrão)* e *Somente
  reagendamento*, e `booking_payment_mode` entre *Sinal* e *Valor cheio*, cada opção com o
  efeito escrito por extenso.
- `admin_platform_settings_screen.dart` — `appointment_reschedule_min_hours`,
  `_max_count` e `_max_days` passam a editáveis (são operacionais, não mexem em valor cobrado;
  `appointment_deposit_cents` continua blindada).
- `admin_appointments_screen.dart` — mostra `Reagendada Nx · original: …` e um botão
  **Histórico** que lê `appointment_reschedules` (horário antigo → novo, quem mudou, troca de
  profissional). O botão **Cancelar** em nome do cliente continua lá, intacto: o admin fica
  acima da política.

## 6. Ponta solta — `partner_cancel_appointment` NÃO reembolsa

Verificado no corpo da função. Quando o barbeiro desmarca, ela:

1. põe `status='cancelled'`, `cancelled_by='partner'`;
2. **deixa `deposit_status='paid'`** — não há marcador na BD de que se deve dinheiro;
3. notifica o cliente com *"O sinal será reembolsado."*;
4. levanta `notify_admin_event('appointment_partner_cancel_refund_due', 'high', …)` com o valor
   já correcto (lê `deposit_cents`, por isso em modo `full` diz €15).

Ou seja: **o reembolso é 100% manual** e a promessa feita ao cliente depende de alguém agir no
painel. Em modo `full` isso passa de €3 para €15 por cancelamento do parceiro. Como pediste,
**não alterei a RPC** — fica reportado. Se quiseres o reembolso automático (ou pelo menos
`deposit_status='refund_due'` para não depender de um alerta), é ordem própria e é 🔴.

## 7. Teste real — NÃO FEITO (bloqueado, sem invenção)

`adb devices` devolveu lista vazia — nenhum telemóvel ligado. E mesmo com ele ligado, o teste
exige a **build nova** instalada (o APK actual não tem o tratamento data-only nem o ecrã de
reagendamento). A build Android arrancou no CI com este commit.

Roteiro para quando a build estiver no telemóvel:
1. `adb logcat -c && adb logcat -s NotificationService:V flutter:V`
2. Marcar no Ouro e Prata → confirmar push persistente no parceiro.
3. Reagendar → confirmar horário novo na agenda + push `appointment_rescheduled`.
4. Provar que não houve cobrança nova:
   ```sql
   select id, deposit_pi, deposit_cents, deposit_status, scheduled_at,
          original_scheduled_at, reschedule_count
     from appointments where id = '<uuid>';
   ```
   `deposit_pi` **tem de ser exactamente o mesmo** antes e depois — e não deve existir nenhum
   PaymentIntent novo no Stripe para essa marcação.

## 8. Os dois pressupostos que deixaram de ser verdade

Varri os ecrãs à procura de "marcação = €3" e "cancelar existe sempre":

- **"marcação = €3"** — havia em 4 sítios, todos corrigidos: a constante `_kDepositEur` do
  fluxo de marcação (usada em 3 chamadas), o cartão informativo com o texto fixo
  *"Sinal de €3,00 agora"*, `_depositLabel` em "As minhas marcações", e o card da agenda do
  parceiro. Todos passam a ler o modo do parceiro.
- **"cancelar existe sempre"** — havia em 3 sítios no ecrã do cliente (card, bottom-sheet de
  detalhe e o caminho de erro do cancelamento). Todos passam pela política. O admin e o
  parceiro mantêm o cancelamento de propósito — nenhum dos dois está sujeito à política do cliente.
