-- BLOCO 5 — 2026-09-07
-- Quem fica a dever a Bora tem de ver PARA ONDE pagar, dentro da app. Ate hoje
-- o cartao do estafeta dizia "vais pagar via MBWay segunda-feira" e nao dizia
-- o numero — a pessoa tinha de perguntar.
--
-- Porque nao se usa a `get_setting` generica aqui: essa devolve QUALQUER chave
-- e esta aberta a qualquer utilizador. Uma janela estreita e melhor do que uma
-- porta aberta, mesmo que hoje desse o mesmo resultado.
CREATE OR REPLACE FUNCTION public.bora_mbway_para_cobranca()
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(value #>> '{}', '') FROM platform_settings WHERE key = 'bora_mbway_phone';
$function$;

REVOKE ALL ON FUNCTION public.bora_mbway_para_cobranca() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bora_mbway_para_cobranca() TO authenticated;;
