-- =============================================================================
-- B2 — CONHECIMENTO DO AMIGO BORA (missão fechar-tudo-2026-11-11, bloco 2)
-- NÃO APLICADO pelo executor. Aplica a sessão que o chamou, DEPOIS da migração
-- supabase/migrations/20261111090000_amigo_pesquisa_e_lojas_abertas.sql (não depende dela, mas é a ordem).
--
-- O que faz (nada se apaga; só assistant_learned e assistant_knowledge, sem dinheiro de ninguém):
--   (a) desliga (active = false) a resposta aprendida com lixo 02ed08cc-… — o "manual" devolveu notas
--       internas (TODOs, atualização de produtos) à pergunta da agenda da Guarda de 10/11 e isso ficou
--       aprendido e entrava no prompt de todos os clientes;
--   (b) põe o conhecimento do Amigo em dia com os valores de HOJE (platform_settings lidas a 11/11/2026
--       ~08:20 Lisboa, ver relatório): TVDE não disponível; tokens; carteira (o cliente escolhe Carteira
--       ou conta); pagamentos (sem "valor de garantia"); WhatsApp no "falar com uma pessoa"; e acrescenta
--       categorias, entrega, sacos, depósito Volta, check-in, lavagem e gorjeta.
--   Antes de cada mudança, cópia em bkp_assistant_knowledge_20261111 / bkp_assistant_learned_20261111.
--
-- Valores confirmados em platform_settings (11/11/2026):
--   tvde_app_visivel=false, tvde_passageiros_enabled=false · client_token_award_pct=3 ·
--   token_value_cents_x100=50 (100 tokens = 0,50 €) · token_balance_max_use_pct=50 · checkin_token_expiry_days=60 ·
--   checkin_rewards=[5,5,10,10,15,15,40] · checkin_require_phone=true · wallet_split_free_pct=1.0 ·
--   max_cash_amount_cents=4000 · mbway_enabled=true · non_partner_payment_buffer_multiplier=1.0 ·
--   delivery_base_fee_cents=250, delivery_base_distance_km=4, delivery_per_km_cents=50, delivery_max_distance_km=15 ·
--   bag_fee_restaurant_cents=30, bag_fee_supermarket_per_bag_cents=10 · volta_deposit_enabled=true, volta_deposit_cents=10 ·
--   tips_enabled=true, tip_max_cents=5000 · carwash_enabled=true, carwash_price_exterior_cents=1200,
--   carwash_price_full_cents=2000, carwash_interior_enabled=false, carwash_service_radius_km=8 ·
--   support_settings.whatsapp_number=+351937501673.
--   A escolha Carteira/conta no reembolso não está em platform_settings: está na app (refund_choice_dialog.dart,
--   regra do Danilo de 29/10: 100% em saldo na Carteira, ou MB Way/cartão; tokens voltam como tokens).
-- =============================================================================

begin;

-- ─── 0. Cópias antes de mexer ─────────────────────────────────────────────────
create table if not exists public.bkp_assistant_knowledge_20261111 as
  select * from public.assistant_knowledge;
create table if not exists public.bkp_assistant_learned_20261111 as
  select * from public.assistant_learned where id = '02ed08cc-a61d-4df3-baad-50a6a36442b7';
revoke all on public.bkp_assistant_knowledge_20261111 from public, anon, authenticated;
revoke all on public.bkp_assistant_learned_20261111 from public, anon, authenticated;

-- ─── (a) Resposta aprendida com lixo: desligar, nunca apagar ──────────────────
update public.assistant_learned
   set active = false, updated_at = now()
 where id = '02ed08cc-a61d-4df3-baad-50a6a36442b7'
   and active = true;

-- ─── (b) Conhecimento: rever o que existe ─────────────────────────────────────
update public.assistant_knowledge
   set title = 'Bora Motorista (TVDE) — não disponível',
       content = 'As viagens (Bora Motorista, TVDE) não estão disponíveis na app de momento. Se perguntarem, diz que ainda não há viagens na Bora e sugere o que há: entregas de restaurantes, supermercados, farmácias e lojas, Favores, Limpeza, Lavagem Auto e Reservas de mesa.',
       updated_at = now()
 where id = '4f61aa0f-76c4-431c-990c-898f90ae6b30' and topic = 'tvde';

