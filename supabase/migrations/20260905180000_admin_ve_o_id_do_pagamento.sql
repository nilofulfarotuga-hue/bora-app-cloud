-- ============================================================================
-- O PAINEL PASSA A MOSTRAR O ID DO PAGAMENTO
-- 2026-09-05
-- ----------------------------------------------------------------------------
-- PARA QUE SERVE, EM PORTUGUES SIMPLES
--
-- Quando um cliente diz "fui cobrado duas vezes", a pergunta que se responde e'
-- sempre a mesma: quantos pagamentos existem para esta compra? Um pagamento so,
-- ou dois? A resposta esta' no id do pagamento na Stripe. Ate hoje o painel nao
-- o mostrava nem para os planos TVDE nem para os pacotes ida-e-volta, por isso
-- essa pergunta nao tinha resposta sem ir a' base de dados a' mao.
--
-- Isto SO ACRESCENTA CAMPOS DE LEITURA a duas funcoes de listagem do admin.
-- Nao altera nenhum valor, nenhum preco, nenhuma cobranca. Nao mexe em Stripe.
--
-- (Nas limpezas o id ja vinha — a funcao de listagem devolve a linha inteira.
--  O que faltava la era mostra-lo no ecra, e isso e' do lado do Flutter.)
-- ============================================================================

-- 1) Planos TVDE ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tvde_subscriptions_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.active DESC, s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      sub.active AS active,
      sub.created_at AS created_at,
      jsonb_build_object(
        'id',             sub.id,
        'client_id',      sub.client_id,
        'client_name',    COALESCE(au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',   COALESCE(au.raw_user_meta_data->>'bora_phone', ''),
        'client_email',   au.email,
        'plan',           sub.plan,
        'rides_total',    sub.rides_total,
        'rides_used',     sub.rides_used,
        'daily_included', sub.daily_included,
        'price_cents',    sub.price_cents,
        'starts_at',      sub.starts_at,
        'ends_at',        sub.ends_at,
        'active',         sub.active,
        'created_at',     sub.created_at,
        -- NOVO (2026-09-05): o rasto do dinheiro. Dois planos do mesmo cliente
        -- com ids de pagamento DIFERENTES e datas coladas = cobranca dupla.
        'payment_intent_id', sub.stripe_payment_intent_id,
        'payment_status',    sub.payment_status
      ) AS row
    FROM public.tvde_subscriptions sub
    LEFT JOIN auth.users au ON au.id = sub.client_id
  ) s;
  RETURN v_out;
END; $function$;

-- 2) Pacotes ida-e-volta -------------------------------------------------------
-- A lista de colunas devolvidas muda, por isso a funcao antiga tem de cair
-- primeiro (o Postgres nao deixa trocar o formato de saida com REPLACE).
DROP FUNCTION IF EXISTS public.admin_tvde_roundtrips(integer);

CREATE OR REPLACE FUNCTION public.admin_tvde_roundtrips(p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, client_id uuid, status text, paid_cents integer,
               outbound_ride_id uuid, return_ride_id uuid,
               created_at timestamp with time zone, expires_at timestamp with time zone,
               payment_intent_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.id, c.client_id, c.status, c.paid_cents, c.outbound_ride_id, c.return_ride_id,
         c.created_at, c.expires_at,
         c.payment_intent_id   -- NOVO (2026-09-05): o rasto do dinheiro
    FROM public.tvde_roundtrip_credits c
   WHERE public.is_admin()
   ORDER BY c.created_at DESC LIMIT COALESCE(p_limit, 100);
$function$;

GRANT EXECUTE ON FUNCTION public.admin_tvde_roundtrips(integer) TO authenticated;
