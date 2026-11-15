-- Texto aplicado em produção a 15/11/2026 (versão 20261115154444, pela Claude.ai; migração C3).
-- O servidor guardou só o carregador (net._http_response id 157896, sha256 26e9ae656c5c6d4e781dd313c57236a447c3d5b57821049753480f5b6e52d799);
-- o SQL que correu é este, igual byte a byte a docs/propostas/manha-15-11/C3-20261115100000_reconsumir_tokens_pedido_reativado.sql.

-- DESTINO: supabase/migrations/20261115100000_reconsumir_tokens_pedido_reativado.sql
-- manha-15-11 bloco C3 (autorizo do Danilo 15/11/2026 08:50, erros de dinheiro do MB WAY).
--
-- O ERRO: um pedido MB WAY cancelado pela app por `payment_failed` devolve os tokens
-- (devolver_tokens_do_pedido marca as linhas de pedido_tokens_gastos como devolvidas).
-- Se o pagamento entra depois, o stripe-webhook REATIVA o pedido, mas os tokens não se
-- voltam a gastar: consumir_tokens_do_pedido vê linhas no registo e responde
-- already_applied. O cliente fica com o desconto E com os tokens.
--
-- A CORREÇÃO: esta função volta a gastar os tokens de um pedido reativado, só quando
-- TODAS as linhas do registo estão devolvidas (nada ativo). Gasta pela mesma regra de
-- consumir_tokens_do_pedido (mais antigos primeiro, valor de token_value_cents_x100).
-- Se o cliente já não tiver tokens chega, NÃO falha o webhook: gasta o que houver e
-- devolve o que falta, para o painel avisar (decisão de dinheiro fica com o Danilo).
-- Não muda valores, preços nem a regra de metade dos tokens.

create or replace function public.reconsumir_tokens_pedido_reativado(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_o       record;
  v_x100    numeric;
  v_precisa integer;
  v_falta   integer;
  v_row     record;
  v_usa     integer;
  v_total   integer := 0;
begin
  -- só o servidor (service_role) chama isto: nunca o cliente
  if coalesce(auth.role(), '') <> 'service_role' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'reconsumir_tokens_pedido_reativado: so o servidor' using errcode = '42501';
  end if;

  select id, user_id, coalesce(tokens_applied_value_cents, 0) as tv
    into v_o from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'pedido_nao_encontrado');
  end if;
  if v_o.tv <= 0 or v_o.user_id is null then
    return jsonb_build_object('ok', true, 'tokens', 0, 'motivo', 'pedido_sem_tokens');
  end if;
  -- ainda há tokens gastos e não devolvidos: nada a fazer (idempotente)
  if exists (select 1 from public.pedido_tokens_gastos
              where order_id = p_order_id and devolvido_em is null) then
    return jsonb_build_object('ok', true, 'already_applied', true);
  end if;
  -- nunca houve registo (pedido de antes de 28/10): o normal trata
  if not exists (select 1 from public.pedido_tokens_gastos where order_id = p_order_id) then
    return public.consumir_tokens_do_pedido(p_order_id);
  end if;

  v_x100 := coalesce(nullif(public.get_setting('token_value_cents_x100') #>> '{}', '')::numeric, 50);
  v_precisa := ceil(v_o.tv * 100.0 / v_x100)::integer;
  v_falta := v_precisa;

  for v_row in
    select id, amount, expires_at, role
      from public.bora_tokens
     where user_id = v_o.user_id and is_used = false and expires_at > now()
     order by expires_at asc, created_at asc
     for update
  loop
    exit when v_falta = 0;
    v_usa := least(v_row.amount, v_falta);
    update public.bora_tokens set is_used = true, used_at = now() where id = v_row.id;
    if v_row.amount > v_usa then
      insert into public.bora_tokens (user_id, role, amount, expires_at)
        values (v_o.user_id, v_row.role, v_row.amount - v_usa, v_row.expires_at);
    end if;
    insert into public.pedido_tokens_gastos (order_id, user_id, token_id, role, quantidade, expira_em)
      values (p_order_id, v_o.user_id, v_row.id, v_row.role, v_usa, v_row.expires_at);
    v_falta := v_falta - v_usa;
    v_total := v_total + v_usa;
  end loop;

  update public.orders set tokens_applied_count = v_total where id = p_order_id;
  return jsonb_build_object('ok', v_falta = 0, 'tokens', v_total, 'faltam', v_falta,
                            'motivo', case when v_falta > 0 then 'tokens_insuficientes' end);
end;
$function$;

revoke all on function public.reconsumir_tokens_pedido_reativado(text) from public, anon, authenticated;
grant execute on function public.reconsumir_tokens_pedido_reativado(text) to service_role;

-- PROVA (em transação, com rollback), depois de aplicar:
-- begin;
--   -- pedido de teste com tokens: consumir -> devolver -> reconsumir
--   select public.consumir_tokens_do_pedido('<id>');            -- gasta N
--   select public.devolver_tokens_do_pedido('<id>', 'teste');    -- devolve N
--   select public.consumir_tokens_do_pedido('<id>');            -- already_applied (o erro)
--   select public.reconsumir_tokens_pedido_reativado('<id>');   -- gasta N outra vez
--   select public.reconsumir_tokens_pedido_reativado('<id>');   -- already_applied (idempotente)
-- rollback;
