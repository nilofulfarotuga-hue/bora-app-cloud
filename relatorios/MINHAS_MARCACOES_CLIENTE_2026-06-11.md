# "As Minhas Marcações" do cliente — vertical Serviços
**Data:** 2026-06-11 · **Gap confirmado em device:** cliente paga sinal €3 e não tem onde ver a marcação
**Modo:** PROTECÇÃO TOTAL · edits cirúrgicos · zero lógica financeira nova

---

## 1. Investigação primeiro (missão item 1) — o que JÁ existia

A vertical Serviços (sessão 2026-06-08) já tinha construído **quase tudo**:

| Peça | Estado encontrado |
|---|---|
| Ecrã `MyAppointmentsScreen` | ✅ EXISTIA — 3 tabs (Próximas/Passadas/Canceladas), cards, cancel modal |
| `ServicesStore` | ✅ `fetchMyAppointments` + `subscribeMyAppointments` (realtime) + `cancelAppointment` |
| `AppointmentModel` | ✅ completo (servicePriceCents, depositCents, depositStatus, staff, notas…) |
| RPC `client_cancel_appointment` | ✅ no DB — janela 24h server-side, devolve `will_refund` |
| RLS `appointments` | ✅ `client_user_id = auth.uid()` OR dono do provider OR admin |
| Crons lembretes | ✅ **ativos**: `appt-reminders-24h` (10h diário) + `appt-reminders-2h` (cada 30min) — o de 24h faz push ao **cliente** (`notify_client` no prosrc); + `appt-auto-noshow` + `appt-weekly-payout` |
| Admin | ✅ `admin_appointments_screen` (filtros estado/prestador/dia) + payouts + métricas + cancel em nome do cliente |

### O verdadeiro gap (root cause do problema do Danilo)
`MyAppointmentsScreen` era **órfão**: o ÚNICO caminho era o `booking_success_screen`
(ecrã imediatamente pós-pagamento). Fechada essa página, **não havia nenhuma porta
de entrada** — nem na secção Serviços, nem no Perfil. Benchmark Fresha/Booksy: o
cliente vê sempre as marcações. Era um problema de **wiring**, não de feature.

Lacunas secundárias encontradas: card sem **preço total** nem **estado do sinal**;
sem **detalhe ao tocar**; modal de cancelamento com texto vago ("pode não ser
reembolsado") em vez da regra exata; admin sem **busca por cliente**.

## 2. O que mudou (5 ficheiros, zero DB/RPC/Stripe)

### 2.1 Pontos de entrada (o fix do gap)
- **`profile_screen.dart`** — tile "As minhas marcações" nos quick links do
  cliente (a seguir a "Minhas Reservas", mesmo padrão do histórico de pedidos).
- **`services_category_screen.dart`** — ícone 📋 (`event_note`) na `BoraScreenAppBar`
  do ecrã Serviços → abre as marcações.
- (O atalho existente no `booking_success_screen` mantém-se.)

### 2.2 `my_appointments_screen.dart` — completar o spec da missão
- **Card** ganha linha `€preço • estado do sinal` (ex.: "€12.00 • Sinal €3.00 pago");
  labels PT do sinal: pago/pendente/reembolsado/retido/sem sinal.
- **Detalhe ao tocar** (novo `_AppointmentDetailSheet`, bottom sheet padrão Fresha):
  barbearia+foto, badge de estado, serviço, profissional, data/hora, duração,
  preço total, sinal+estado, notas do cliente, motivo de cancelamento (se aplicável),
  e botão "Cancelar marcação" (só em futuras — `a.isUpcoming`).
- **Modal de cancelamento** agora mostra a REGRA EXATA antes de confirmar
  (business_rules: >24h vs <24h):
  - \>24h: "Regra: reembolso TOTAL do sinal de €3.00 (5–10 dias úteis no cartão)."
  - <24h: "Regra: o sinal de €3.00 NÃO é reembolsado."
  - O split interno €0,50 Bora / €2,50 barbearia NÃO é exposto ao cliente
    (Fresha/Booksy também não expõem; é detalhe de settlement).
- **Zero lógica financeira nova**: o cancel continua a ser SÓ a RPC
  `client_cancel_appointment` existente (server-side decide refund/retenção).

### 2.3 `admin_appointments_screen.dart` — visão "por cliente" (missão item 5)
Campo de busca "Buscar cliente (nome ou telefone)" (PT-BR) acima dos filtros
existentes, com botão limpar; filtro local sobre `clientName`/`clientPhone`.
Resto do ecrã intocado.

## 3. Lembretes (missão item 4) — VERIFICADOS, nada a duplicar
Os 4 crons `appt-*` existem e estão `active=true` no pg_cron (verificado por SQL
nesta sessão). O `_appointment_cron_send_reminders_24h` contém push ao cliente.
**Não criei nada novo.** Nota: o lembrete 2h corre a cada 30min; o de 24h corre 1×/dia
às 10:00 UTC — marcações feitas <24h antes podem receber só o lembrete de 2h
(comportamento herdado das reservas; aceitável, registado).

## 4. Fluxo completo de teste (checklist T — device, build novo)

**T1 — Ver marcações (o gap):**
1. Login cliente → Perfil → "As minhas marcações" → vê a marcação real de €3
   (Barbearia Nobre) na tab Próximas, com preço e "Sinal €3.00 pago".
2. Home → Serviços → ícone no canto superior direito → mesmo ecrã. ✅
3. Tocar no card → bottom sheet com TODOS os detalhes (serviço, profissional,
   data/hora, duração, preço, sinal, estado).

**T2 — Cancelar >24h (refund total):**
1. Marcar (ou usar marcação) com data >24h no futuro.
2. Cancelar → modal mostra "reembolso TOTAL do sinal de €3.00" → confirmar.
3. Esperado: snackbar "Reembolso a caminho", marcação move para tab Canceladas,
   refund Stripe do sinal chega em 5–10 dias (mecanismo server-side existente).
4. Admin: marcação aparece cancelada; buscar pelo nome do cliente funciona.

**T3 — Cancelar <24h (sinal retido):**
1. Marcação com data <24h → Cancelar → modal mostra "NÃO é reembolsado" a vermelho.
2. Confirmar → cancelada SEM refund (€0,50 Bora / €2,50 barbearia via ledger,
   já implementado server-side).

**T4 — Lembretes:** com marcação amanhã, push "lembrete" chega às 10h UTC (24h)
e ~2h antes (cron 30min). Sem ação minha — só observar.

## 5. O que NÃO mudou
- RPCs, RLS, crons, Edge Functions, Stripe, ledger: **zero alterações**.
- `booking_flow`/`booking_success`: intocados.
- versionCode: intocado (CI auto-bumpa).

## 6. Validação
- `flutter analyze`: 0 erros (ver resumo da sessão; issues pré-existentes noutros ficheiros).
- Commits + push: ver hashes no resumo da sessão.
- Nota de contexto: o CI do push anterior (sessão FSI, run 27330519274) compila
  build ≥278 — este push gera o build seguinte com AMBAS as sessões.
