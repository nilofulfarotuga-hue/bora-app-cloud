-- Missão checkin-escada-premios-2026-11-04, bloco E (painel admin PT-BR):
--  - os degraus novos criados a 04/11 por MCP não tinham categoria e não apareciam no painel;
--  - criar degraus novos pelo painel (admin_update_setting só altera chaves que já existem);
--  - custo dos prémios por mês e por loja.
-- Não mexe em preços, comissões nem tokens.

update public.platform_settings
   set category = 'marketing'
 where category is null
   and (key like 'checkin\_marco\_%' or key = 'checkin_premio_intervalo_dias');

create or replace function public.admin_checkin_degrau_criar(p_chave text, p_marco jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_admin record;
  v_chave text := lower(trim(coalesce(p_chave, '')));
  v_key text;
  v_tipo text := p_marco ->> 'tipo';
  v_dia int;
  v_m jsonb;
begin
  select admin_id, admin_email into v_admin from public._admin_op_guard();
  if v_chave !~ '^[a-z0-9_]{2,40}$' then raise exception 'chave_invalida: só letras minúsculas, números e _'; end if;
  v_key := 'checkin_marco_' || v_chave;
  if exists (select 1 from public.platform_settings where key = v_key) then raise exception 'degrau_ja_existe: %', v_key; end if;
  if v_tipo not in ('produto', 'servico') then raise exception 'tipo_invalido: produto ou servico'; end if;
  if coalesce(p_marco ->> 'dia', '') !~ '^[0-9]{1,3}$' then raise exception 'dia_invalido'; end if;
  v_dia := (p_marco ->> 'dia')::int;
  if v_dia < 1 or v_dia > 365 then raise exception 'dia_invalido'; end if;
  if nullif(trim(coalesce(p_marco ->> 'titulo', '')), '') is null then raise exception 'titulo_obrigatorio'; end if;
  if v_tipo = 'produto' then
    if not exists (select 1 from public.restaurants where id = p_marco ->> 'loja_id') then
      raise exception 'loja_nao_encontrada';
    end if;
    if not exists (select 1 from public.products where id = p_marco ->> 'produto_id' and restaurant_id = p_marco ->> 'loja_id') then
      raise exception 'produto_nao_e_desta_loja';
    end if;
  end if;
  v_m := p_marco || jsonb_build_object('chave', v_chave, 'dia', v_dia,
                                       'ativo', coalesce((p_marco ->> 'ativo')::boolean, false),
                                       'quantidade', greatest(coalesce((p_marco ->> 'quantidade')::int, 1), 1));
  insert into public.platform_settings (key, value, category, updated_at, updated_by)
  values (v_key, v_m, 'marketing', now(), v_admin.admin_id);
  perform public.log_admin_action('checkin_degrau_criado', 'platform_setting', null,
                                  jsonb_build_object('key', v_key, 'new', v_m));
  return v_m;
end;
$function$;
revoke all on function public.admin_checkin_degrau_criar(text, jsonb) from public, anon;
grant execute on function public.admin_checkin_degrau_criar(text, jsonb) to authenticated;

-- Custo dos prémios por mês e por loja (vales emitidos, não anulados; custo = o que a loja recebe).
create or replace function public.admin_checkin_premios_custos(p_meses int default 6)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v jsonb;
begin
  perform public._admin_op_guard();
  select coalesce(jsonb_agg(x order by x.mes desc, x.custo_cents desc), '[]'::jsonb) into v
    from (
      select to_char(date_trunc('month', c.emitido_em at time zone 'Europe/Lisbon'), 'YYYY-MM') as mes,
             coalesce(c.loja_id, '(serviço)') as loja_id,
             coalesce(r.name, case when c.tipo = 'servico' then 'Limpeza / lavagem' else c.loja_id end) as loja,
             count(*) as vales,
             count(*) filter (where c.estado = 'usado') as usados,
             sum(c.custo_cents)::bigint as custo_cents,
             sum(c.custo_cents) filter (where c.estado = 'usado')::bigint as custo_usados_cents
        from public.checkin_premios_vales c
        left join public.restaurants r on r.id = c.loja_id
       where c.estado <> 'anulado'
         and c.emitido_em >= date_trunc('month', now()) - make_interval(months => greatest(coalesce(p_meses, 6), 1) - 1)
       group by 1, 2, 3
    ) x;
  return v;
end;
$function$;
revoke all on function public.admin_checkin_premios_custos(int) from public, anon;
grant execute on function public.admin_checkin_premios_custos(int) to authenticated;