update public.assistant_knowledge
   set content = 'Cada pedido entregue dá tokens Bora: cerca de 3 tokens por cada euro do pedido. 100 tokens valem 0,50 €. Num pedido usas no máximo metade do valor dos tokens que tens. Os tokens do check-in diário valem 60 dias. Vês os teus tokens em Perfil > Carteira.',
       updated_at = now()
 where id = '4467294a-f689-438a-a854-666d64840ced' and topic = 'tokens';

update public.assistant_knowledge
   set content = 'O saldo da Carteira Bora paga pedidos (Perfil > Carteira). Quando um pedido pago com cartão ou MB Way é cancelado e há dinheiro a devolver, o cliente escolhe: Carteira Bora (fica logo disponível, tudo em saldo) ou devolver para a conta (MB Way, normalmente na hora; cartão, 5 a 10 dias úteis). O valor é o mesmo nas duas. Os tokens usados no pedido voltam como tokens.',
       updated_at = now()
 where id = '0129bc00-97f4-4290-9bc7-1a7b6bea2653' and topic = 'carteira';

update public.assistant_knowledge
   set content = 'Formas de pagamento: cartão, MB Way, dinheiro (até 40 €) e saldo da Carteira/tokens. Nos supermercados e cadeias paga-se o preço que aparece na app; a entrega e as taxas aparecem antes de pagar.',
       updated_at = now()
 where id = '9ccad6c0-1f4f-491a-b461-1c6fbc91f9df' and topic = 'pagamento';

update public.assistant_knowledge
   set content = 'Suporte humano: Perfil > Ajuda > Falar com o suporte (chat), WhatsApp da Bora 937 501 673 ou e-mail boraappbora@gmail.com. O Amigo passa a conversa ao suporte quando não consegue resolver.',
       updated_at = now()
 where id = 'ac7338be-5b4b-4791-aaea-3a5bf1ef2103' and topic = 'humano';

-- ─── (b) Conhecimento: acrescentar o que faltava (só se ainda não existir) ────
insert into public.assistant_knowledge (topic, title, content, active, sort_order)
select v.topic, v.title, v.content, true, v.sort_order
  from (values
    ('categorias', 'O que há na app Bora',
     'Na página inicial: Restaurantes, Supermercados, Farmácia, Lojas, Enviar Encomenda, Levar Compras, Favores, Reservar Mesa, Beleza, Limpeza, Casa e Manutenção, Festas, Sobremesas e Lavagem Auto. Viagens (Bora Motorista) não estão disponíveis.',
     135),
    ('entrega', 'Taxa de entrega',
     'A entrega custa 2,50 € até 4 km; a partir daí, mais 0,50 € por cada km. Entregamos até 15 km. O valor certo aparece antes de pagar (e nos cartões do Amigo, já com tudo incluído).',
     140),
    ('sacos', 'Sacos',
     'Sacos: nos restaurantes 0,30 € por pedido; nos supermercados 0,10 € por saco.',
     145),
    ('deposito_volta', 'Depósito Volta',
     'Latas e garrafas de plástico de bebidas (até 3 L) pagam o depósito Volta: 0,10 € por embalagem, numa linha à parte (é a lei). Recebes o dinheiro de volta quando entregas as embalagens vazias numa máquina Volta. O estafeta não recolhe embalagens vazias.',
     150),
    ('checkin', 'Check-in diário',
     'Check-in diário no topo da página inicial: um toque por dia dá tokens (5, 5, 10, 10, 15, 15 e 40 ao 7.º dia seguido). Os tokens do check-in valem 60 dias. Precisa de telemóvel confirmado. A partir do dia 8 abrem prémios maiores (vês no calendário); levantas um a cada 30 dias, só quem fez um pedido no último mês; entrega e taxas pagas à parte.',
     155),
    ('lavagem', 'Lavagem Auto',
     'Lavagem Auto (na página inicial): lavagem exterior 12 € ou lavagem completa (por fora e por dentro) 20 €, até 8 km. O preço certo aparece antes de pagar.',
     160),
    ('gorjeta', 'Gorjeta',
     'Podes deixar gorjeta ao estafeta ao pagar ou no fim do pedido. A gorjeta vai toda para o estafeta. Máximo 50 €.',
     165)
  ) as v(topic, title, content, sort_order)
 where not exists (select 1 from public.assistant_knowledge k where k.topic = v.topic);

-- Prova (lida de volta antes do commit):
select topic, title, active, left(content, 80) as inicio from public.assistant_knowledge order by sort_order;
select id, active from public.assistant_learned where id = '02ed08cc-a61d-4df3-baad-50a6a36442b7';

commit;
