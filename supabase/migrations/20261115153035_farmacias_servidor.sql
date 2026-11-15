-- Texto aplicado em produção a 15/11/2026 (versão 20261115153035, pela Claude.ai).
-- O servidor guardou só o carregador (net._http_response id 157857, sha256 96ca79f3c952852c2d05b4602b617fc28ec88ebcb01c09b6c336933023715df6);
-- o SQL que correu é este, igual byte a byte a docs/propostas/app-15-11/farmacias_servidor.PROPOSTA.sql.

-- PROPOSTA (missão app-15-11, 15/11/2026; aprovada para preparar pela Claude.ai às 10:48,
-- "não é preço nem comissão, eu aplico"). Nome sugerido: 20261115113000_farmacias_servidor.
-- Partiu das definições EM PRODUÇÃO lidas por SELECT a 15/11 ~11:05 (não do ficheiro antigo).
-- Achados de origem: e2e_log 9127 (revisor de contexto limpo).
--
-- O QUE MUDA (só isto):
--  A) farmacia_botoes_visiveis: os botões de receita só aparecem numa farmácia ESCONDIDA
--     (so_lista_permissao, a fase de demonstração) ou quando a entrega real de receitas estiver
--     ligada (platform_settings.pharmacy_prescription_real_orders_enabled = true). Hoje, se uma
--     farmácia abrir ao público, o cliente envia a receita, a farmácia prepara e responde, e a
--     confirmação é recusada (RECEITA_REAL_POR_LIGAR): beco sem saída e trabalho da farmácia em vão.
--     Em produção hoje: farmacia-se-guarda e farmacia-teixeira-guarda estão escondidas (nada muda
--     para elas); wells-guarda está aberta mas com o modo 'desligado' (já não mostrava botões).
--  B) farmacia_prescricao_fechar_demo(p_id): a farmácia fecha um pedido de DEMONSTRAÇÃO confirmado
--     ("levantado / entregue"). Hoje só o admin o consegue (admin_prescricao_forcar) e todos ficam
--     "confirmado" para sempre. Só aceita is_demo = true: o extrato da farmácia ignora os de
--     demonstração (NOT is_demo em farmacias_loja_01_dinheiro), por isso nunca toca em dinheiro.
--     Os pedidos reais fecham-se pelo fluxo do estafeta, quando a entrega real for ligada.
--  C) Paridade admin (só leitura): admin_farmacia_chegadas_listar e admin_farmacia_lembretes_listar.
--
-- O QUE NÃO MUDA: prescricao_confirmar (continua a recusar em farmácia aberta), preços, taxas,
-- comissões, extrato, RLS. Ligar a entrega real de receitas (pedido com estafeta e cobrança) é outra
-- missão, com o "autorizo" do Danilo.
--
-- FICA POR DECIDIR (não está aqui): a RLS de pedidos_prescricao deixa o dono da farmácia ler a
-- coluna codigo_entrega (o código que o cliente dá ao estafeta). Tirar-lha obriga a app a ler
-- colunas explícitas em vez de "*"; só importa quando houver entregas reais.

