-- Embaixador IPG — ajuste do painel (missão guarda-primeiro-2026-10-26).
-- admin_embaixador_guardar: campo a NULL = fica como está; texto vazio = apaga.
-- Assim o interruptor ligar/desligar do painel não apaga o nome nem a conta ligada.
-- admin_embaixador_resumo: devolve também o email da conta ligada (para o formulário).

create or replace function public.admin_embaixador_guardar(
  p_code text,
  p_nome text,
  p_telefone text,
  p_email text,
  p_notas text,
  p_ativo boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(p_code));
  v_e public.embaixadores;
  v_user uuid;
begin
  perform public._admin_op_guard();

  select * into v_e from public.embaixadores where code = v_code;
  if v_e.code is null then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_nao_e_de_embaixador');
  end if;

  v_user := v_e.user_id;
  if p_email is not null then
    if trim(p_email) = '' then
      v_user := null;
    else
      select id into v_user from public.users where lower(email) = lower(trim(p_email)) limit 1;
      if v_user is null then
        return jsonb_build_object('ok', false, 'motivo', 'email_sem_conta');
      end if;
    end if;
  end if;

  update public.embaixadores
     set nome = case when p_nome is null then nome else nullif(trim(p_nome), '') end,
         telefone = case when p_telefone is null then telefone else nullif(trim(p_telefone), '') end,
         notas = case when p_notas is null then notas else nullif(trim(p_notas), '') end,
         user_id = v_user,
         atualizado_em = now()
   where code = v_code;

  if p_ativo is not null then
    update public.promo_codes set is_active = p_ativo where code = v_code;
  end if;

  perform public.log_admin_action('embaixador_atualizado', 'promo_code', v_code,
    jsonb_build_object('code', v_code, 'nome', p_nome, 'ativo', p_ativo, 'conta_ligada', v_user is not null));

  return jsonb_build_object('ok', true, 'code', v_code, 'conta_ligada', v_user is not null);
end;
$$;

create or replace function public.admin_embaixador_resumo(p_semanas integer default 8)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_desde date := (date_trunc('week', now() at time zone 'Europe/Lisbon'))::date
                  - (greatest(coalesce(p_semanas, 8), 1) - 1) * 7;
  v jsonb;
begin
  perform public._admin_op_guard();

  select jsonb_build_object(
    'codigos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', e.code, 'nome', e.nome, 'user_id', e.user_id, 'email', u.email,
               'telefone', e.telefone, 'notas', e.notas, 'ativo', pc.is_active,
               'usos', pc.uses_count, 'max_usos', pc.max_uses,
               'valor_por_cliente_cents', e.valor_por_cliente_cents,
               'teto_semana_cents', e.teto_semana_cents)
             order by e.code)
      from public.embaixadores e
      join public.promo_codes pc on pc.code = e.code
      left join public.users u on u.id = e.user_id), '[]'::jsonb),
    'semanas', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.semana desc, s.code)
      from (
        select v.semana,
               v.code,
               count(*) filter (where v.motivo_exclusao is null) as elegiveis,
               count(*) filter (where v.motivo_exclusao is not null) as excluidos,
               least(count(*) filter (where v.motivo_exclusao is null) * max(e.valor_por_cliente_cents),
                     max(e.teto_semana_cents)) as a_pagar_cents
        from public.vw_embaixador_ipg v
        join public.embaixadores e on e.code = v.code
        where v.semana is not null and v.semana >= v_desde
        group by v.semana, v.code
      ) s), '[]'::jsonb),
    'clientes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', v.code, 'cliente', v.cliente, 'usou_em', v.usou_em,
               'entregue_em', v.entregue_em, 'semana', v.semana,
               'motivo_exclusao', v.motivo_exclusao)
             order by v.usou_em desc)
      from public.vw_embaixador_ipg v), '[]'::jsonb)
  ) into v;

  return v;
end;
$$;

revoke all on function public.admin_embaixador_resumo(integer) from public, anon;
revoke all on function public.admin_embaixador_guardar(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.admin_embaixador_resumo(integer) to authenticated;
grant execute on function public.admin_embaixador_guardar(text, text, text, text, text, boolean) to authenticated;
