-- PROPOSTA (missão fecho-contabilista-2026-11-10, Claude Code, 10/11/2026) — APLICA A CLAUDE.AI.
-- Regra de 10/11/2026 (Danilo, fechada com o contabilista): o NIF da Bora nunca vai na caixa; sem NIF do
-- cliente o talão é consumidor final. A Claude.ai já mudou _nif_caixa_regra e _talao_nif_usado a 10/11
-- (backup em bkp_funcoes_nif_20261110). Ficou em driver_order_invoice_nif um ramo final morto que ainda
-- devolvia tipo 'bora' com o texto "talão com o NIF da Bora" — hoje nunca é alcançado (só chega lá quem
-- aplica=true, e isso só acontece com NIF do cliente), mas fica limpo: sem NIF do cliente → mostrar=false.
-- A app (ramo ai/2026-11-10-fecho-contabilista) também já só mostra o cartão quando o NIF é do cliente.
-- Só muda texto/decisão de mostrar; não mexe em dinheiro.

create table if not exists public.bkp_funcoes_nif_20261110b (
  nome text primary key, definicao text not null, guardado_em timestamptz not null default now());
alter table public.bkp_funcoes_nif_20261110b enable row level security;
revoke all on public.bkp_funcoes_nif_20261110b from public, anon, authenticated;
insert into public.bkp_funcoes_nif_20261110b (nome, definicao)
select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'driver_order_invoice_nif'
on conflict (nome) do nothing;

CREATE OR REPLACE FUNCTION public.driver_order_invoice_nif(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  o record;
  g jsonb;
  c record;
  v_conf jsonb;
  v_nif text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT id, assigned_driver_id, current_driver_offer_id, helper_driver_id INTO o
    FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF NOT COALESCE((public.is_admin()
         OR o.assigned_driver_id = v_uid::text
         OR o.current_driver_offer_id = v_uid::text
         OR o.helper_driver_id = v_uid
         OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN
    -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;

  g := public._nif_caixa_regra(p_order_id);
  -- 10/11/2026: só há cartão e caixa quando o CLIENTE pediu fatura com NIF.
  IF NOT COALESCE((g->>'aplica')::boolean, false) OR g->>'tipo' IS DISTINCT FROM 'cliente' THEN
    RETURN jsonb_build_object('ok', true, 'mostrar', false,
                              'loja_parceira', COALESCE((g->>'loja_parceira')::boolean, false),
                              'motivo', COALESCE(g->>'motivo', 'cliente_sem_nif'));
  END IF;

  SELECT nc.dado, nc.motivo, nc.confirmado_em INTO c
    FROM public.order_nif_caixa nc WHERE nc.order_id = p_order_id;
  v_conf := CASE WHEN c.confirmado_em IS NULL THEN NULL
                 ELSE jsonb_build_object('dado', c.dado, 'motivo', c.motivo, 'em', c.confirmado_em) END;
  v_nif := g->>'nif';
  RETURN jsonb_build_object('ok', true, 'mostrar', true, 'pediu_fatura', true, 'tipo', 'cliente',
                            'nif', v_nif, 'nome', g->>'nome', 'favor', (g->>'favor')::boolean,
                            'confirmado', v_conf,
                            'texto', 'Cliente pediu fatura com NIF ' || v_nif || ': pede ao balcão com este NIF');
END $function$;
