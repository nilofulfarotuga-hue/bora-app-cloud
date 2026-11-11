# CONTRATO — missão farmacias-2026-11-11 (fonte única para todos os agentes)

Lojas: `farmacia-se-guarda` (dona: demo.farmacia.se@bora.app, uid 9b218f1a-3b54-4168-ba8f-d1b218f6ec94)
e `farmacia-teixeira-guarda` (dona: demo.farmacia.teixeira@bora.app, uid a34b2f3d-40f4-439a-bf22-3dcc7721c2a4).
Contas do Danilo (únicas que veem as lojas): boraappbora@gmail.com `4f61dd31-5e9e-4a7c-a557-7d53d2ceded7`,
nilofulfarotuga@gmail.com `c9fccf85-03ee-4efc-83bf-613f211a78ff` (esta também é admin).
Hoje (antes da migração) as lojas estão `approval_status='rejected'`, `is_active_admin=false`, `coming_soon=true` = invisíveis.

A trava do PC NÃO deixa aplicar estrutura em produção: tudo o que é DDL vai em ficheiros de migração no ramo
`ai/2026-11-11-farmacias` e a Claude.ai aplica. Dados (INSERT/UPDATE em restaurants/products, Storage) faz o PC.

## 1. Visibilidade (lista de permissão por loja)
- `restaurants.so_lista_permissao boolean not null default false`.
- Tabela `loja_lista_permissao(restaurant_id text fk restaurants on delete cascade, user_id uuid fk auth.users on delete cascade,
  motivo text, criado_por uuid, criado_em timestamptz default now(), primary key(restaurant_id,user_id))`. RLS: admin tudo; o
  próprio utilizador vê as suas linhas. Sem escrita por clientes.
- `public.lojas_escondidas_para_mim() returns text[]` (SECURITY DEFINER, STABLE, search_path fixo): ids das lojas com
  `so_lista_permissao` que o `auth.uid()` NÃO pode ver. Pode ver: admin (`is_admin()`), dono (`user_id`/`user_`), quem está na lista.
- `public.loja_visivel_para_mim(p_restaurant_id text) returns boolean` = not (id = any(lojas_escondidas_para_mim())).
- Políticas RESTRICTIVE de SELECT em `restaurants` e `products`: `not (id/restaurant_id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}')))`.
- Todas as funções SECURITY DEFINER que o cliente/anon chama e leem lojas/produtos filtram as escondidas
  (cliente_pesquisar, home_mais_pedidos, home_pede_outra_vez, search_businesses, assistant_search_products,
  assistant_propose_cart, agent_search_products, agent_get_store_info, store_active_promotions, social_lojas_permitidas,
  e as que a auditoria encontrar). `social_lojas_permitidas` exclui SEMPRE as `so_lista_permissao` (os robôs das redes nunca as mostram).
  Edge Functions com service role que mostram lojas/produtos a clientes (ex.: client-assistant) também filtram.

## 2. Modo demonstração (enquanto `so_lista_permissao`)
- `_modo_demo_loja(p_rid, p_uid)` passa a devolver true também quando a loja é `so_lista_permissao` e `p_uid` está na lista
  (ou `p_uid` null). Efeito já provado da Boom: pedido em dinheiro → `is_test_order=true` (gatilho `a_trg_pedido_demo_caixa_fechada`)
  e passa o `_coming_soon_guard_orders`.
- `_e_pedido_demo_loja(p_order_id)` passa a devolver true também para pedidos `is_test_order` de lojas `so_lista_permissao`
  → o despacho só oferece ao estafeta demo (`_modo_demo_estafeta()`), nunca a estafetas reais.
- Guarda nova BEFORE INSERT em orders: loja `so_lista_permissao` e pedido que não é `is_test_order` → erro
  `LOJA_EM_DEMONSTRACAO: Nesta demonstração só se pede em dinheiro.` (nunca há cobrança real por cartão/MB Way).
- Pedidos `is_test_order` já ficam fora de fechos e contas (`is_demo_order`).

## 3. Colunas novas
- `products.is_medicine boolean not null default true`; `products.preco_provisorio boolean not null default false`.
- `restaurants.pharmacy_prescription_mode text not null default 'desligado' check in ('desligado','so_lista','publico')`.
  Botões e receita visíveis se categoria `pharmacy` e (modo='publico' ou (modo='so_lista' e (lista/admin/dono))).
- `restaurants.partner_extra_commission_pct numeric` (null = nada), `restaurants.partner_extra_commission_starts_at timestamptz`
  (null = ainda não conta). As duas farmácias: 0.10 e null. Ninguém mais muda.
