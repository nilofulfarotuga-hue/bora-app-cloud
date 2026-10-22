-- N3b · P4 · lavagens: por escrita direta (API), o cliente e o lavador só mudam o que a app escreve.
-- Preparado na missão fechar-pendencias-2026-10-20 (d/pronto/P4_aplicar.sql, 21/10) e aplicado por
-- ordem do Danilo no prompt de 22/10 04:33, passo 3b ("fechar ... as colunas de dinheiro das lavagens
-- a quem não é admin ... aplicar"). Não muda preços, valores, políticas nem dados: só quem pode escrever.
--
-- Hoje a política carwash_bookings_update_own deixa o cliente e o lavador mudar QUALQUER coluna da sua
-- lavagem: estado, pagamento, ganho do lavador, total. A app só escreve uma coisa por escrita direta:
-- o cliente anexa a foto (carwash_store.dart:372, photos_client). Tudo o resto vai pelas funções do
-- servidor (create_carwash_booking, cancel_carwash_booking, carwash_confirm_completion, as do lavador e
-- as do admin) e pela Edge carwash-checkout (chave de serviço), que não passam por aqui.
-- Um gatilho que, numa escrita direta de quem não é admin, só deixa mudar photos_client (e updated_at),
-- e photos_client só pelo próprio cliente da lavagem (revisor N3b, achado 3: o lavador não troca as
-- fotos que o cliente tirou ao carro, que são a prova numa queixa).
--
-- A LEITURA das colunas de dinheiro (total, ganho do lavador, taxa Bora) continua aberta ao cliente e ao
-- lavador da própria lavagem: a app lê a linha inteira (carwash_store.dart:178/231, washer_store.dart:
-- 139/159, select()), por isso tirar a leitura de colunas parte as duas apps. Para a fechar é preciso
-- primeiro mudar a app (ler só as colunas de que cada um precisa), publicar nas 3 plataformas, e só
-- depois tirar a leitura na base. Escrito para o Danilo em
-- .claude/.ai/missoes/fechar-pendencias-2026-10-20/RELATORIO-N3b.md (secção PARA O DANILO).
CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_novo  jsonb;
  v_velho jsonb;
  v_quais text;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.photos_client IS DISTINCT FROM OLD.photos_client
     AND auth.uid() IS DISTINCT FROM OLD.client_user_id THEN
    RAISE EXCEPTION 'lavagem_fotos_so_do_cliente' USING ERRCODE = '42501';
  END IF;
  v_novo  := to_jsonb(NEW) - 'photos_client' - 'updated_at';
  v_velho := to_jsonb(OLD) - 'photos_client' - 'updated_at';
  IF v_novo IS DISTINCT FROM v_velho THEN
    SELECT string_agg(n.key, ', ' ORDER BY n.key) INTO v_quais
      FROM jsonb_each(v_novo) n WHERE n.value IS DISTINCT FROM (v_velho -> n.key);
    RAISE EXCEPTION 'lavagem_so_pelo_servidor (%)', v_quais USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._lavagem_escrita_direta_guarda() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER a00_lavagem_escrita_direta_guarda
  BEFORE UPDATE ON public.carwash_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public._lavagem_escrita_direta_guarda();
