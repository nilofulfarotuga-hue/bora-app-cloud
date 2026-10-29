-- ADENDO 4 + paridade pequena (29/10/2026) — parte A.
-- Interruptores do painel (nada que mexa em valores) e colunas novas, todas
-- opcionais. As funcoes e tabelas novas vao nas partes B, C e D.

-- 1) Interruptores. ON CONFLICT DO NOTHING: nunca desfaz uma escolha do admin.
insert into public.platform_settings (key, value, description, category) values
  ('ask_cutlery', 'true'::jsonb,
   'Perguntar por talheres e guardanapos no pagamento dos restaurantes (entrega e takeaway). O interruptor do cliente nasce desligado: so vao se ele pedir.',
   'cliente'),
  ('ask_cash_change', 'true'::jsonb,
   'Perguntar "Com que nota vai pagar?" quando o cliente escolhe dinheiro. Só acrescenta uma linha na nota do pedido (TROCO PARA X €); não muda nenhum valor.',
   'cliente'),
  ('ask_address_details', 'true'::jsonb,
   'Campo "Andar, porta ou código" nas moradas guardadas do cliente. O texto vai na nota do pedido para o estafeta, a loja e o admin.',
   'cliente'),
  ('cart_add_more_strip', 'true'::jsonb,
   'Mostrar "Juntar mais" no carrinho quando falta pouco para a entrega grátis ou para o pedido mínimo (até 3 produtos mais baratos da mesma loja).',
   'cliente'),
  ('feature_barra_pedido_ativo', 'true'::jsonb,
   'Barra fixa do pedido em curso (estado e tempo estimado recalculado) nos ecrãs do cliente.',
   'cliente'),
  ('feature_foto_entrega_cliente', 'true'::jsonb,
   'O cliente vê a foto de prova da entrega no acompanhamento e no detalhe do pedido.',
   'cliente'),
  ('feature_esgotado_aviso_cliente', 'true'::jsonb,
   'Quando a loja marca um produto em falta num pedido já aceito, o cliente vê o aviso com contagem de tempo e pode pedir troca à loja pelo chat. Só aviso e contagem: não muda nenhum valor.',
   'cliente'),
  ('feature_esgotado_minutos', '10'::jsonb,
   'Minutos que o cliente tem para pedir troca depois de um produto ficar em falta (só contagem no ecrã).',
   'cliente'),
  ('feature_habituais_home', 'true'::jsonb,
   'Os meus habituais: os últimos 3 pedidos do cliente no topo da página inicial, com repetir num toque.',
   'cliente'),
  ('feature_avaliacao_com_foto', 'true'::jsonb,
   'Permitir foto do prato na avaliação do pedido (sem prémio nenhum por enviar foto).',
   'cliente'),
  ('feature_etiquetas_menu', 'true'::jsonb,
   'Mostrar ao cliente as etiquetas do menu (vegetariano, picante, sem glúten) quando existirem.',
   'partners'),
  ('feature_etiquetas_menu_ia', 'false'::jsonb,
   'Deixar a IA sugerir as etiquetas do menu a partir da descrição do prato. O parceiro corrige no ecrã dos produtos. Ligar só depois de testado.',
   'partners'),
  ('feature_resumo_avaliacoes_ia', 'false'::jsonb,
   'Resumo das avaliações escrito por IA no painel do parceiro. Ligar só depois de testado.',
   'partners'),
  ('feature_funil_pratos', 'true'::jsonb,
   'Painel do parceiro: pratos muito vistos e pouco pedidos (aberturas da ficha contra pedidos).',
   'partners'),
  ('feature_oferta_ganho_visivel', 'true'::jsonb,
   'Cartão de oferta do estafeta mostra o ganho, a distância e o número de paragens antes de aceitar.',
   'drivers'),
  ('feature_mapa_procura_estafeta', 'true'::jsonb,
   'Mapa simples de procura para estafeta (zonas com mais pedidos por hora nos últimos 30 dias).',
   'drivers')
on conflict (key) do nothing;

-- Filtros rapidos da lista de restaurantes: duas chaves novas no JSON que ja
-- existe (desligadas por defeito).
update public.platform_settings
   set value = value || jsonb_build_object('takeaway_enabled', false, 'free_delivery_enabled', false),
       updated_at = now()
 where key = 'discovery_filters'
   and jsonb_typeof(value) = 'object'
   and not (value ? 'takeaway_enabled');

-- 2) Colunas novas (todas opcionais, nada muda para quem não as usa).
alter table public.client_addresses
  add column if not exists details text;
alter table public.client_addresses
  drop constraint if exists client_addresses_details_len;
alter table public.client_addresses
  add constraint client_addresses_details_len
  check (details is null or char_length(details) <= 80);

alter table public.products
  add column if not exists diet_tags text[] not null default '{}',
  add column if not exists diet_tags_source text,
  add column if not exists diet_tags_at timestamptz;
alter table public.products
  drop constraint if exists products_diet_tags_source_ok;
alter table public.products
  add constraint products_diet_tags_source_ok
  check (diet_tags_source is null or diet_tags_source in ('ia', 'parceiro'));

alter table public.ratings
  add column if not exists photo_url text;