- `restaurants.aberta_ao_publico_em timestamptz` (quando o Danilo disser "abre"; a data da comissão = esta + N meses).

## 4. Definições (platform_settings, novas)
- `pharmacy_prescription_response_minutes` = 15 (lembrete à farmácia aos X, expira aos 2X).
- `pharmacy_prescription_retention_days` = 30 (apagar foto, assinatura e códigos depois da entrega/recusa/expiração).
- `errand_pharmacy_driver_cents` = 500 (igual ao Favor normal até o Danilo decidir).
- `pharmacy_prescription_commission_pct` = 0.10 (adendo 1: os 10% contam também na receita, com a mesma data de início).
- `pharmacy_extra_commission_months` = 3.
- `pharmacy_prescription_consent_version` = 'v1-2026-11-11' e `pharmacy_prescription_consent_text` =
  "Autorizo o estafeta da Bora a levantar os meus medicamentos em meu nome na {farmacia}. A farmácia valida a receita e é responsável pela dispensa."
- A taxa da Bora vem de `errand_fee_normal_cents` (600), já existe.

## 5. Tabela `pedidos_prescricao`
id uuid pk default gen_random_uuid(); created_at, updated_at; restaurant_id text fk; user_id uuid fk auth.users (cliente);
tipo text check in ('receita','pedido_livre');
estado text check in ('enviado','aceite','aceite_parcial','recusado','expirado','cancelado','confirmado','entregue') default 'enviado';
-- cliente envia
receita_foto_path text, receita_numero text, receita_codigo_acesso text, receita_codigo_opcao text,
descricao text (pedido livre: o que quer), pedido_foto_path text (foto opcional do pedido livre),
morada text, lat double precision, lng double precision, nota text,
assinatura_path text, consentimento_versao text, consentimento_texto text, consentimento_em timestamptz;
-- farmácia responde
valor_medicamentos_cents int, itens_disponiveis text, tempo_preparacao_min int, motivo_recusa text
check in ('sem_stock','receita_invalida','outro'), motivo_texto text, volta_a_ter text, respondido_por uuid, respondido_em timestamptz,
lembrete_enviado_em timestamptz, expira_em timestamptz;
-- cliente confirma
taxa_servico_cents int, total_cents int, metodo_pagamento text check in ('card','mbway','cash'), so_disponiveis boolean,
confirmado_em timestamptz, codigo_levantamento text (6 letras/números, para o estafeta mostrar na farmácia),
codigo_entrega text (4 dígitos), order_id text (pedido real em orders, quando houver), is_demo boolean default false,
cancelado_por uuid, cancelado_em timestamptz, entregue_em timestamptz, dados_apagados_em timestamptz.
RLS: cliente vê/insere as suas (insert só pela RPC); dono da loja vê as da loja; admin tudo. Realtime ligado
(`alter publication supabase_realtime add table`). As colunas sensíveis (fotos, códigos) nunca vão para e2e_log/Telegram.

## 6. RPCs (todas SECURITY DEFINER, search_path fixo, REVOKE FROM PUBLIC, GRANT só a authenticated)
Cliente:
- `farmacia_botoes_visiveis(p_restaurant_id text) returns boolean`
- `farmacia_consentimento(p_restaurant_id text) returns jsonb` → {versao, texto (com o nome da farmácia), taxa_servico_cents}
- `prescricao_criar(p_restaurant_id text, p_tipo text, p_receita_foto_path text, p_receita_numero text, p_receita_codigo_acesso text,
   p_receita_codigo_opcao text, p_descricao text, p_pedido_foto_path text, p_morada text, p_lat double precision, p_lng double precision,
   p_nota text, p_assinatura_path text, p_consentimento_versao text) returns uuid`
   Regras: receita exige (foto) OU (número + código de acesso); exige assinatura + versão de consentimento atual. pedido_livre exige descrição.
   Põe `expira_em = now() + 2X`, `is_demo = loja.so_lista_permissao`. Avisa a farmácia (push com toque persistente, tipo `prescricao_nova`).
- `prescricao_confirmar(p_id uuid, p_metodo text, p_so_disponiveis boolean) returns jsonb` — só de aceite/aceite_parcial.
   Demo: estado `confirmado`, gera códigos, NÃO cria pedido nem cobra; avisa a farmácia (`prescricao_confirmada`).
   Não-demo (loja pública): cria o pedido real (Favor de farmácia) — se ainda não estiver ligado, erro claro `RECEITA_REAL_POR_LIGAR`.
