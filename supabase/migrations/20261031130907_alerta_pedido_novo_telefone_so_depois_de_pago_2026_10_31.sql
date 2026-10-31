CREATE OR REPLACE FUNCTION public._alerta_txt_pedido(o orders)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_loja      text;
  v_pag       text;
  v_total     numeric;
  v_tel       text;
  v_por_tel   boolean := false;
  v_items     jsonb;
  v_it        jsonb;
  v_n         int := 0;
  v_qtd_itens int := 0;
  v_itens     text := '';
  v_opc       text;
  v_linha     text;
  v_extra     numeric;
  v_balcao    numeric := 0;
  v_balcao_ok boolean := true;
  v_extras    text := '';
begin
  select r.name,
         coalesce(nullif(btrim(r.phone_order_number), ''), nullif(btrim(r.phone), '')),
         coalesce(r.order_by_phone, false)
    into v_loja, v_tel, v_por_tel
    from public.restaurants r where r.id = o.restaurant_id;
  v_loja  := coalesce(v_loja, nullif(btrim(o.vendor_name), ''), o.restaurant_id, 'loja desconhecida');
  v_total := coalesce(o.final_total, o.price, 0);
  v_pag   := case lower(coalesce(o.payment_method, ''))
               when 'cash'  then 'Dinheiro'
               when 'card'  then 'Cartão'
               when 'mbway' then 'MB WAY'
               else coalesce(o.payment_method, 'por definir') end;

  -- 31/10/2026 (queixa do Danilo, pedido da Jyosmi Sushi): o aviso não dizia O QUE se pediu
  -- nem o telefone da loja. Agora leva os produtos, o valor ao balcão (lojas não-parceiras),
  -- a nota do cliente, o texto do Favor e, nas lojas de encomenda por telefone, o número para ligar.
  -- O número só aparece com o pagamento garantido (dinheiro ou já pago): com MB WAY/cartão
  -- ainda por pagar diz para esperar o aviso "LIGAR À LOJA", que sai quando o pagamento cai —
  -- para nunca se encomendar à loja um pedido que o cliente acaba por não pagar.
  -- Cada parte está protegida: se falhar, sai o aviso curto de sempre.
  -- Texto curto de propósito (máx. 10 produtos, 70 letras cada): o mesmo texto vai no push (limite 4 KB).
  begin
    if v_por_tel and v_tel is not null then
      if lower(coalesce(o.payment_method, '')) in ('card', 'mbway')
         and coalesce(o.payment_status, '') <> 'paid' then
        v_loja := v_loja || ' · por telefone: espera o aviso LIGAR (pagamento por confirmar)';
      else
        v_tel := regexp_replace(v_tel, '[^0-9]', '', 'g');
        if length(v_tel) = 12 and left(v_tel, 3) = '351' then v_tel := substr(v_tel, 4); end if;
        if length(v_tel) = 9 then
          v_tel := substr(v_tel, 1, 3) || ' ' || substr(v_tel, 4, 3) || ' ' || substr(v_tel, 7, 3);
        end if;
        if v_tel <> '' then v_loja := v_loja || ' · ligar ' || v_tel; end if;
      end if;
    end if;
  exception when others then null;
  end;

  begin
    v_items := o.items::jsonb;
    if jsonb_typeof(v_items) = 'array' and jsonb_array_length(v_items) > 0 then
      v_qtd_itens := jsonb_array_length(v_items);
      for v_it in select e.value from jsonb_array_elements(v_items) e loop
        v_n := v_n + 1;
        -- valor ao balcão = (preço base + extras) x quantidade
        begin
          select coalesce(sum((gi.value->>'price_add')::numeric), 0) into v_extra
            from jsonb_array_elements(case when jsonb_typeof(v_it->'selected_options_priced') = 'array'
                                           then v_it->'selected_options_priced' else '[]'::jsonb end) g,
                 jsonb_array_elements(case when jsonb_typeof(g.value->'items') = 'array'
                                           then g.value->'items' else '[]'::jsonb end) gi;
          if (v_it->>'basePrice') is not null then
            v_balcao := v_balcao + ((v_it->>'basePrice')::numeric + coalesce(v_extra, 0))
                                   * coalesce((v_it->>'quantity')::numeric, 1);
          else
            v_balcao_ok := false;
          end if;
        exception when others then v_balcao_ok := false;
        end;
        if v_n <= 10 then
          v_opc := null;
          begin
            select string_agg(x.v, ', ') into v_opc
              from (select jsonb_array_elements_text(g.value->'items') as v
                      from jsonb_array_elements(case when jsonb_typeof(v_it->'selected_options') = 'array'
                                                     then v_it->'selected_options' else '[]'::jsonb end) g
                     where jsonb_typeof(g.value->'items') = 'array') x;
          exception when others then v_opc := null;
          end;
          v_linha := coalesce(v_it->>'quantity', '1') || 'x ' || coalesce(nullif(btrim(v_it->>'name'), ''), 'produto');
          if coalesce(v_opc, '') <> '' then v_linha := v_linha || ' (' || v_opc || ')'; end if;
          if length(v_linha) > 70 then v_linha := left(v_linha, 69) || '…'; end if;
          v_itens := v_itens || E'\n- ' || v_linha;
        end if;
      end loop;
      if v_qtd_itens > 10 then
        v_itens := v_itens || E'\n- … e mais ' || (v_qtd_itens - 10) || ' produtos';
      end if;
      if v_itens <> '' then v_extras := E'\nProdutos:' || v_itens; end if;
      if coalesce(o.is_partner_store, false) = false and v_balcao_ok and v_balcao > 0 then
        v_extras := v_extras || E'\nAo balcão: ' || to_char(v_balcao, 'FM999999990.00') || ' EUR';
      end if;
    end if;
  exception when others then v_extras := '';
  end;

  begin
    if nullif(btrim(o.errand_description), '') is not null then
      v_extras := v_extras || E'\nFavor: ' || left(btrim(o.errand_description), 150);
    end if;
    if nullif(btrim(o.customer_notes), '') is not null then
      v_extras := v_extras || E'\nNota: ' || left(btrim(o.customer_notes), 120);
    end if;
  exception when others then null;
  end;

  return '🛎️ PEDIDO NOVO — ' || public._alerta_quem(o.user_id, o.customer_name, o.client_phone)
      || E'\nLoja: '   || v_loja
      || E'\n'         || to_char(v_total, 'FM999999990.00') || ' EUR · ' || v_pag
      || E'\nQuando: ' || case when o.scheduled_for is not null
                               then 'ENCOMENDA para ' || public._alerta_quando(o.scheduled_for)
                               else 'agora' end
      || v_extras
      || E'\n#'        || left(o.id, 8);
end
$function$;
