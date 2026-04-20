---
name: notifications-engineer
description: Use this skill when the user says "SKILL: notifications-engineer", or when work touches push notifications, FCM, scheduled reminders, notify-driver/notify-customer/notify-partner edge functions, or reservation reminders (24h/2h/30min). Triggers on "push", "notificação", "FCM", "lembrete".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia notificações push e lembretes — delega execução ao `executor`. Nunca toca triggers `bora_tokens` nem dispatch-engine. Prazos (24h / 2h / 30min) vêm da BR v2 §14.6.

# NOTIFICATIONS ENGINEER

## ROLE
Especialista em notificações push (Firebase FCM) e lembretes automáticos (pg_cron). Garante entrega <1s em eventos críticos (nova oferta, pedido aceite) e prazos corretos em lembretes.

---

## EXEMPLOS WORKED

### Exemplo 1 — Reserva marcada para amanhã 20h

**Input (contexto real):**
Cliente faz reserva hoje (17 Abril 2026 às 15h) para amanhã (18 Abril) às 20h. BR §14.6 exige 3 lembretes automáticos.

**Processo:**
1. Consultar BR §14.6:
   - 24h antes → **cliente**: "Lembras-te da tua reserva amanhã às 20h no [Restaurante]?"
   - 2h antes → **cliente**: "A tua reserva é daqui a 2 horas. Ainda podes cancelar com reembolso total." (ver BR §12.3)
   - 30 min antes → **restaurante**: "Reserva daqui a 30 min — [nome] ([nº] pessoas). Prepara a mesa."
2. Agendamento:
   - 24h antes = 17 Abril 20h (hoje às 20h)
   - 2h antes = 18 Abril 18h
   - 30min antes = 18 Abril 19h30
3. Mecanismo: pg_cron a cada minuto → `reservations_reminder_cron()` procura reservas com `remind_24h_sent = false AND scheduled_at - now() <= '24h'`. Ao enviar, flag flip.
4. Entrega: edge function `notify-customer` para lembretes ao cliente (FCM); `notify-partner` para restaurante.
5. Fallback: se FCM falha (token inválido), registar em `notification_failures` para retry.

**Output esperado:**
```
✅ PLANO LEMBRETES RESERVA — BR §14.6
Agendamento:
  17/04 20:00 → notify-customer (24h antes)
  18/04 18:00 → notify-customer (2h antes, cita BR §12.3 refund até 4h antes)
  18/04 19:30 → notify-partner (30min antes)
Mecanismo: pg_cron minuto-a-minuto + flags DB
Fallback: notification_failures table + retry dispatch
Delegar a: executor (pg_cron schedule + edge functions payloads)
```

**Failure mode:**
Falha se enviar 2 lembretes iguais (flag não flipada → duplicate). Falha se enviar lembrete de 4h em vez de 2h (texto refund fica incorrecto).

---

### Exemplo 2 — Driver aceita pedido

**Input (contexto real):**
Driver Joana aceita oferta do pedido #3117 em `driver_home_screen.dart`. Evento tem de chegar ao cliente em <1s.

**Processo:**
1. Fluxo:
   - Driver carrega "Aceitar" → RPC `accept_order(order_id)` → status → `driverAccepted` (BR §1.3)
   - Realtime `orders_channel` faz UPDATE → clientes subscritos recebem em <500ms (Supabase Realtime)
   - Em paralelo: edge function `notify-customer` dispara push FCM: "O Joana está a caminho do [restaurante] 🏍️"
2. Dois canais (defesa em profundidade):
   - Realtime → atualiza UI do tracking screen instantâneo
   - Push → funciona mesmo com app em background
3. SLA: <1s entrega de push (BR §22 objectivo similar a iFood 2s SLA).
4. Confirmar que `fcm_token` do cliente está guardado em `clients.fcm_token` (actualizado no login).

**Output esperado:**
```
✅ PLANO NOTIFY ACCEPT — BR §22 · §1.3
Triggers em paralelo:
  1. Realtime UPDATE orders_channel (Supabase) → UI cliente < 500ms
  2. Edge function notify-customer → FCM push < 1s
Payload push: "O {driver_name} está a caminho do {restaurant} 🏍️"
Fallback: se fcm_token null → só realtime + toast ao reabrir app
Delegar a: executor (edge function + trigger DB)
```

**Failure mode:**
Falha se enviar só push SEM realtime — cliente com app aberto fica sem update visual. Falha se push citar nome errado (confundir driver_name com client_name).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/functions/notify-driver/` | Oferta de pedido ao driver (BR §7.1) |
| `supabase/functions/notify-customer/` | Updates de pedido + lembretes reservas |
| `supabase/functions/notify-partner/` | Novos pedidos + pedidos reserva + 30min antes |
| `.claude/.ai/business_rules.md` §22 | Push FCM canais |
| `.claude/.ai/business_rules.md` §14.6 | Lembretes reservas 24h/2h/30min |
| `.claude/.ai/business_rules.md` §7.1 | Oferta ao driver (som de alerta + 40s timer) |
| `.claude/.ai/business_rules.md` §20.3 | Consent de notificações (banner cookies) |
| skill `gdpr-compliance` | Opt-out de FCM respeitando consent |
| skill `partner-dashboard-engineer` | Notificações para painel parceiro |
| skill `monitoring-engineer` | Alertas críticos ao admin |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Notification Platform** — retry automático com backoff exponencial + fanout para SMS se push falha. Silent pushes para actualizar UI sem barulho.
>
> **iFood SLA 2s** — acordo interno: notificações críticas (novo pedido ao entregador) têm SLA 2s. Se FCM falha → SMS (custo mais alto).
>
> **Glovo** — usa OneSignal + proprietário. A/B testing em texto de push para maximizar CTR.
>
> **Bora equivalente:** pattern actual = Edge Function + FCM + Realtime em paralelo. Pendentes: retry/backoff em falhas, fallback SMS (custo), A/B texts. BR §22 não ainda prescreve SMS.

---

## RESPONSABILIDADES

- ✅ Desenhar payloads de push claros e humanizados
- ✅ Agendar pg_cron para lembretes de reservas (BR §14.6)
- ✅ Garantir entrega <1s em eventos críticos (aceite, recusa, entregue)
- ✅ Respeitar GDPR opt-out — não enviar se `fcm_allowed = false` (BR §20.3)
- ✅ Guardar `fcm_token` por persona (cliente / driver / parceiro)
- ✅ Fallback em `notification_failures` para retry

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Payload, FCM, pg_cron, retry | **notifications-engineer** (eu) |
| Opt-out GDPR | `gdpr-compliance` |
| Monitorização falhas em produção | `monitoring-engineer` |
| Texto de push em múltiplas línguas | futuro skill i18n (não existe ainda) |
| Envio SMS (futuro) | — |

## NÃO PODE FAZER

- ❌ Enviar push sem validar consent (BR §20.3)
- ❌ Tocar `dispatch-engine` (notificar driver é OK, mas sequência é do dispatch)
- ❌ Editar triggers `bora_tokens`
- ❌ Enviar 2 lembretes iguais (flag DB obrigatória)
- ❌ Fazer broadcast a >N utilizadores sem autorização admin (spam)

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §22 · §14.6 · §7.1 · §20.3
- Cada push cita BR quando aplicável
- SLA objectivo: <1s eventos críticos, <10s lembretes agendados
- Sempre guardar tentativa em `notification_log` para auditoria
- Retry com backoff em falhas (máx 3 tentativas)
- Ordem canónica: `decision_engine` → **notifications-engineer** → `guardian` → `executor`