- `prescricao_cancelar(p_id uuid) returns void` — cliente, antes de confirmado.
Farmácia (dono da loja do pedido):
- `prescricao_responder(p_id uuid, p_aceita boolean, p_valor_cents int, p_parcial boolean, p_itens_disponiveis text,
   p_tempo_preparacao_min int, p_motivo text, p_motivo_texto text, p_volta_a_ter text) returns void`
   Avisa o cliente (push tipo `prescricao_resposta` + sininho).
- `prescricao_url_assinada(p_id uuid, p_campo text) returns text` NÃO é preciso: a app usa `createSignedUrl` do Storage com as políticas do bucket.
Admin:
- `admin_prescricoes_listar(p_estado text, p_restaurant_id text, p_limite int) returns setof jsonb` (sem fotos/códigos em claro: só se há ou não)
- `admin_prescricao_forcar(p_id uuid, p_estado text, p_motivo text)` (forçar/cancelar; regista em admin_audit_log)
- `admin_farmacia_definir(p_restaurant_id text, p_modo text, p_so_lista boolean, p_extra_pct numeric, p_extra_inicio timestamptz)`
- `admin_loja_lista_permissao_definir(p_restaurant_id text, p_user_ids uuid[])`
- `admin_farmacia_abrir(p_restaurant_id text)` → so_lista_permissao=false, aberta_ao_publico_em=now(),
   partner_extra_commission_starts_at = now() + N meses (definição), exige conformidade completa (não força).
Lembrete mensal:
- tabela `farmacia_lembretes(id uuid, user_id, restaurant_id, prescricao_id uuid null, order_id text null, dia_do_mes int 1-28,
  ativo bool, proximo_em date, ultimo_aviso_em timestamptz, created_at)`; RPCs `farmacia_lembrete_definir(p_restaurant_id, p_prescricao_id,
  p_order_id, p_dia int) returns uuid`, `farmacia_lembrete_desligar(p_id uuid)`. Nunca faz pedido nem cobra: só avisa
  (tipo `farmacia_lembrete_mensal`) e o toque abre o formulário já preenchido.
Tarefas (pg_cron): cada minuto `prescricao_vigiar()` (lembrete aos X, expira aos 2X e avisa o cliente); diária
`farmacia_lembretes_disparar()` às 09:00 de Lisboa; diária limpeza dos dados de saúde (Edge `prescricoes-limpeza` com service role,
apaga ficheiros do bucket e põe a null os códigos/caminhos, marca `dados_apagados_em`).

## 7. Storage
Bucket privado `prescricoes`. Caminhos: `<uid_cliente>/<uuid>-receita.<ext>`, `<uid_cliente>/<uuid>-assinatura.png`,
`<uid_cliente>/<uuid>-pedido.<ext>`. Políticas: o cliente insere/lê a sua pasta; o dono da loja lê ficheiros que aparecem
num pedido_prescricao da sua loja; admin lê tudo. Ninguém mais. Fotos por URL assinado de curta duração (5 min).

## 8. Tipos de aviso (push data-only) — entram em `_kPersistentCategoryTypes` os da farmácia
`prescricao_nova` (parceiro, TOQUE PERSISTENTE até abrir), `prescricao_lembrete` (parceiro, persistente),
`prescricao_confirmada` (parceiro), `prescricao_resposta` (cliente), `prescricao_expirada` (cliente),
`farmacia_lembrete_mensal` (cliente). Tocar no aviso abre o ecrã certo com o id.

## 9. Dinheiro (está autorizado pelo Danilo a 11/11 para ESTAS duas lojas; nada muda para mais ninguém)
- Catálogo: `products.price` = preço da Glovo (é o que o cliente vê, como na Boom); `partner_shelf_price` = price×0,90/1,05
  (balcão provisório); `preco_provisorio=true`. Cliente: +5 % de taxa de serviço, entrega normal, grátis acima de 30 €.
- Farmácia recebe a parte normal da loja (`partner_store_share`). Depois de `partner_extra_commission_starts_at`, desconta-se
  `partner_extra_commission_pct` dessa parte no fecho semanal (antes da data: zero). Receita: remédios 1 para 1 ao cliente;
  à farmácia o valor inteiro, menos `pharmacy_prescription_commission_pct` depois da mesma data. Bora: taxa do Favor (600).
- Mostrar no extrato do parceiro e no painel admin.

## 10. Idiomas e estilo
Apps PT-PT, painel admin PT-BR. Verde #16A34A, laranja #F97316 (um elemento laranja por ecrã no máximo), Inter.
Botões de baixo com `BoraBottomActionBar.folgaInferior`; ecrãs que rolam; nada cortado a 360 px.
