-- PUBLICAÇÃO 2 da Casa — passo 3: ligar a Casa para TODOS e pôr o selo "Novo" durante 14 dias.
-- Ordem do Danilo (09/11/2026 07:02): "publique já … deixa publicada como novidade".
--
-- Pelas funções do painel (Casa > Configurações): admin_casa_interruptor(true) e
-- admin_casa_guardar_definicao('casa_novo_ate', 'AAAA-MM-DD'). A data é calculada AQUI, no dia em que se
-- corre: hoje em Lisboa + 14 dias (o selo aparece até ao fim desse dia). Para mudar depois: painel >
-- Casa > Configurações > Novidade.
-- Pré-requisito: passo 1 (a chave casa_novo_ate existe). Idempotente.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_ate text := to_char((now() at time zone 'Europe/Lisbon')::date + 14, 'YYYY-MM-DD');
  r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  perform set_config('bora.agente', 'publicacao2-casa', true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  if not public._casa_valores_validos() then raise exception 'valores_por_autorizar: nao se liga a Casa'; end if;
  if not exists (select 1 from public.platform_settings where key = 'casa_novo_ate') then
    raise exception 'falta o passo 1 (migracao 20261109074000_casa_novidade_selo_novo)';
  end if;

  r := public.admin_casa_interruptor(true);
  raise notice 'interruptor: %', r;
  r := public.admin_casa_guardar_definicao('casa_novo_ate', to_jsonb(v_ate));
  raise notice 'selo Novo ate %: %', v_ate, r;
  if coalesce((r ->> 'valores_reabertos')::boolean, false) then
    raise exception 'a definicao do selo reabriu os valores autorizados (nao devia): desfeito';
  end if;
end
$pub$;

-- Prova (lê de volta): o que o cliente recebe e as duas definições.
select (public.casa_config() ->> 'visivel') as casa_visivel,
       (public.casa_config() ->> 'valores_autorizados') as valores_autorizados,
       jsonb_array_length(public.casa_config() -> 'servicos') as servicos_visiveis,
       (select value::text from public.platform_settings where key = 'casa_enabled') as casa_enabled,
       (select value::text from public.platform_settings where key = 'casa_novo_ate') as casa_novo_ate,
       public.get_setting('casa_novo_ate')::text as o_que_a_app_le;
