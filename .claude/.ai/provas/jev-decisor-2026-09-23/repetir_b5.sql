-- jev-decisor-2026-09-23 · Bloco 5 — repetir as 20 provas reais (correr no SQL da produção).
-- Troca :motor por 'jev' ou 'gemini' e :ronda por 'prova-b5r2' (ou outra etiqueta).
-- Os estados saem da base já anonimizados (telefones/emails mascarados no suporte).

-- (1) 10 sugestões do Robot B (5 aplicadas, 5 rejeitadas) — noul "vale a pena abrir?"
with c as (select (select decrypted_secret from vault.decrypted_secrets where name='project_url') || '/functions/v1/decidir' u,
  jsonb_build_object('Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key'),'Content-Type','application/json') h),
rb as (
  (select s.id from robot_suggestions s where s.status in ('aplicada','aprovada') order by s.created_at desc limit 5)
  union all
  (select s.id from robot_suggestions s where s.status='rejeitada' order by s.created_at desc limit 5)
)
select net.http_post(c.u, jsonb_build_object(
    'pergunta_tipo','noul','usado_por',:ronda || '-robotb','modo','teste','motor',:motor,'contexto_id', s.id::text,
    'pergunta','Is this automatic suggestion worth the owner''s attention (real, actionable and not a repeat)? Use the history of how the owner handled this category.',
    'criterios', jsonb_build_object('true','Worth opening: real problem, actionable, owner usually acts on this kind','false','Not worth it: noise, repeat, or the owner usually rejects or ignores this kind'),
    'estado', jsonb_build_object('titulo', s.titulo, 'categoria', s.categoria, 'nivel', s.nivel, 'severidade', s.severidade,
       'proposta', left(coalesce(s.proposta,''),1200), 'evidencia', left(coalesce(s.evidencia::text,''),1500),
       'historico_da_categoria', (select jsonb_build_object('aplicadas', count(*) filter (where h.status in ('aplicada','aprovada','aprovada-emerson')),
            'rejeitadas', count(*) filter (where h.status='rejeitada'), 'expiradas_sem_resposta', count(*) filter (where h.status='expirada'))
          from robot_suggestions h where h.categoria=s.categoria and h.id<>s.id and h.created_at < s.created_at))),
  '{}'::jsonb, c.h, 60000)
from rb join robot_suggestions s on s.id=rb.id, c;

-- (2) 4 marcações com desfecho (score de falta) + 6 conversas de suporte (noul "passar a humano?")
with c as (select (select decrypted_secret from vault.decrypted_secrets where name='project_url') || '/functions/v1/decidir' u,
  jsonb_build_object('Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key'),'Content-Type','application/json') h),
ap as (
  select jsonb_build_object('pergunta_tipo','score','usado_por',:ronda || '-noshow','modo','teste','motor',:motor,'contexto_id',a.id::text,
      'pergunta','How likely is this client NOT to show up for this booked appointment?',
      'escala', '["Very low risk","Low risk","Medium risk","High risk","Very high risk"]'::jsonb,
      'estado', jsonb_build_object('horas_ate_marcacao', round(extract(epoch from (a.scheduled_at - a.created_at))/3600.0,1),
        'dia_semana', to_char(a.scheduled_at at time zone 'Europe/Lisbon','FMDay'), 'hora_local', to_char(a.scheduled_at at time zone 'Europe/Lisbon','HH24:MI'),
        'preco_servico_eur', round(coalesce(a.service_price_cents,0)/100.0,2), 'sinal_pago', coalesce(a.deposit_status,'sem_sinal'),
        'metodo_pagamento', a.full_payment_method, 'remarcacoes', coalesce(a.reschedule_count,0), 'deixou_notas', coalesce(a.client_notes,'')<>'')) b
  from appointments a where a.status in ('no_show','completed','cancelled') and not coalesce(a.is_walk_in,false)
),
ses as (
  (select s.id from support_chatbot_sessions s where s.messages_count>0 and (s.escalated or exists(select 1 from support_escalations e where e.session_id=s.id)) order by s.started_at desc limit 4)
  union all
  (select s.id from support_chatbot_sessions s where s.messages_count>0 and not s.escalated and not exists(select 1 from support_escalations e where e.session_id=s.id) order by s.started_at desc limit 2)
),
sup as (
  select jsonb_build_object('pergunta_tipo','noul','usado_por',:ronda || '-suporte','modo','teste','motor',:motor,'contexto_id',m.id::text,
    'pergunta','Should this support conversation be handed to a human now?',
    'criterios', jsonb_build_object('true','Hand to a human: dispute, money/refund, legal or privacy, anger, safety, or the bot is failing','false','The bot can keep answering'),
    'estado', jsonb_build_object('papel_utilizador', se.user_role, 'tem_pedido_associado', se.order_id is not null,
       'mensagem', regexp_replace(regexp_replace(left(coalesce(m.content,''),1500), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+', '[email]', 'g'), '\+?\d[\d ]{7,}\d', '[telefone]', 'g'))) b
  from ses join support_chatbot_sessions se on se.id=ses.id
  join lateral (select * from support_chatbot_messages mm where mm.session_id=se.id and mm.role='user' order by mm.created_at limit 1) m on true
)
select net.http_post(c.u, t.b, '{}'::jsonb, c.h, 60000) from (select b from ap union all select b from sup) t, c;
