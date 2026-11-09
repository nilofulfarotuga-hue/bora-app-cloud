-- PUBLICAÇÃO 2 da Casa — REVERTER (só se for preciso tirar a novidade do ar). Não apaga nada:
-- desliga a Casa, desliga o selo e desliga a faixa. A aprovação do Danilo e a difusão já enviada ficam.
-- (Uma notificação enviada não se desenvia.)
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  perform set_config('bora.agente', 'publicacao2-casa-reverter', true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  perform public.admin_casa_interruptor(false);
  if exists (select 1 from public.platform_settings where key = 'casa_novo_ate') then
    perform public.admin_casa_guardar_definicao('casa_novo_ate', to_jsonb(''::text));
  end if;
  update public.home_banners set ativo = false, atualizado_em = now()
   where tipo_destino = 'categoria' and destino = 'casa' and ativo;
  perform public.log_admin_action('home_banner_desligar'::text, 'home_banners'::text, 'categoria:casa'::text,
    jsonb_build_object('via', 'publicacao2-casa-reverter'));
end
$pub$;

select (public.casa_config() ->> 'visivel') as casa_visivel,
       public.get_setting('casa_novo_ate')::text as selo,
       (select count(*) from public.home_banners where destino = 'casa' and ativo) as faixas_ativas;
