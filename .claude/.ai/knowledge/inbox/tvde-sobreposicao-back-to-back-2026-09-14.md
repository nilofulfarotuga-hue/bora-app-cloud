---
id: tvde-sobreposicao-back-to-back-2026-09-14
tipo: handoff
origem: Claude Code (Opus 5), missão tvde-sobreposicao-back-to-back
data: 2026-09-14
zona: amarela
estado: para o bibliotecário
---

# Handoff — sobreposição de corridas TVDE (back-to-back, à Uber)

**Regra nova (ordem do Danilo, 14/09):** um motorista a meio de uma corrida também recebe ofertas
TVDE; a nova entra em fila atrás da que ele leva e abre sozinha quando termina. O ocupado entra na
MESMA rotação dos livres (prioridade 2, depois dos livres por distância); se recusar/expirar a roda
segue e pode voltar ao livre. Ficar offline é a forma de deixar de receber (como na Uber). TVDE
activo continua a bloquear ENTREGAS (regra cruzada de 02/07 não mudou; dispatch-engine intacto).

**Onde vive:** `tvde_offer_to_next` (pool único), `tvde_accept_ride` (fila com qualquer activa +
guarda `ride_conflict`), `tvde_cancel_ride` (largar só a fila não promove outra),
`admin_tvde_reassign_ride`, `tvde_ride_queue_info`; settings `tvde_backtoback_enabled` (true),
`tvde_backtoback_max_queue` (1), `tvde_backtoback_min_stage` (motorista_a_caminho),
`tvde_queue_pickup_radius_km` (5). Edge notify-tvde-driver v16 (kinds queued_added / ride_assigned /
ride_reassigned_away → type tvde_queue_update). Migrations 20260914150204 e 20260914151041.

**Lições (confirmadas com saída literal):**
1. A Edge notify-tvde-driver RE-ANCORA `offer_expires_at` para +40 s depois do push. Um teste em
   produção com oferta sintética "de 10 minutos" dura 40 s e, com a pausa de 35 s do sweep, a
   corrida foge para um motorista REAL (aconteceu ao Valdemir às 16:51, cancelada aos 37 s).
   Com motoristas reais online, pedido sintético só sem passar pela oferta.
2. Race no app do motorista: a promoção da fila podia chegar pelo realtime antes de a RPC
   `tvde_finish_ride` responder e o store escrevia a finalizada por cima da promovida — corrigido
   com `_reloadActiveAfterTerminal` (relê sempre do servidor, nunca deixa a corrida a null).
3. Provas em rollback: `now()` constante na transacção; `net.http_request_queue.body` é bytea;
   `_admin_op_guard` lê `app_metadata.role` do JWT; motoristas reais online entram na roda do teste.

Relatório: `.claude/.ai/reports/tvde-sobreposicao-2026-09-14.md`. Provas: `.claude/.ai/provas/tvde-sobreposicao-2026-09-14/`.
