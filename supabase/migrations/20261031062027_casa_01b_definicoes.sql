-- Casa & Manutenção — parte 1b: definições (categoria 'casa' em platform_settings).
-- Valores de dinheiro (comissão, promoção dos primeiros, preços do catálogo) nascem como PROPOSTA:
-- o servidor só os usa em pedidos reais depois de casa_valores_autorizados.autorizado = true,
-- que só muda pela função admin_casa_autorizar_valores com o texto do "autorizo" do Danilo.
-- Cartão e MB Way na Casa ficam fora desta missão (proposta à parte): não há chave para eles aqui.
INSERT INTO public.platform_settings (key, value, description, category, is_secret) VALUES
  ('casa_enabled', 'false'::jsonb, 'Interruptor geral da categoria Casa. Nasce DESLIGADO.', 'casa', false),
  ('casa_testadores', '[]'::jsonb, 'Utilizadores (uuid) que veem a Casa com o interruptor desligado, para provas.', 'casa', false),
  ('casa_valores_autorizados', '{"autorizado": false, "em": null, "texto": null, "por": null}'::jsonb, 'Preços do catálogo, comissão e promoção só valem com o autorizo datado do Danilo. Qualquer mudança desses valores volta a pôr false.', 'casa', false),
  ('casa_bora_pct', '15'::jsonb, 'PROPOSTA: percentagem do Bora sobre o serviço, só em serviço concluído.', 'casa', false),
  ('casa_promo_primeiros_n', '5'::jsonb, 'PROPOSTA: quantos primeiros profissionais aprovados ficam sem percentagem do Bora.', 'casa', false),
  ('casa_promo_meses', '2'::jsonb, 'PROPOSTA: meses sem percentagem do Bora para os primeiros profissionais.', 'casa', false),
  ('casa_offer_timeout_min', '15'::jsonb, 'Minutos que cada profissional tem para aceitar uma oferta de preço fixo.', 'casa', false),
  ('casa_offer_rondas', '2'::jsonb, 'Quantas voltas a rotação dá à lista de profissionais antes de expirar.', 'casa', false),
  ('casa_quote_max_pros', '3'::jsonb, 'Máximo de orçamentos por pedido.', 'casa', false),
  ('casa_quote_convidar_n', '6'::jsonb, 'Quantos profissionais são convidados a orçar (os mais perto).', 'casa', false),
  ('casa_quote_pedido_horas', '48'::jsonb, 'Horas que um pedido de orçamento espera respostas antes de expirar.', 'casa', false),
  ('casa_quote_validade_horas', '72'::jsonb, 'Horas que um orçamento enviado é válido.', 'casa', false),
  ('casa_min_lead_hours', '2'::jsonb, 'Antecedência mínima da marcação, em horas.', 'casa', false),
  ('casa_cancel_free_hours', '12'::jsonb, 'POR DECIDIR: cancelamento grátis até estas horas antes.', 'casa', false),
  ('casa_cancel_half_hours', '2'::jsonb, 'POR DECIDIR: entre isto e o grátis paga metade; abaixo disto paga tudo.', 'casa', false),
  ('casa_auto_confirm_hours', '24'::jsonb, 'Horas depois de concluído em que o trabalho fica confirmado se o cliente não responder.', 'casa', false),
  ('casa_garantia_dias', '7'::jsonb, 'POR DECIDIR: dias para o cliente pedir para refazer.', 'casa', false),
  ('casa_stuck_after_hours', '6'::jsonb, 'Horas em curso sem concluir que geram alerta ao admin.', 'casa', false),
  ('casa_max_fotos', '5'::jsonb, 'Máximo de fotos do problema por pedido.', 'casa', false),
  ('casa_lembrete_confirmar_horas', '6'::jsonb, 'Horas depois de concluído em que o cliente recebe lembrete para confirmar.', 'casa', false)
ON CONFLICT (key) DO NOTHING;