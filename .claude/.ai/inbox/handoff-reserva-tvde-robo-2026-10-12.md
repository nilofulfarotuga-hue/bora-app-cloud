# Handoff → bibliotecario-cerebro · missão reserva-tvde-robo-2026-10-12

Factos confirmados (estado: atual), para o Cérebro — tema TVDE / robô de suporte:

1. **O robô de suporte muda a hora das reservas de corrida sozinho** (support-chatbot v28,
   12/10/2026). Tools `agent_get_my_tvde_reservations` e `tvde_reservation_reschedule`, secção
   "RESERVAS DE CORRIDA (TVDE)" no prompt, skill `TVDE_RESERVATION_CHANGE` (support_skills,
   active). Prova: sessão c821ab81 com demo.cliente — reserva 13/10 10:00 → 11:00 por chat.
   Origem: cliente teve de ligar ao Danilo (17:30→17:45) a 12/10.
2. **Tools do robô podem ir por Edge** (`EDGE_TOOLS` → `callEdgeTool`): as de destino chamam
   `tvde-dest-change` v3 (acções `reservation_quote`/`reservation_change`, geocodificação da
   morada escrita + rota Google no servidor). Quatro sítios para uma tool nova: whitelist,
   declaração, secção no prompt, linha em support_skills.
3. **notify-tvde-driver v22**: kinds `reservation_rescheduled` ("A reserva passou para DD/MM às
   HH:MM • rota • Ganhas €X") e `reservation_rescheduled_lost` (texto verdadeiro). App do
   motorista conhece `tvde_reservation_rescheduled`. A função `tvde_reservation_reschedule`
   ainda manda os kinds antigos: a migração `20261012180000_tvde_reserva_aviso_hora_alterada.sql`
   está no repo e a bora-tranca recusou aplicá-la por MCP (corpo com UPDATE tvde_rides) —
   pedido à Claude.ai.
4. **Bloco 2 (mudar destino, dinheiro) é PROPOSTA**, em
   `.claude/.ai/missoes/reserva-tvde-robo-2026-10-12/bloco2-proposta-mudar-destino.md`, provada
   em PGlite com base falsa (`provar_bloco2_base_falsa.mjs`, saída em `provar_bloco2.saida.txt`).
   Interruptor `tvde_reservation_dest_change_enabled` ainda não existe = desligado. Precisa
   também de alteração na tvde-payment (devolução parcial `valor_cents` + guarda do
   amount_received).
5. **Achado**: repo `supabase/functions/tvde-payment/index.ts` está em v18 (04/10) e o ar em v19
   (10/10). Não se tocou.
6. **Fixture seguro de reserva TVDE**: demo.cliente + `tvde_schedule_ride(... 'card')` fica
   `aguarda_pagamento` sem chamar motoristas; cancela-se com `tvde_cancel_reservation`.
7. App cliente ("As minhas reservas") e painel admin (TVDE — Reservas) têm "Mudar hora" e
   "Mudar destino" (este só com o interruptor ligado). Commit ab056aa3.

Lições (procedural): a tranca recusa `Write` de migração com palavras de pagamento mesmo com
PROPOSTA no nome → proposta vai como relatório na pasta da missão; PGlite corre com `bun`
(o `node` do PC dá "unreachable").
