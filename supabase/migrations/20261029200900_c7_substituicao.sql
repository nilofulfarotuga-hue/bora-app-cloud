-- C7 (adendo 5, item 7, 29/10/2026) — SUBSTITUICAO ESCOLHIDA ANTES DE PAGAR.
--
-- No checkout de um mercado (nao parceiro) ou de um Favor com compra, o cliente
-- escolhe o que o estafeta faz se faltar um produto ("replacement preference"
-- na Uber Eats, Glovo e iFood):
--   trocar          -> trocar por um parecido
--   tirar_devolver  -> tirar do pedido (o cliente nao paga por ele)
--   ligar           -> o estafeta fala com o cliente no chat, com foto
--
-- INTERRUPTOR DESLIGADO POR DEFEITO (substitution_choice_enabled = false):
-- desligado, a app nao mostra a pergunta e o servidor recusa a gravacao.
--
-- ISTO NAO MEXE EM DINHEIRO. Guarda so a ESCOLHA. A devolucao do valor de um
-- produto em falta continua a ser a de hoje (finalizar_talao_nao_parceiro:
-- dinheiro desconta na hora; cartao/MB Way volta ao saldo). Passar essa
-- devolucao para o meio original (regra de 28/10) e' dinheiro: esta so em
-- docs/propostas/missao-geral-2026-10-28/C7_substituicao/01_devolucao_proposta.md.
--
-- create_order recebe p_input jsonb mas faz INSERT com colunas explicitas, por
-- isso um campo extra no p_input seria ignorado e perdido. A app grava a escolha
-- logo a seguir a criar o pedido, com client_set_substitution_preference.
--
-- A "preferencia para a proxima vez" NAO tem tabela nem coluna propria: e' a
-- escolha do pedido mais recente do cliente (client_get_substitution_preference).
-- Menos uma coisa para manter, nada a tocar em public.users nem na memoria do
-- Bora Assistente, e o comportamento e' o mesmo (a ultima escolha fica).

-- 1) Interruptor. ON CONFLICT DO NOTHING: nunca desfaz uma escolha do admin.
insert into public.platform_settings (key, value, description, category) values
  ('substitution_choice_enabled', 'false'::jsonb,
   'Perguntar ao cliente, antes de pagar, o que fazer se faltar um produto (trocar por parecido, tirar e devolver, falar comigo). So em mercados que nao sao parceiros e em Favores com compra. O estafeta ve a escolha na lista de compras e o admin no detalhe do pedido. So guarda a escolha: nao muda nenhum valor cobrado ou pago.',
   'cliente')
on conflict (key) do nothing;

-- 2) A escolha, no pedido. Nula = o cliente nao escolheu (tudo como ate aqui).
alter table public.orders
  add column if not exists substitution_preference text;
alter table public.orders
  drop constraint if exists orders_substitution_preference_ok;
alter table public.orders
  add constraint orders_substitution_preference_ok
  check (substitution_preference is null
         or substitution_preference in ('trocar', 'tirar_devolver', 'ligar'));

comment on column public.orders.substitution_preference is
  'Escolha do cliente antes de pagar para quando faltar um produto: trocar | tirar_devolver | ligar. Nula = sem escolha. Gravada por client_set_substitution_preference; nao e coluna financeira.';

-- 3) Gravar a escolha. So o dono do pedido, so antes de o estafeta recolher,
--    so em mercado nao parceiro ou Favor com compra, so com o interruptor ligado.
create or replace function public.client_set_substitution_preference(p_order_id text, p_pref text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_order record;
  v_ligado boolean;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;

  if p_pref is null or p_pref not in ('trocar', 'tirar_devolver', 'ligar') then
    raise exception 'SUBSTITUICAO_INVALIDA: %', coalesce(p_pref, 'null');
  end if;

  select coalesce((select value = 'true'::jsonb
                     from public.platform_settings
                    where key = 'substitution_choice_enabled'), false)
    into v_ligado;
  if not v_ligado then raise exception 'SUBSTITUICAO_DESLIGADA'; end if;

  select id, user_id, status, service_type, is_partner_store, errand_has_purchase
    into v_order
    from public.orders
   where id = p_order_id
   for update;
  if not found then raise exception 'ORDER_NOT_FOUND: %', p_order_id; end if;

  if v_order.user_id::text is distinct from v_uid::text then
    raise exception 'NOT_ORDER_OWNER';
  end if;

  -- Antes de o estafeta recolher (pickedUp) e' que ainda faz sentido escolher.
  if v_order.status not in ('created', 'preparing', 'readyForPickup', 'callingDriver', 'driverAccepted') then
    raise exception 'ORDER_ALREADY_PICKED_UP: %', v_order.status;
  end if;

  if not (
       (v_order.service_type = 'storeShopping' and not coalesce(v_order.is_partner_store, false))
    or (v_order.service_type = 'errand' and coalesce(v_order.errand_has_purchase, false))
  ) then
    raise exception 'SUBSTITUICAO_NAO_APLICA: %', v_order.service_type;
  end if;

  update public.orders
     set substitution_preference = p_pref
   where id = p_order_id;

  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'preference', p_pref);
end;
$function$;
revoke all on function public.client_set_substitution_preference(text, text) from public, anon;
grant execute on function public.client_set_substitution_preference(text, text) to authenticated;

-- 4) A ultima escolha do cliente (pre-marca o seletor na proxima vez).
--    Devolve nulo se nunca escolheu. Le so os pedidos do proprio utilizador.
create or replace function public.client_get_substitution_preference()
 returns text
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select o.substitution_preference
    from public.orders o
   where o.user_id::text = auth.uid()::text
     and o.substitution_preference is not null
   order by o.created_at desc
   limit 1;
$function$;
revoke all on function public.client_get_substitution_preference() from public, anon;
grant execute on function public.client_get_substitution_preference() to authenticated;
