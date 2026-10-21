-- Bloco D · fechar-pendencias-2026-10-20 — definicoes dos marcos do check-in (painel admin).
-- Tudo com o prefixo checkin_marco_. Valores do Danilo (20/10/2026). O interruptor geral
-- nasce DESLIGADO: liga-se depois de a versao da app com "Os meus premios" estar nas 3 lojas.
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('checkin_marco_ativo', 'false'::jsonb,
   'Marcos do check-in ligados (vales aos 10, 15 e 30 dias seguidos). Ligar só depois de publicar a app nas 3.', 'marketing'),
  ('checkin_marco_ciclo_dias', '30'::jsonb,
   'Tamanho do ciclo dos marcos: depois deste dia a sequência dos marcos recomeça no dia 1.', 'marketing'),
  ('checkin_marco_validade_dias', '30'::jsonb,
   'Validade de cada vale dos marcos, em dias, a contar de quando fica disponível.', 'marketing'),
  ('checkin_marco_tecto_ativo', 'true'::jsonb,
   'Tecto mensal dos vales de 30 dias ligado (quem chega depois fica com o vale guardado para o mês seguinte).', 'marketing'),
  ('checkin_marco_tecto_mensal', '10'::jsonb,
   'Máximo de vales de 30 dias disponibilizados por mês (hora de Lisboa).', 'marketing'),
  ('checkin_marco_exige_pedido_pago', 'true'::jsonb,
   'O vale de 30 dias exige pelo menos 1 pedido pago nos últimos dias (regra tipo Uber One / Glovo Prime).', 'marketing'),
  ('checkin_marco_pedido_pago_dias', '30'::jsonb,
   'Janela, em dias, do pedido pago exigido pelo vale de 30 dias.', 'marketing'),
  ('checkin_marco_espera_pedido_dias', '30'::jsonb,
   'Quantos dias o vale de 30 dias espera pelo pedido pago antes de expirar.', 'marketing'),
  ('checkin_marco_lembrete_dias', '3'::jsonb,
   'Os lembretes das 11h e das 20h dizem quantos dias faltam para o próximo marco quando faltam até este número.', 'marketing'),
  ('checkin_marco_texto', to_jsonb('Faz o check-in todos os dias. Aos 10 dias seguidos ganhas 2 salgados da Keli (pagas só a entrega e as taxas). Aos 15, um açaí do Goola. Aos 30, escolhes 2 horas de limpeza ou uma lavagem exterior do carro.'::text),
   'Texto da vista do mês dos marcos (app do cliente, PT-PT).', 'marketing'),
  ('checkin_marco_semana', jsonb_build_object(
     'chave','semana','ativo',true,'dia',7,'tipo','tokens','titulo','os tokens do Dia 7',
     'descricao','Ao 7.º dia seguido ganhas os tokens do Dia 7.'),
   'Marco dos 7 dias: só se mostra (são os tokens do Dia 7 que já existem).', 'marketing'),
  ('checkin_marco_salgados', jsonb_build_object(
     'chave','salgados','ativo',true,'dia',10,'tipo','produto','titulo','2 salgados da Keli',
     'descricao','Na Sabores do Brasil: 2 salgados grandes, coxinha ou esfirra à escolha. Pagas só a entrega e as taxas.',
     'loja_id','sabores-brasil-guarda','produto_id','premio-checkin-salgados','quantidade',1,
     'valor_cents',630,'custo_cents',540),
   'Marco dos 10 dias: 2 Salgados Grandes da Sabores do Brasil. valor = preço na app; custo = o que a loja recebe (venda normal).', 'marketing'),
  ('checkin_marco_acai', jsonb_build_object(
     'chave','acai','ativo',true,'dia',15,'tipo','produto','titulo','um açaí do Goola',
     'descricao','No Goola Açaí: um Goola Bowl com 3 acompanhamentos à escolha. Pagas só a entrega e as taxas.',
     'loja_id','goola-acai-guarda','produto_id','premio-checkin-acai','quantidade',1,
     'valor_cents',922,'custo_cents',790),
   'Marco dos 15 dias: o açaí mais barato do Goola (Goola Bowl). valor = preço na app; custo = preço de balcão.', 'marketing'),
  ('checkin_marco_mes', jsonb_build_object(
     'chave','mes','ativo',true,'dia',30,'tipo','servico',
     'titulo','2 horas de limpeza ou uma lavagem exterior do carro',
     'descricao','Escolhes: 2 horas de limpeza em casa ou uma lavagem do carro só por fora.',
     'opcoes',jsonb_build_array('limpeza','lavagem'),'limpeza_horas',2),
   'Marco dos 30 dias: o cliente escolhe 2 h de limpeza ou lavagem exterior. O prestador recebe o ganho normal.', 'marketing')
ON CONFLICT (key) DO NOTHING;
