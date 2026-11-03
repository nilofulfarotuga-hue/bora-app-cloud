-- Missão boom-hamburguer-mes-2026-11-02, bloco C (autorização do Danilo 02/11/2026 21:05, opção 1):
-- "Hambúrguer do mês" — um produto em destaque no topo da loja (padrão Glovo/Uber Eats).
-- restaurants.produto_destaque_id (id de products da MESMA loja) + produto_destaque_rotulo (o selo).
-- O parceiro escolhe o da sua loja (parceiro_definir_destaque); o admin o de qualquer loja
-- (admin_definir_destaque). Produto nulo = sem destaque (a loja fica como antes). Não toca em preços.

alter table public.restaurants
  add column if not exists produto_destaque_id text,
  add column if not exists produto_destaque_rotulo text default 'Hambúrguer do mês';

comment on column public.restaurants.produto_destaque_id is
  'Produto em destaque no topo da loja (products.id da mesma loja). Nulo = sem destaque.';
comment on column public.restaurants.produto_destaque_rotulo is
  'Selo do destaque (ex.: Hambúrguer do mês). Máximo 40 letras.';

-- O parceiro, só na loja dele (user_id ou user_, como parceiro_minhas_lojas).
create or replace function public.parceiro_definir_destaque(p_restaurant_id text, p_produto_id text, p_rotulo text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_rotulo text := coalesce(nullif(trim(coalesce(p_rotulo, '')), ''), 'Hambúrguer do mês');
  v_prod text := nullif(trim(coalesce(p_produto_id, '')), '');
begin
  if auth.uid() is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  if not exists (select 1 from restaurants r where r.id = p_restaurant_id
                   and (r.user_id = auth.uid() or r.user_ = auth.uid())) then
    raise exception 'loja_nao_e_tua' using errcode = '42501';
  end if;
  if v_prod is not null and not exists (
       select 1 from products where id = v_prod and restaurant_id = p_restaurant_id) then
    raise exception 'produto_nao_e_desta_loja';
  end if;
  if length(v_rotulo) > 40 then raise exception 'rotulo_demasiado_longo'; end if;
  update restaurants set produto_destaque_id = v_prod, produto_destaque_rotulo = v_rotulo
   where id = p_restaurant_id;
  return jsonb_build_object('ok', true, 'restaurant_id', p_restaurant_id,
                            'produto_destaque_id', v_prod, 'produto_destaque_rotulo', v_rotulo);
end
$function$;
grant execute on function public.parceiro_definir_destaque(text, text, text) to authenticated;

-- O admin, em qualquer loja, com registo na auditoria.
create or replace function public.admin_definir_destaque(p_restaurant_id text, p_produto_id text, p_rotulo text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_rotulo text := coalesce(nullif(trim(coalesce(p_rotulo, '')), ''), 'Hambúrguer do mês');
  v_prod text := nullif(trim(coalesce(p_produto_id, '')), '');
  v_res jsonb;
begin
  perform public._admin_op_guard();
  if not exists (select 1 from restaurants where id = p_restaurant_id) then
    raise exception 'loja_nao_encontrada';
  end if;
  if v_prod is not null and not exists (
       select 1 from products where id = v_prod and restaurant_id = p_restaurant_id) then
    raise exception 'produto_nao_e_desta_loja';
  end if;
  if length(v_rotulo) > 40 then raise exception 'rotulo_demasiado_longo'; end if;
  update restaurants set produto_destaque_id = v_prod, produto_destaque_rotulo = v_rotulo
   where id = p_restaurant_id;
  v_res := jsonb_build_object('ok', true, 'restaurant_id', p_restaurant_id,
                              'produto_destaque_id', v_prod, 'produto_destaque_rotulo', v_rotulo);
  perform public.log_admin_action('definir_destaque_loja', 'restaurant', p_restaurant_id, v_res);
  return v_res;
end
$function$;
grant execute on function public.admin_definir_destaque(text, text, text) to authenticated;

-- A Boom! abre com o Café de Paris (o produto que a Claude.ai já pôs em "Hambúrguer do Mês").
update public.restaurants
   set produto_destaque_id = 'f2ac93d2-9e77-4f02-8cbe-11a17ce91b32',
       produto_destaque_rotulo = 'Hambúrguer do mês'
 where id = 'boom-burger-guarda'
   and exists (select 1 from public.products where id = 'f2ac93d2-9e77-4f02-8cbe-11a17ce91b32'
                 and restaurant_id = 'boom-burger-guarda');
