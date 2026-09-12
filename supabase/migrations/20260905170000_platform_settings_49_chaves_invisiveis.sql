-- ============================================================================
-- AS 49 CHAVES QUE NAO APARECIAM NO PAINEL
-- 2026-09-05
-- ----------------------------------------------------------------------------
-- Uma chave de platform_settings sem categoria nao e' mostrada no painel admin:
-- o ecra agrupa por categoria e o que nao tem categoria nao entra em grupo
-- nenhum. Havia 49 assim, de 247. Ou seja: o Danilo nem sabia que existiam.
--
-- Destas 49, treze mexem em DINHEIRO (carteira, taxas de cancelamento, tokens).
-- Decisao do Danilo nesta missao:
--   - as 36 operacionais ficam VISIVEIS e EDITAVEIS no painel;
--   - as 13 de dinheiro ficam VISIVEIS para ele poder ver e auditar, mas NAO
--     entram na whitelist de editaveis. Ver e' uma coisa; mudar por engano num
--     toque e' outra. O rotulo delas comeca por "DINHEIRO." de proposito.
--
-- ESTA MIGRATION NAO ALTERA NENHUM VALOR. So mexe em `category` e, quando
-- estava vazia, em `description`. Nenhum preco, taxa, comissao ou limite mudou.
--
-- A whitelist de editaveis vive no codigo, em
-- lib/screens/admin/admin_platform_settings_screen.dart (_isEditable).
-- ============================================================================

UPDATE platform_settings s
SET category = v.cat,
    description = COALESCE(NULLIF(btrim(s.description), ''), v.rotulo)
