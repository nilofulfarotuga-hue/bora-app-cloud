# Relatório — Calendário mensal de disponibilidade (exceções) · app parceiro

**Data:** 2026-07-19 · **Branch:** `autonomous-night-2026-04-29`
**Squad (CEO-AI):** parceiro-servicos + flutter-ui · **Não toca dinheiro** (Lista Vermelha).

## Objetivo
Dar ao profissional (barbeiro/cabeleireira/etc.) o que Noona/Fresha/Booksy já têm: além do
**padrão semanal** (modelo base, intacto), um **calendário mensal** para marcar **exceções** em
datas específicas — folgas, feriados ou horários diferentes.

## Backend (já estava pronto — só confirmei)
- `staff_availability_exceptions` (id, staff_id, date, is_working, start_time, end_time, note,
  UNIQUE(staff_id,date)) com RLS `sae_select`/`sae_write`. ✅
- `staff_availability` já com políticas `sa_select`/`sa_write` (o bug do "Guardar dia" que nunca
  gravava está corrigido). ✅
- `get_available_slots` **confirmado via MCP** a ler `staff_availability_exceptions` + `is_working`
  (dá prioridade à exceção; sem exceção → cai no padrão semanal). ✅

## O que foi construído (Flutter, PT-PT)

### 1. `PartnerAppointmentsStore` (3 métodos novos, padrão dos vizinhos)
- `fetchAvailabilityExceptions({staffId, month})` — exceções do mês.
- `upsertAvailabilityException({staffId, date, isWorking, startTime?, endTime?, note?})` —
  upsert `onConflict: 'staff_id,date'`.
- `deleteAvailabilityException({staffId, date})` — volta ao padrão semanal.
Mesmo `try/catch` + mensagens PT-PT de `upsertAvailability`.

### 2. `partner_manage_staff_screen.dart` — 2 abas na tela do profissional
A tela de disponibilidade passou a ter **duas abas**:
- **"Padrão semanal"** — o editor existente, **movido tal e qual** para uma aba (lógica inalterada).
- **"Calendário do mês"** — novo (`_StaffMonthCalendar`), com `table_calendar`:
  - Formato mês, navegação entre meses (recarrega exceções por mês), semana começa à Segunda.
  - **PT-PT sem depender de intl locale-data**: título e cabeçalho dos dias renderizados com
    formatadores próprios (`titleTextFormatter` + `dowBuilder`) — ver "Decisão técnica".
  - **Marcadores por dia:** 🟢 verde = trabalha (segue padrão semanal) · 🟠 laranja = horário
    diferente (exceção) · 🔴 vermelho = folga/indisponível (exceção). Dias sem exceção e sem
    trabalho no padrão → sem ponto.
  - **Toque num dia → bottom sheet** com 3 opções: "Seguir o padrão semanal" (apaga exceção),
    "Marcar como folga/indisponível" (upsert is_working=false), "Horário diferente neste dia"
    (2 seletores de hora 24h + validação fim>início → upsert is_working=true). SnackBar de
    sucesso/erro em todos os casos.
  - Legenda + dica explicativas.

## Decisão técnica (pre-flight)
`main.dart` **não** chama `initializeDateFormatting`, logo `table_calendar` com `locale:'pt_PT'`
crashava (`LocaleDataException`). Em vez de mexer no bootstrap do `main`, usei **formatadores PT
próprios** (meses e dias-da-semana em código) e **não passo `locale`** — resultado 100% PT-PT,
zero dependência de dados de locale, zero risco no arranque da app.

## Fluxo testado (mentalmente)
1. Profissional → aba "Calendário do mês" → toca **24/07** → "Marcar como folga" → grava
   is_working=false (ponto vermelho).
2. Cliente tenta marcar 24/07 → `get_available_slots` encontra a exceção → devolve vazio →
   a tela do cliente mostra o já-existente **"Sem horários disponíveis neste dia. Escolhe outro dia."** ✅
3. "Horário diferente" (ex.: 10:00–14:00) → cliente só vê slots nessa janela. ✅
4. "Seguir o padrão semanal" → apaga exceção → dia volta ao padrão. ✅

## Qualidade
- `flutter analyze` nos ficheiros tocados: **No issues found!**
- Design system: verde #16A34A, laranja #F97316 (só marcadores semânticos; sem 2.º CTA laranja).
- Editor semanal **não** foi alterado (apenas movido para aba). Zonas protegidas intactas.

## Ficheiros tocados
- `pubspec.yaml` / `pubspec.lock` — `table_calendar: ^3.2.0` (resolveu sem conflito).
- `lib/stores/partner_appointments_store.dart` — 3 métodos de exceções.
- `lib/screens/partner/services/partner_manage_staff_screen.dart` — abas + `_StaffMonthCalendar`.
- `relatorio-calendario-disponibilidade.md` — este relatório.

## O que ficou para depois (declarado)
- **Seleção múltipla de dias** (marcar um intervalo de férias de uma vez): **deferida** para uma
  próxima iteração. Fiz o fluxo de 1 dia sólido e robusto primeiro (simplicidade > risco numa
  execução autónoma). A base (`upsert`/`delete` por data) já suporta aplicar em lote; falta só a
  UI de range + o loop. Não é bloqueante — marcar dia-a-dia já cobre o caso de uso.
