-- M10 b2-limpeza (09/11/2026), item 2.9 — ordem do Danilo de 08/11/2026: a categoria Casa & Manutenção FICA
-- DESLIGADA PARA TODOS (clientes, testadores, contas demo e admins) até ele a ligar.
--
-- No ar (31/10): _casa_visivel() = casa_enabled OU (testador da lista casa_testadores, conta demo ou admin).
-- Com casa_enabled = false, testadores/demo/admins continuavam a ver o ladrilho da home, o atalho da pesquisa e
-- podiam criar pedidos (casa_criar_pedido também pergunta a _casa_visivel()).
-- Agora: só o interruptor conta. casa_enabled = false → ninguém vê nem cria; quando ele ligar (painel > Casa >
-- Definições, ou platform_settings.casa_enabled = true) volta a regra normal: todos veem.
-- Não muda: o painel admin da Casa (as admin_casa_* passam por _casa_exigir_admin, não por esta função), a
-- candidatura e o lado do profissional, _casa_testador (fica, sem uso aqui) e nenhum valor.
-- Prova em rollback no relatório M10 b2-limpeza (admin, demo e conta normal: false com o interruptor desligado;
-- true para a conta normal com o interruptor ligado).
-- Reverter: repor o corpo de 31/10 (SELECT public._casa_bool('casa_enabled', false) OR (auth.uid() IS NOT NULL
--   AND (public._casa_testador(auth.uid()) OR public.is_admin()))).

create or replace function public._casa_visivel()
returns boolean language sql stable security definer set search_path to 'public'
as $function$
  SELECT public._casa_bool('casa_enabled', false)
$function$;