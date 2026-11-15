DO $prova$ DECLARE r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; su text; BEGIN
EXECUTE $q$
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
$function$
$q$;
su := session_user;
r1 := public.devolver_tokens_do_pedido('45e8e3d2-a278-48ff-b1bb-462b3a706b47', 'prova-c3-rollback');
r2 := public.consumir_tokens_do_pedido('45e8e3d2-a278-48ff-b1bb-462b3a706b47');
r3 := public.reconsumir_tokens_pedido_reativado('45e8e3d2-a278-48ff-b1bb-462b3a706b47');
r4 := public.reconsumir_tokens_pedido_reativado('45e8e3d2-a278-48ff-b1bb-462b3a706b47');
RAISE EXCEPTION 'PROVA-ROLLBACK su=% | devolver=% | consumir(o erro)=% | reconsumir=% | reconsumir2=%', su, r1, r2, r3, r4;
END $prova$;
