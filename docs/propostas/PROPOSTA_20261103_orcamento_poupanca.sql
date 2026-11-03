-- Missão boom-hamburguer-mes, bloco M (ordem do Danilo de 03/11/2026): "Com este pedido poupas X €"
-- (padrão Glovo). SÓ LEITURA: chama o orçamento do servidor (quote_order_pricing) e as funções de preço
-- que ele já usa, e soma apenas poupanças REAIS deste carrinho:
--   entrega  = entrega normal (pricing_calculate) - entrega com a oferta da loja (pricing_calculate_loja)
--   pedido_pequeno = taxa de pedido pequeno normal - a que esta loja cobra (loja que a tirou)
--   tokens   = tokens aplicados no orçamento (o BEMVINDO entra aqui)
--   promocoes = promoções ativas das lojas (preço normal - preço de promoção), com o mesmo arredondamento
-- Nunca compara com outras apps; nunca conta a taxa de serviço riscada. Não muda nada do que se cobra.
-- Interruptor: platform_settings.feature_poupanca_carrinho (false = devolve 0).

insert into public.platform_settings (key, value)
values ('feature_poupanca_carrinho', 'true'::jsonb)
on conflict (key) do nothing;

create or replace function public.orcamento_poupanca(p_input jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_ligado boolean;
  v_q jsonb;
  v_st text := p_input->>'service_type';
  v_rid text := nullif(p_input->>'restaurant_id', '');
  v_parc boolean := coalesce((p_input->>'is_partner_store')::boolean, false);
  v_apt boolean := coalesce((p_input->>'apartment_delivery')::boolean, false);
  v_sub numeric;
  v_km numeric;
  v_m numeric;
  v_ent numeric := 0;
  v_pp numeric := 0;
  v_tok numeric := 0;
  v_promo numeric := 0;
  v_normal numeric;
  v_loja numeric;
  v_line jsonb;
  p record;
begin
  select coalesce((value::text)::boolean, false) into v_ligado
    from platform_settings where key = 'feature_poupanca_carrinho';
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ligado', false, 'total_cents', 0, 'partes', '[]'::jsonb);
  end if;

  v_q := public.quote_order_pricing(p_input);   -- o mesmo orçamento que o carrinho mostra
  v_sub := coalesce((v_q->>'subtotal')::numeric, 0);

  if v_st in ('restaurant', 'storeShopping') and v_rid is not null and v_sub > 0 then
    v_km := coalesce((p_input->>'distance_km')::numeric,
                     public._haversine_km((p_input->>'pickup_lat')::numeric, (p_input->>'pickup_lng')::numeric,
                                          (p_input->>'dropoff_lat')::numeric, (p_input->>'dropoff_lng')::numeric));
    -- entrega que deixou de ser cobrada pela oferta da loja
    select c.delivery_fee into v_normal
      from public.pricing_calculate(v_st, v_sub, v_km, v_parc, v_apt, false, 0) c;
    select c.delivery_fee into v_loja
      from public.pricing_calculate_loja(v_st, v_sub, v_km, v_parc, v_apt, false, 0, v_rid) c;
    v_ent := greatest(0, round(coalesce(v_normal, 0) - coalesce(v_loja, 0), 2));

    -- taxa de pedido pequeno que esta loja tirou (só não parceira: na parceira nunca existiu)
    if not v_parc then
      v_pp := greatest(0, round(public.small_order_fee_calc(v_st, v_sub, null)
                               - coalesce((v_q->>'small_order_fee')::numeric, 0), 2));
    end if;
  end if;

  v_tok := greatest(0, coalesce((v_q->>'tokens_applied_value_cents')::numeric, 0) / 100.0);

  -- promoções ativas (mesma conta do orçamento: unitário arredondado ao cêntimo)
  select coalesce((value::text)::numeric, 0) into v_m from platform_settings where key = 'non_partner_markup_pct';
  if jsonb_typeof(p_input->'product_lines') = 'array' then
    for v_line in select * from jsonb_array_elements(p_input->'product_lines') loop
      select x.price::numeric as price, round(x.discount_price::numeric, 2) as promo into p
        from public.products x
       where x.id = (v_line->>'product_id') and public.product_promocao_ativa(x.id);
      if found and p.promo is not null and p.promo < p.price then
        if not v_parc and v_st <> 'takeaway' then
          v_promo := v_promo + (round(p.price * (1 + v_m), 2) - round(p.promo * (1 + v_m), 2))
                               * coalesce((v_line->>'quantity')::numeric, 1);
        else
          v_promo := v_promo + (p.price - p.promo) * coalesce((v_line->>'quantity')::numeric, 1);
        end if;
      end if;
    end loop;
  end if;
  v_promo := greatest(0, round(v_promo, 2));

  return jsonb_build_object(
    'ligado', true,
    'total_cents', round((v_ent + v_pp + v_tok + v_promo) * 100)::int,
    'partes', jsonb_build_array(
      jsonb_build_object('tipo', 'entrega', 'cents', round(v_ent * 100)::int),
      jsonb_build_object('tipo', 'pedido_pequeno', 'cents', round(v_pp * 100)::int),
      jsonb_build_object('tipo', 'tokens', 'cents', round(v_tok * 100)::int),
      jsonb_build_object('tipo', 'promocoes', 'cents', round(v_promo * 100)::int)));
end
$function$;

revoke all on function public.orcamento_poupanca(jsonb) from public, anon;
grant execute on function public.orcamento_poupanca(jsonb) to authenticated;
