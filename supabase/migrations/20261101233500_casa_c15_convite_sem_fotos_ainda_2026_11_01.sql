-- Missão app-fechar-2026-11-01 · B1 Casa, achado C15
-- (docs/propostas/revisao-casa-peso-convidado-2026-11-01.md): o convite a orçar sai dentro de
-- casa_criar_pedido, ANTES de a app subir as fotos, e dizia "Vê as fotos e envia o teu preço.".
-- Só muda essa frase para "Abre o pedido e envia o teu preço." (as fotos aparecem no pedido
-- logo que sobem). Não mexe em valores nem em dinheiro.

CREATE OR REPLACE FUNCTION public._casa_convidar(p_pedido_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b casa_pedidos;
  e record;
  v_ja int;
  v_n int := public._casa_int('casa_quote_convidar_n', 6);
  v_expira timestamptz;
  v_feitos int := 0;
BEGIN
  SELECT * INTO b FROM casa_pedidos WHERE id = p_pedido_id FOR UPDATE;
  IF b.id IS NULL OR b.estado <> 'orcamentos' THEN RETURN 0; END IF;
  IF (SELECT count(*) FROM casa_orcamentos WHERE pedido_id = b.id AND estado = 'enviado')
       >= public._casa_int('casa_quote_max_pros', 3) THEN RETURN 0; END IF;
  SELECT count(*) INTO v_ja FROM casa_ofertas WHERE pedido_id = b.id AND tipo = 'convite_orcamento';
  v_expira := b.created_at + make_interval(hours => public._casa_int('casa_quote_pedido_horas', 48));

  FOR e IN
    SELECT x.* FROM public._casa_elegiveis(p_pedido_id) x
     WHERE NOT EXISTS (SELECT 1 FROM casa_ofertas co WHERE co.pedido_id = b.id AND co.profissional_id = x.profissional_id)
     LIMIT GREATEST(v_n - v_ja, 0)
  LOOP
    INSERT INTO casa_ofertas (pedido_id, profissional_id, user_id, tipo, expira_em, tinha_aparelho, ronda)
    VALUES (b.id, e.profissional_id, e.user_id, 'convite_orcamento', v_expira, e.tem_aparelho, 1);
    BEGIN
      PERFORM public.registar_oferta('casa', b.id, e.profissional_id, e.user_id, e.nome, e.tem_aparelho,
                                     GREATEST(1, (extract(epoch FROM (v_expira - now())) / 60)::int));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    -- 1.13: o primeiro aviso de um pedido de orçamento ainda não tem valor (exceção escrita no ESPEC).
    -- C15 (01/11/2026): as fotos sobem depois deste aviso; não prometer "Vê as fotos".
    PERFORM public._casa_notificar(e.user_id, 'handyman', 'casa_offer', 'Pedido de orçamento Casa',
      COALESCE((SELECT s.nome FROM casa_servicos s WHERE s.id = b.servico_id), 'Trabalho') || ' em '
      || COALESCE(NULLIF(b.address_city, ''), 'Guarda') || '. Abre o pedido e envia o teu preço.', b.id);
    v_feitos := v_feitos + 1;
  END LOOP;

  UPDATE casa_pedidos SET convites_enviados_em = now() WHERE id = b.id;
  IF v_ja + v_feitos = 0 THEN
    PERFORM public._casa_notificar_admin('Casa sem profissional para orçar',
      'Pedido de orçamento ' || b.id || ' (' || b.oficio || ') sem profissional disponível.');
  END IF;
  RETURN v_feitos;
END $function$;
