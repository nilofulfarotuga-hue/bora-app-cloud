# Handoff para o bibliotecario-cerebro — reservas-num-so-sitio (10/10/2026)

Origem: Claude Code, missão reservas-num-so-sitio-2026-10-10, commits 4d0b1c3c e 58c57a5f.
Relatório: `.claude/.ai/reports/reservas-num-so-sitio-2026-10-10.md`.

## Factos confirmados (para o Cérebro)

1. O separador "Reserva" do cliente junta 4 tipos — mesas (`reservations`), corridas
   marcadas (`tvde_rides` com `scheduled_at`), limpezas (`cleaning_bookings`) e marcações
   (`appointments`). A regra de agrupamento vive só em `lib/utils/minhas_reservas.dart`
   (`juntarReservas`), usada pelo app e pelo painel admin. estado: atual.
2. Corrida marcada continua em "Próximas" depois de passar a `motorista_atribuido` /
   `motorista_a_caminho` / `motorista_chegou` / `em_andamento`; só sai quando acaba.
   Confirmado ao vivo: a reserva 6f89ef6a passou a motorista_a_caminho às 03:48 UTC (20 min
   antes das 04:00). estado: atual.
3. `cleaning_bookings.payment_status` aceita só: unpaid, held, released, estornado,
   cash_pending, cash_settled (CHECK lido a 10/10). "Pago" para o cliente = held ou released.
4. `CleaningStore.loadMyBookings` e `TvdeStore.loadMyReservations` engoliam o erro; agora
   expõem `myBookingsFailed` / `myReservationsFailed`.
5. iOS CI: uma versão em `READY_FOR_REVIEW` (submissão aberta não enviada) bloqueia criar a
   versão seguinte (409). `ios_publicar.py` reaproveita-a desde 58c57a5f.
6. Admin não tem leitura direta de `cleaning_bookings` (RLS só dono/profissional): passa pela
   RPC `admin_list_cleanings(p_search)`.

## Lição

Provar um ecrã com dados de todos os tipos sem escrever em produção: interceção das leituras
REST no Playwright (web) e integration_test com stores falsos (Android). Ver memória
`prova-de-ecra-sem-escrever-no-banco`.

## Telemetria de skills (linha para `wiki/skills-metrics.md`)

| ceo-ai | 2026-10-10 | missão reservas-num-so-sitio | 1 missão, 3 plataformas | sucesso |
