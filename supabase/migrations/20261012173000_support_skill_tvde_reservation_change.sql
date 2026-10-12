-- =============================================================================
-- Robô de suporte (support-chatbot v28) — skill TVDE_RESERVATION_CHANGE
-- 2026-10-12 (missão reserva-tvde-robo). O robô passa a conhecer as reservas de
-- corrida (Bora Motorista / TVDE): lista-as, muda a HORA sozinho (sem aprovação
-- manual — regra do Danilo de 12/10) e, quando a mudança de DESTINO estiver no
-- ar (Bloco 2, atrás do interruptor tvde_reservation_dest_change_enabled),
-- também o destino. Playbook curto; as regras de dinheiro vivem no servidor.
-- Dados (não DDL): idempotente por skill_name.
-- =============================================================================

INSERT INTO public.support_skills
  (skill_name, version, category, mode, requires_human_handoff, playbook_md, allowed_tools, examples, active)
VALUES (
  'TVDE_RESERVATION_CHANGE', 1, 'reservations', 'read_only', false,
$md$
## TVDE_RESERVATION_CHANGE

Quando activar: o cliente quer MUDAR A HORA ou o DESTINO de uma CORRIDA MARCADA para depois
(reserva de corrida, "Bora Motorista", TVDE, "o carro", "a boleia", "a viagem marcada").
NAO confundir com RESERVA DE MESA (restaurante) — isso e a skill RESERVATION_CANCEL / FAQ.

Tools: agent_get_my_tvde_reservations(), tvde_reservation_reschedule(p_ride, p_nova_hora_local),
tvde_reservation_dest_quote(p_ride, p_morada), tvde_reservation_change_dest(...).

### Mudar a HORA (faz sozinho, sem aprovacao de ninguem)
1. Chama SEMPRE primeiro agent_get_my_tvde_reservations. Sem reservas -> diz que nao tem
   corridas marcadas e que pode marcar em "Bora Motorista" > "Marcar para depois".
2. Uma so reserva -> confirma-a numa frase (dia, hora e destino). Varias -> pergunta qual.
3. Pergunta a hora nova (dia e hora, hora de Portugal). Se o cliente so disser a hora, e o
   mesmo dia da reserva. "Daqui a 15 min" conta-se a partir da hora marcada, nao de agora.
4. Chama tvde_reservation_reschedule com p_nova_hora_local no formato 'AAAA-MM-DD HH:MM'.
   NUNCA pedes aprovacao nem dizes "aguarda aprovacao": a mudanca aplica-se ja.
5. Responde com a hora final e com o motorista: motorista_mantem=true -> "o teu motorista
   mantem-se"; false -> "vamos procurar motorista para a hora nova, recebes aviso".

### Mudar o DESTINO (so quando a tool nao devolver reservation_dest_change_disabled)
1. Lista e confirma a reserva como acima. Pergunta a morada nova por extenso.
2. Chama tvde_reservation_dest_quote com a morada escrita pelo cliente. NUNCA inventes
   coordenadas: a morada e as contas vem todas da tool.
3. Confirma com o cliente a MORADA ENCONTRADA (dest_label) e o preco: igual, "pagas mais X"
   ou "devolvemos X". So com o "sim" chamas tvde_reservation_change_dest com os valores
   exactos devolvidos pela cotacao (dest_lat, dest_lng, dest_label, client_diff_cents).
4. needs_payment=true -> explica que a diferenca se paga na app, em "As minhas reservas"
   (o destino so muda depois de pagar). Caso contrario diz que ja esta mudado.

### Erros -> frase simples em PT-PT
too_soon -> "Essa hora esta muito em cima, tem de ser pelo menos 30 minutos a partir de agora."
too_far -> "So dá para marcar ate 30 dias para a frente."
reservation_overlap -> "Ja tens outra reserva a menos de 30 minutos dessa hora."
too_late_to_change -> "Essa reserva ja esta em andamento ou ja acabou; ja nao da para mudar."
invalid_time -> "Nao percebi a hora. Diz-me o dia e a hora, por exemplo amanha as 17:45."
reservation_not_found / reservation_not_yours -> "Nao encontrei essa reserva na tua conta."
reservation_dest_change_disabled -> "Mudar o destino pelo chat ainda nao esta disponivel. Posso passar o pedido a equipa."
reservation_awaiting_payment -> "Essa reserva ainda esta a espera do pagamento; termina o pagamento na app primeiro."
route_failed / address_not_found -> "Nao consegui encontrar essa morada. Podes escrever a rua, o numero e a localidade?"
Outro erro -> pede desculpa, nao inventes, e oferece passar a equipa.
$md$,
  '["agent_get_my_tvde_reservations","tvde_reservation_reschedule","tvde_reservation_dest_quote","tvde_reservation_change_dest"]'::jsonb,
  '[{"user":"quero mudar a hora da minha corrida de amanha para as 17:45","assistant":"Tens uma corrida marcada para amanha as 17:30, de Avenida X para Y. Passo-a para as 17:45?"},{"user":"sim","assistant":"Feito: a tua corrida fica marcada para amanha as 17:45. O teu motorista mantem-se."}]'::jsonb,
  true
)
ON CONFLICT (skill_name) DO UPDATE
  SET version = support_skills.version + 1,
      category = EXCLUDED.category,
      mode = EXCLUDED.mode,
      requires_human_handoff = EXCLUDED.requires_human_handoff,
      playbook_md = EXCLUDED.playbook_md,
      allowed_tools = EXCLUDED.allowed_tools,
      examples = EXCLUDED.examples,
      active = EXCLUDED.active,
      updated_at = now();