FROM (VALUES
 -- ── OPERACIONAIS (36) ────────────────────────────────────────────────────
 ('appointment_reschedule_max_count','appointments','Quantas vezes o cliente pode remarcar a mesma marcacao.'),
 ('appointment_reschedule_max_days','appointments','Ate quantos dias a frente o cliente pode empurrar uma marcacao.'),
 ('appointment_reschedule_min_hours','appointments','Quantas horas antes da marcacao ainda se pode remarcar.'),
 ('cancel_grace_seconds','fees','Janela em segundos logo apos o pedido em que cancelar nao custa nada.'),
 ('carwash_retry_lead_hours','carwash','Antecedencia minima, em horas, para reoferecer uma lavagem que ninguem aceitou.'),
 ('carwash_retry_window_hours','carwash','Durante quantas horas se continua a procurar quem lave o carro.'),
 ('carwash_stuck_after_hours','carwash','Ao fim de quantas horas uma lavagem parada e marcada como encravada para o admin ver.'),
 ('delivery_max_distance_km','delivery','Distancia maxima de entrega. Acima disto o pedido e recusado logo na criacao.'),
 ('discovery_filters','delivery','Que filtros aparecem ao cliente a procurar lojas (vegetariano, sem gluten, aberto agora).'),
 ('dispatch_auto_cancel_safety_seconds','dispatch','Rede de seguranca: ao fim de quantos segundos um pedido sem motorista se cancela sozinho.'),
 ('dispatch_max_total_seconds_with_drivers_online','dispatch','Quanto tempo se insiste a procurar quando ha estafetas online.'),
 ('dispatch_offer_timeout_seconds','dispatch','Quantos segundos o estafeta tem para aceitar antes de a oferta passar ao seguinte.'),
 ('dispatch_partner_confirm_extension_seconds','dispatch','Tempo extra dado quando o parceiro ainda esta a confirmar o pedido.'),
 ('dispatch_retry_no_driver_seconds','dispatch','De quantos em quantos segundos se volta a tentar quando nao havia ninguem.'),
 ('oferta_sem_aparelho_min','dispatch','Minutos que uma oferta espera por um estafeta sem aparelho ligado.'),
 ('reservation_default_slot_duration_minutes','reservations','Duracao normal de um turno de mesa, em minutos.'),
 ('reservation_default_turn_time_2','reservations','Tempo previsto a mesa para 2 pessoas, em minutos.'),
 ('reservation_default_turn_time_4','reservations','Tempo previsto a mesa para 4 pessoas, em minutos.'),
 ('reservation_default_turn_time_6_plus','reservations','Tempo previsto a mesa para 6 ou mais pessoas, em minutos.'),
 ('reservation_default_walk_in_pct','reservations','Percentagem de lugares guardados para quem chega sem reserva.'),
 ('reservation_late_cancel_threshold_count','reservations','Quantos cancelamentos em cima da hora ate o cliente ser sinalizado.'),
 ('reservation_max_advance_days','reservations','Com quantos dias de antecedencia se pode reservar mesa.'),
 ('reservation_min_advance_minutes','reservations','Antecedencia minima, em minutos, para reservar mesa.'),
 ('reservation_no_show_threshold_count','reservations','Quantas faltas ate o cliente ser sinalizado.'),
 ('reservation_notify_list_expiry_hours','reservations','Quantas horas dura um aviso de mesa vaga antes de passar ao seguinte.'),
 ('reservation_reminder_24h_enabled','reservations','Ligar ou desligar o lembrete de reserva 24 horas antes.'),
 ('reservation_reminder_2h_enabled','reservations','Ligar ou desligar o lembrete de reserva 2 horas antes.'),
 ('reservation_waitlist_expiry_hours','reservations','Quantas horas alguem fica em lista de espera antes de sair dela.'),
 ('robot_b_max_open_suggestions','robot','Quantas sugestoes o robo pode ter em aberto ao mesmo tempo na Central.'),
 ('robot_consumer_cutoff_at','robot','Data a partir da qual o robo passa a considerar as conversas. Nao mexer sem saber.'),
 ('tvde_reservation_eta_kmh','tvde','Velocidade media usada para calcular o tempo ate a recolha numa corrida marcada.'),
 ('tvde_reservation_lock_margin_minutes','tvde','Margem em minutos ao prender o motorista a uma corrida marcada.'),
 ('tvde_reservation_lock_max_minutes','tvde','Tempo maximo, em minutos, que um motorista fica preso a uma corrida marcada.'),
 ('tvde_reservation_lock_min_minutes','tvde','Tempo minimo, em minutos, que um motorista fica preso a uma corrida marcada.'),
 ('tvde_reservation_position_max_age_min','tvde','Ate quantos minutos a posicao do motorista ainda conta para uma corrida marcada.'),
 ('tvde_reservation_road_factor_x100','tvde','Quanto a estrada real e mais longa que a linha recta (135 = mais 35 por cento).'),
 -- ── DINHEIRO (13) — visiveis, mas NAO entram na whitelist de editaveis ────
 ('cancel_fee_after_accept_cents','fees','DINHEIRO. Quanto o cliente paga se cancelar depois de o estafeta aceitar.'),
 ('cancel_fee_after_accept_driver_cents','fees','DINHEIRO. Quanto o estafeta recebe quando o cliente cancela depois de ele aceitar.'),
 ('cancel_fee_after_pickup_ratio','fees','DINHEIRO. Que fatia do pedido fica retida se o cliente cancelar depois da recolha (1.00 = tudo).'),
 ('cancel_fee_before_dispatch_cents','fees','DINHEIRO. Quanto custa cancelar antes de se comecar a procurar estafeta.'),
 ('max_extra_charge_cents','fees','DINHEIRO. Tecto do acerto que se pode cobrar a mais depois da entrega.'),
 ('token_payment_max_pct','tokens','DINHEIRO. Percentagem maxima do pedido que se pode pagar com Bora Tokens.'),
 ('token_withdrawal_max_pct_weekly','tokens','DINHEIRO. Percentagem maxima dos tokens que o estafeta pode levantar por semana.'),
 ('wallet_cancel_hard_floor_cents','wallet','DINHEIRO. Fundo do poco da carteira para cancelamentos (valor negativo).'),
 ('wallet_hard_floor_cents','wallet','DINHEIRO. Fundo do poco da carteira do cliente. Espelha a trava da propria base.'),
 ('wallet_max_negative_balance_cents','wallet','DINHEIRO. A partir deste saldo negativo o cliente deixa de poder fazer pedidos.'),
 ('wallet_negative_action_days','wallet','DINHEIRO. Dias com saldo negativo parado ate exigir accao.'),
 ('wallet_negative_alert_days','wallet','DINHEIRO. Dias com saldo negativo parado ate avisar o admin.'),
 ('wallet_negative_enabled','wallet','DINHEIRO. Interruptor geral do saldo negativo. Desligar volta ao comportamento antigo.')
) AS v(k, cat, rotulo)
WHERE s.key = v.k AND (s.category IS NULL OR s.category = '');
