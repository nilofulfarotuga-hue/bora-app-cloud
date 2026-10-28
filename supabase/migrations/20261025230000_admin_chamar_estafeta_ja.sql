-- Missão botao-chamar-estafeta-ja-2026-10-25. Pedido do Danilo, 25/10/2026 22:16:
-- "tem um botão para mim chamar. Porque é 15 minutos se eu ver que vai demorar. Mas como ela falou,
--  5 minutos tá pronto, então pode chamar já."
-- Encomendas por telefone (restaurants.order_by_phone): hoje o estafeta só é chamado depois de
-- dispatch_delay_minutes pelo encomendas_telefone_relogio. Este botão do painel liberta JÁ, pelo mesmo
-- caminho do relógio (app.phone_order_release + preparing → callingDriver), com auditoria.
create or replace function public.admin_chamar_estafeta_ja(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_nome text; v_n int; e public.encomendas_telefone; v_status text;
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;

  select * into e from public.encomendas_telefone where order_id = p_order_id for update;
  if e.order_id is null then return jsonb_build_object('ok', false, 'motivo', 'nao_e_encomenda_por_telefone'); end if;
  if e.cancelado_em is not null then return jsonb_build_object('ok', false, 'motivo', 'encomenda_cancelada'); end if;
  if e.libertado_em is not null then return jsonb_build_object('ok', false, 'motivo', 'estafeta_ja_chamado'); end if;

  select status into v_status from public.orders where id = p_order_id;
  if v_status is distinct from 'preparing' then
    return jsonb_build_object('ok', false, 'motivo', 'pedido_nao_esta_em_preparacao', 'estado', v_status);
  end if;

  select coalesce(u.name, u.email) into v_nome from public.users u where u.id = auth.uid();
  -- se ainda ninguém tinha carregado "Encomendado à loja", fica registado agora
  update public.encomendas_telefone
     set encomendado_em = coalesce(encomendado_em, now()),
         encomendado_por = coalesce(encomendado_por, auth.uid()),
         encomendado_por_nome = coalesce(encomendado_por_nome, v_nome)
   where order_id = p_order_id;

  perform set_config('app.phone_order_release', 'true', true);
  perform set_config('app.order_transition_source', 'admin_chamar_estafeta_ja', true);
  update public.orders set status = 'callingDriver' where id = p_order_id and status = 'preparing';
  get diagnostics v_n = row_count;
  perform set_config('app.phone_order_release', 'false', true);
  if v_n <> 1 then return jsonb_build_object('ok', false, 'motivo', 'nao_libertou'); end if;

  update public.encomendas_telefone set libertado_em = now() where order_id = p_order_id;

  insert into public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), 'chamar_estafeta_ja', 'order', p_order_id,
          jsonb_build_object('restaurant_id', e.restaurant_id, 'encomendado_em', e.encomendado_em,
                             'origem', 'painel: encomendas por telefone'));

  return jsonb_build_object('ok', true, 'chamado_as', to_char(now() at time zone 'Europe/Lisbon', 'HH24:MI'));
end $function$;

revoke all on function public.admin_chamar_estafeta_ja(text) from public, anon;
grant execute on function public.admin_chamar_estafeta_ja(text) to authenticated;
comment on function public.admin_chamar_estafeta_ja(text) is
  'Painel: chama o estafeta JÁ numa encomenda por telefone (sem esperar dispatch_delay_minutes). Só admin, auditado. Missão botao-chamar-estafeta-ja-2026-10-25.';

-- O alerta (Telegram + push que abre /admin/encomendas-telefone) passa a lembrar o botão novo.
create or replace function public._encomenda_telefone_alertar(p_order_id text, p_vez integer)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare j jsonb; v_msg text;
begin
  j := public.encomenda_telefone_resumo(p_order_id);
  if j is null then return; end if;
  v_msg := case when p_vez <= 1 then '📞 LIGAR À LOJA — pedido novo'
                else '📞 AINDA POR ENCOMENDAR (' || p_vez || '.º aviso)' end
        || E'\n' || (j->>'texto')
        || E'\nNo painel: "Encomendado à loja" depois de ligar; se a loja disser que fica pronto antes, "Chamar entregador já".';
  begin perform public._telegram_admin(v_msg);
  exception when others then raise warning 'encomenda_telefone: telegram falhou: %', sqlerrm; end;
  begin
    perform public.notify_admin_urgent_push(
      'phone_order_call', v_msg, 'order', p_order_id,
      jsonb_build_object('telefone', j->>'telefone', 'tel_link', 'tel:' || replace(coalesce(j->>'telefone', ''), ' ', ''),
                         'total_balcao', j->'total_balcao', 'aviso', p_vez),
      '/admin/encomendas-telefone');
  exception when others then raise warning 'encomenda_telefone: push falhou: %', sqlerrm; end;
  update public.encomendas_telefone
     set alertas = p_vez, ultimo_alerta_em = now(),
         resumo = j->>'texto', total_balcao = (j->>'total_balcao')::numeric
   where order_id = p_order_id;
end $function$;
