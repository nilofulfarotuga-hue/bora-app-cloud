-- PROPOSTA — NÃO APLICAR SEM O "AUTORIZO" DO DANILO.
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- Missão fechar-tudo-2026-11-10, Bloco G, regra R7: os 6 degraus de DESCONTO do check-in
-- (Continente 3/5/7/10 €, Mercadona Beleza 3/5 €; dias 9, 10, 15, 16, 22, 25).
-- Ponto de partida: docs/propostas/PROPOSTA_20261104_checkin_desconto_e_premio_nao_parceiro.md
-- e docs/propostas/PROPOSTA_20261104_gatilho_cancelar_devolve_vale_desconto.md.
-- Os 6 degraus FICAM DESLIGADOS ("ativo": false). O painel (admin_checkin_degrau_editar) recusa
-- ligá-los até isto estar aplicado e provado. Liga-se quando o Danilo disser.
--
-- ── O QUE JÁ ESTÁ NO AR (lido em produção a 10/11/2026, só leitura) ──
--  1. quote_order_pricing aceita checkin_vale_id: valida dono, tipo, validade, loja e mínimo de
--     produtos; devolve checkin_desconto e checkin_desconto_falta_cents (migração 20261104125306).
--  2. _create_order_core aceita checkin_vale_id com a mesma validação (nunca confia no ecrã): tira o
--     desconto ao customer_total e à platform_commission; driver_earnings igual; marca o vale
--     'usado' com o pedido_id logo antes do débito do saldo; devolve checkin_desconto.
--  3. A app tem o desconto no carrinho pronto e DESLIGADO (CartStore.descontoCheckinNoPedido = false)
--     e já o manda no orçamento.
--
-- ── O QUE FALTA (por esta ordem) ──
--  A. [SQL, abaixo] O gatilho de cancelamento só devolve vales de pedidos com artigo
--     'premio-checkin-'. Um pedido com vale de DESCONTO não tem esse artigo: cancelado, o vale fica
--     'usado' para sempre. Tirar o filtro dos artigos (a função já procura por pedido_id e a regra
--     "só devolve antes de um estafeta aceitar" — _checkin_premio_pode_voltar — não muda).
--  B. [App, zona vermelha] lib/stores/order_store.dart, createOrder: juntar ao p_input
--        if (cart.checkinValeId != null) 'checkin_vale_id': cart.checkinValeId,
--     (o CartStore já tem o getter). Depois, e só depois, CartStore.descontoCheckinNoPedido = true.
--     Sem isto o carrinho nunca mostra desconto (o total do ecrã é sempre o que se paga).
--  C. [Decisão de dinheiro] Nos NÃO-parceiros (Continente, Mercadona) a platform_commission é só a
--     taxa de serviço; com 3-10 € de desconto fica NEGATIVA. Confirmar que o acerto/fecho aceita
--     comissão negativa (a Bora paga o desconto) ou pôr o desconto numa coluna própria. Ver
--     _create_order_core: "v_platform_commission := ROUND((v_platform_commission - v_ck_desc)…".
--  D. [Prova em dinheiro] Conta demo, pagamento em DINHEIRO, Continente:
--       - caixa abaixo do mínimo → sem desconto e "Falta X €";
--       - compra acima do mínimo → total menos o desconto, estafeta igual, vale 'usado' uma vez só;
--       - cancelar antes de aceitar → o vale volta a 'por_usar' (depois de A).
--     Nota: o pedido demo nasce driverAccepted (gatilho a_trg_pedido_demo_caixa_fechada) e um pedido
--     já aceite não devolve o vale de propósito — provar a devolução em transação desfeita (DO+RAISE)
--     com um pedido criado em 'created'.
--  E. Só depois de A-D e do "liga" do Danilo: o UPDATE comentado no fim deste ficheiro.

-- ── A. Cancelar o pedido devolve também o vale de desconto ──
CREATE OR REPLACE TRIGGER trg_checkin_premio_pedido_cancelado
  AFTER UPDATE OF status ON public.orders FOR EACH ROW
  WHEN ((new.status = ANY (ARRAY['cancelled'::text, 'rejected'::text]))
        AND (old.status IS DISTINCT FROM new.status))
  EXECUTE FUNCTION _checkin_premio_pedido_cancelado();

-- Prova depois de aplicar (só leitura): o gatilho já não tem o filtro dos artigos.
-- SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t
--  WHERE t.tgrelid = 'public.orders'::regclass AND t.tgname = 'trg_checkin_premio_pedido_cancelado';

-- ── E. LIGAR OS 6 DEGRAUS — SÓ COM A ORDEM DO DANILO (fica comentado) ──
-- UPDATE public.platform_settings
--    SET value = jsonb_set(value, '{ativo}', 'true'::jsonb), updated_at = now()
--  WHERE key IN ('checkin_marco_desconto_mercadona_3', 'checkin_marco_desconto_continente_3',
--                'checkin_marco_desconto_mercadona_5', 'checkin_marco_desconto_continente_5',
--                'checkin_marco_desconto_continente_7', 'checkin_marco_desconto_continente_10');
-- (e retirar de admin_checkin_degrau_editar o RAISE 'desconto_fica_desligado_ate_entrar_no_pagamento',
--  migração 20261110200400_checkin_g_5_painel.sql)
--
-- Nota de desenho: a escada (R4) guarda o prémio mais valioso a que a pessoa chegou. Com os descontos
-- ligados, um desconto de 10 € (dia 25) vale mais do que o hambúrguer da Boom (16,10 €)? Não: 1000 < 1610.
-- O desconto do dia 22 (7 €) passa à frente do açaí (9,22 €)? Não. A ordem por valor mantém-se.
-- Mas o trigger _checkin_marcos_apos_checkin só olha para 'produto' e 'servico': para os descontos
-- entrarem na escada é preciso acrescentar 'desconto' a essa lista (parte 2 da migração G).