-- ---- A) botões de receita só onde a confirmação funciona -----------------------------------
create or replace function public.farmacia_botoes_visiveis(p_restaurant_id text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select coalesce((
    select r.category = 'pharmacy'
       and public.loja_visivel_para_mim(r.id)
       -- app-15-11: escondida (demonstração) ou entrega real ligada; senão a confirmação recusa.
       and (coalesce(r.so_lista_permissao, false)
            or public._setting_txt('pharmacy_prescription_real_orders_enabled', 'false') = 'true')
       and (
         r.pharmacy_prescription_mode = 'publico'
         or (r.pharmacy_prescription_mode = 'so_lista' and auth.uid() is not null and (
               public.is_admin() or r.user_id = auth.uid() or r.user_ = auth.uid()
               or exists (select 1 from public.loja_lista_permissao l where l.restaurant_id = r.id and l.user_id = auth.uid())))
       )
      from public.restaurants r where r.id = p_restaurant_id
  ), false);
$function$;
-- (CREATE OR REPLACE mantém as permissões: execute para anon e authenticated, como hoje.)

-- ---- B) a farmácia fecha um pedido de demonstração -----------------------------------------
create or replace function public.farmacia_prescricao_fechar_demo(p_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v record;
begin
  select pp.id, pp.estado, coalesce(pp.is_demo, false) as demo, r.user_id as dono1, r.user_ as dono2
    into v
    from public.pedidos_prescricao pp
    join public.restaurants r on r.id = pp.restaurant_id
   where pp.id = p_id
   for update of pp;
  if not found or auth.uid() is null
     or (auth.uid() is distinct from v.dono1 and auth.uid() is distinct from v.dono2 and not public.is_admin()) then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if not v.demo then
    raise exception 'SO_DEMONSTRACAO: Este pedido fecha-se na entrega pelo estafeta.' using errcode = 'P0001';
  end if;
  if v.estado <> 'confirmado' then
    raise exception 'NAO_FECHAVEL: Este pedido já não está à espera de ser levantado.' using errcode = 'P0001';
  end if;
  update public.pedidos_prescricao set estado = 'entregue', entregue_em = now() where id = p_id;
  perform public._prescricao_avisar(p_id, 'cliente', 'prescricao_resposta', 'O seu pedido à farmácia mudou',
    'A farmácia marcou o pedido como levantado.');
  return jsonb_build_object('estado', 'entregue');
end $function$;
revoke all on function public.farmacia_prescricao_fechar_demo(uuid) from public, anon;
grant execute on function public.farmacia_prescricao_fechar_demo(uuid) to authenticated;

-- ---- C) paridade admin: chegadas tardias e lembretes mensais (só leitura) -------------------
create or replace function public.admin_farmacia_chegadas_listar(p_restaurant_id text default null, p_limite integer default 200)
 returns setof public.pedido_chegada_tardia
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
    select c.* from public.pedido_chegada_tardia c
     where p_restaurant_id is null or c.restaurant_id = p_restaurant_id
     order by c.criado_em desc
     limit least(greatest(coalesce(p_limite, 200), 1), 1000);
end $function$;
revoke all on function public.admin_farmacia_chegadas_listar(text, integer) from public, anon;
grant execute on function public.admin_farmacia_chegadas_listar(text, integer) to authenticated;

create or replace function public.admin_farmacia_lembretes_listar(p_restaurant_id text default null, p_limite integer default 200)
 returns setof public.farmacia_lembretes
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
    select l.* from public.farmacia_lembretes l
     where p_restaurant_id is null or l.restaurant_id = p_restaurant_id
     order by l.created_at desc
     limit least(greatest(coalesce(p_limite, 200), 1), 1000);
end $function$;
revoke all on function public.admin_farmacia_lembretes_listar(text, integer) from public, anon;
grant execute on function public.admin_farmacia_lembretes_listar(text, integer) to authenticated;

-- ---- Prova dentro da migração (se falhar, nada fica aplicado) -------------------------------
-- Simula, dentro desta transação, o dono de cada farmácia (o que o servidor vê quando ele abre a app).
do $$
declare
  r record;
  v_flag boolean := public._setting_txt('pharmacy_prescription_real_orders_enabled', 'false') = 'true';
  v_ve boolean;
  v_regressoes int := 0;
  v_becos int := 0;
begin
  if not exists (select 1 from pg_proc where proname = 'farmacia_prescricao_fechar_demo') then
    raise exception 'farmacias_servidor: funcao farmacia_prescricao_fechar_demo em falta';
  end if;
  for r in select id, user_id, coalesce(so_lista_permissao, false) as escondida, pharmacy_prescription_mode as modo
             from public.restaurants where category = 'pharmacy' and user_id is not null loop
    perform set_config('request.jwt.claims', json_build_object('sub', r.user_id, 'role', 'authenticated')::text, true);
    v_ve := public.farmacia_botoes_visiveis(r.id);
    -- escondida em so_lista/publico: o dono continua a ver os botões (igual a antes)
    if r.escondida and r.modo in ('so_lista', 'publico') and not v_ve then
      v_regressoes := v_regressoes + 1;
    end if;
    -- aberta ao público com a entrega real desligada: os botões não podem aparecer (era o beco)
    if not r.escondida and not v_flag and v_ve then
      v_becos := v_becos + 1;
    end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if v_regressoes > 0 then
    raise exception 'farmacias_servidor: % farmacias escondidas deixaram de mostrar os botoes ao dono', v_regressoes;
  end if;
  if v_becos > 0 then
    raise exception 'farmacias_servidor: % farmacias abertas ainda mostram botoes sem entrega real', v_becos;
  end if;
  raise notice 'farmacias_servidor: aplicado e provado';
end
$$;
