-- PROPOSTA — reservas de mesa: a reserva PAGA só passa a 'pending' pelo webhook da Stripe, e
-- client_confirm_reservation_payment deixa de usar a coluna updated_at (que não existe) SEM abrir
-- a porta a "reservar sem pagar".
-- Missão fechar-tudo-15-11, 15/11/2026, Claude Code. Ordem da Claude.ai às 16:15, dentro do
-- "Autorizo tudo" do Danilo das 15:15; 2.ª versão depois da revisão do Juiz da Claude.ai (17:2x),
-- que BLOQUEOU a 1.ª. NADA DISTO FOI APLICADO: aplica a Claude.ai com execute_sql (ou
-- apply_migration) e guarda depois a migração em supabase/migrations/.
--
-- PORQUE A 1.ª VERSÃO FOI BLOQUEADA
--   * No ar (lido a 15/11), client_confirm_reservation_payment falha SEMPRE com 42703 (column
--     "updated_at" of relation "reservations" does not exist): public.reservations tem 27 colunas
--     e nenhuma com esse nome. O plpgsql só resolve o UPDATE quando ele corre, por isso a função foi
--     criada sem erro (migração 20260503020000_reservation_rpcs_sync.sql). md5(pg_get_functiondef)
--     no ar = e52f212e03458760171ee2d742c135c0; md5(prosrc) = 9b8677ae3a26dea148cc6ba67a8a366d.
--   * Por acaso, esse erro fechava uma porta: a função passa 'pending_payment' → 'pending' SEM ir à
--     Stripe. Tirar só o updated_at (1.ª versão) deixava o cliente criar a reserva e o pagamento
--     (create-reservation-payment-intent), NÃO pagar e chamar a função: a reserva ficava 'pending',
--     com prepayment_cents=300, e o parceiro via-a como uma reserva paga normal.
--
-- O QUE MUDA — public.client_confirm_reservation_payment(uuid)
--   1. Sem `, updated_at = NOW()` no UPDATE (era o 42703).
--   2. O UPDATE para 'pending' só corre quando COALESCE(prepayment_cents, 0) = 0, e a condição está
--      no próprio WHERE do UPDATE (atómica com a linha). A reserva com pré-pagamento passa a
--      'pending' SÓ pelo webhook da Stripe (confirm_reservation_payment_webhook, abaixo), que só
--      corre com o evento payment_intent.succeeded assinado pela Stripe e confere que o pagamento
--      é o gravado na reserva (pi_mismatch).
--   3. O aviso in-app ao parceiro fica dentro de IF FOUND: só sai quando a reserva mudou AGORA
--      (antes saía em cada chamada, também numa reserva que já estava 'pending').
--   4. `client_user_id IS DISTINCT FROM v_uid` em vez de `!=`: com `!=`, uma reserva sem cliente
--      (client_user_id NULL, ex.: criada pelo admin) passava a verificação (NULL != uid não é
--      verdadeiro) e qualquer cliente com o id a confirmava.
--   5. Resposta: quando muda, a mesma de sempre ({success:true, status:'pending'}); quando não muda
--      nada, {success:true, status:<estado atual>, waiting_payment_confirmation:<true se ainda
--      'pending_payment'>}. A app não lê a resposta (ReservationStore.confirmReservationPayment só
--      apanha o erro e recarrega a lista), por isso nada parte.
--   Igual: assinatura (p_reservation_id uuid), retorno jsonb, SECURITY DEFINER, search_path=public,
--   dono postgres, EXECUTE só para postgres, service_role e authenticated; erros auth_required,
--   reservation_not_found, not_your_reservation, invalid_status; o texto do aviso ao parceiro.
--
-- O QUE MUDA — public.confirm_reservation_payment_webhook(uuid, text)
--   (md5(pg_get_functiondef) no ar a 15/11 = fcde7d09713f743e0bbcb96ed6bfd576;
--    md5(prosrc) = b0d043ff95b464085b8344d3ceb7f7a5; EXECUTE só postgres e service_role.)
--   Quem a chama: só a Edge stripe-webhook (núcleo partilhado das duas contas,
--   _shared/stripe_webhook_core.ts:629), no payment_intent.succeeded com
--   metadata.purpose='reservation_prepayment'. A migração 20260515100001 dizia "NÃO notifica
--   parceiro — client_confirm_reservation_payment (fallback Flutter) trata"; como a função do
--   cliente deixa de passar a reserva paga a 'pending', o aviso muda-se para aqui. Exatamente:
--   1. O SELECT ... FOR UPDATE lê também restaurant_id, people e reserved_for (para o aviso).
--   2. O UPDATE ganha `AND status = 'pending_payment'`. Com o FOR UPDATE e a verificação de cima é
--      equivalente; serve para o FOUND querer dizer "mudou agora".
--   3. Depois do UPDATE, IF FOUND → o MESMO aviso in-app que a função do cliente mandava
--      (_push_in_app_notification: kind 'reservation', título 'Nova reserva pendente', texto
--      'Reserva para N pessoas em DD/MM HH24:MI', parceiro por restaurants.email = auth.users.email).
--      _push_in_app_notification nunca lança (EXCEPTION WHEN OTHERS → RETURN NULL): não estraga a
--      confirmação do pagamento.
--   Igual: assinatura, retornos ({ok,...}, already_confirmed, pi_mismatch, reservation_not_found),
--   SECURITY DEFINER, search_path=public, dono, acessos.
--
-- O QUE O CLIENTE E O PARCEIRO VEEM
--   * Cartão: depois da folha de pagamento a app diz "Reserva pendente!" como hoje; na lista, a
--     reserva pode aparecer uns segundos "à espera de pagamento" até o webhook chegar.
--   * MB WAY: o diálogo de espera já lê reservations.status até 'pending' (quem o põe é o webhook):
--     nada muda.
--   * Parceiro: o aviso "Nova reserva pendente" da reserva paga passa a sair quando a Stripe
--     confirma o pagamento. Hoje não sai nunca (a função do cliente falha com 42703 e a push FCM do
--     webhook também não sai: ACHADO 3).
--   * Reserva sem pré-pagamento: igual a antes (a função do cliente passa-a a 'pending' e avisa).
--   * Se o webhook falhar, a reserva paga fica em 'pending_payment' (já era o que acontecia, porque
--     a função do cliente falhava sempre) e o payments-reconciler dá o alarme: PI de reserva pago
--     com a reserva ainda em 'pending_payment' = achado 'pi_sem_entidade', crítico (repo,
--     payments-reconciler/index.ts:121-125).
--
-- O GATILHO trg_00_reservas_campos_protegidos NÃO TRAVA ESTAS FUNÇÕES (pg_trigger + pg_proc, 15/11)
--   Chama public._reservas_cliente_campos_protegidos(), que NÃO é SECURITY DEFINER e só recusa
--   quando current_user in ('authenticated','anon') e não is_admin(). As duas funções são SECURITY
--   DEFINER com dono postgres: durante o UPDATE delas o current_user é 'postgres' e a mudança de
--   estado passa. O cliente direto (PostgREST, current_user = authenticated) continua travado — e
--   também não consegue pôr prepayment_cents a 0 numa reserva paga para usar o caminho "sem
--   pré-pagamento" (prepayment_cents é um dos campos protegidos). A prova P4 mostra tudo isto.
--
-- ACHADOS (não corrigidos aqui — para a Claude.ai decidir)
--   1. INSERT direto — A MESMA PORTA, POR OUTRO LADO, CONTINUA ABERTA. A RLS
--      reservations_client_owner (FOR ALL, with check client_user_id = auth.uid()), o privilégio
--      de INSERT de authenticated em status, prepayment_cents, prepayment_pi e stripe_account
--      (information_schema.column_privileges, 15/11) e a falta de gatilho BEFORE INSERT que os
--      confira deixam o cliente criar uma reserva já em 'pending' (o default da coluna) com o
--      prepayment_cents e o prepayment_pi que quiser, sem pagar. Esta proposta fecha o caminho
--      pela RPC; "reservar sem pagar" só fica fechado de vez com um BEFORE INSERT que, para
--      authenticated/anon não-admin, obrigue status='pending_payment', prepayment_cents=0,
--      prepayment_pi null e stripe_account por defeito (as Edge create-*-reservation-payment-intent
--      inserem com a chave do servidor e não são afetadas). Mais grave: com
--      client_cancel_reservation, esta porta vira o reembolso de OUTRO pagamento — ver a nota
--      client_cancel_reservation_reembolso.md, nesta pasta.
--   2. cancel_orphan_reservation (SECURITY DEFINER, EXECUTE para authenticated) não confere quem
--      chama: quem souber o id da reserva e o do PI apaga a reserva 'pending_payment' de outra pessoa.
--   3. Zona vermelha, só lido NO REPO: _shared/stripe_webhook_core.ts (payment_intent.succeeded de
--      reserva) faz select('restaurant_id, guests') e a coluna guests não existe (é people) → a push
--      FCM "Nova reserva confirmada!" ao parceiro não sai.
--   4. O gatilho trg_reservation_notify_partner_new (AFTER INSERT, _reservas_pro_trg_notify_new)
--      já manda ao parceiro "Nova reserva pendente" (in-app + push pelo notify-partner) logo no
--      INSERT, com a reserva ainda em 'pending_payment' — antes de o cliente pagar, e também nas
--      que nunca são pagas. Com esta proposta a reserva paga recebe um 2.º aviso in-app quando o
--      webhook confirma. Sugestão (não feita aqui): o gatilho saltar 'pending_payment' e o webhook
--      usar _reservas_pro_notify_partner_push (in-app + push) — um aviso só, na hora certa.
--   5. A hora dos avisos sai em UTC (to_char sem 'Europe/Lisbon', aqui e no gatilho do INSERT):
--      certa no inverno, 1 h atrás no verão. Mantida igual de propósito (o aviso mudou de sítio,
--      não de texto).
--   Hoje há 0 linhas em reservations (SELECT por estado, 15/11): nada por corrigir para trás.

begin;

create or replace function public.client_confirm_reservation_payment(p_reservation_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE v_rsv record; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  -- fechar-tudo-15-11 (Juiz): IS DISTINCT FROM também recusa a reserva sem cliente (NULL).
  IF v_rsv.client_user_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('pending_payment', 'pending') THEN
    RAISE EXCEPTION 'invalid_status: %', v_rsv.status;
  END IF;

  -- fechar-tudo-15-11: sem o carimbo de atualização (essa coluna não existe em reservations; 42703).
  -- Juiz: só a reserva SEM pré-pagamento passa a 'pending' por aqui; a paga só pelo webhook da
  -- Stripe (confirm_reservation_payment_webhook), que confere o pagamento.
  UPDATE reservations SET status = 'pending'
  WHERE id = p_reservation_id AND status = 'pending_payment'
    AND COALESCE(prepayment_cents, 0) = 0;

  IF FOUND THEN
    -- Notify partner via in_app (also FCM via Edge Fn — fire-and-forget Flutter)
    -- Find partner user_id from restaurants table
    PERFORM _push_in_app_notification(
      (SELECT u.id FROM auth.users u
       JOIN restaurants r ON r.email = u.email
       WHERE r.id = v_rsv.restaurant_id LIMIT 1),
      'reservation',
      'Nova reserva pendente',
      'Reserva para ' || v_rsv.people || ' pessoas em ' ||
         to_char(v_rsv.reserved_for, 'DD/MM HH24:MI'),
      p_reservation_id::text
    );
    RETURN jsonb_build_object('success', true, 'status', 'pending');
  END IF;

  -- Nada mudou aqui: já estava 'pending', ou é paga e espera o webhook da Stripe.
  RETURN jsonb_build_object(
    'success', true,
    'status', v_rsv.status,
    'waiting_payment_confirmation', v_rsv.status = 'pending_payment'
  );
END;
$function$;

create or replace function public.confirm_reservation_payment_webhook(p_reservation_id uuid, p_payment_intent_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_reservation record;
BEGIN
  SELECT id, status, prepayment_pi, restaurant_id, people, reserved_for INTO v_reservation
  FROM public.reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF v_reservation IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;

  -- Idempotência: já confirmada (race com client_confirm_reservation_payment)
  IF v_reservation.status <> 'pending_payment' THEN
    RETURN jsonb_build_object('ok', true, 'already_confirmed', true,
                              'status', v_reservation.status);
  END IF;

  -- Validar PI (defesa contra spoofing de metadata)
  IF v_reservation.prepayment_pi IS DISTINCT FROM p_payment_intent_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pi_mismatch');
  END IF;

  UPDATE public.reservations
  SET status = 'pending'
  WHERE id = p_reservation_id AND status = 'pending_payment';

  -- fechar-tudo-15-11 (Juiz): o aviso ao parceiro da reserva PAGA sai daqui, quando a Stripe
  -- confirma o pagamento (client_confirm_reservation_payment já não passa a paga a 'pending').
  -- O mesmo aviso in-app, com o mesmo texto; _push_in_app_notification nunca lança.
  IF FOUND THEN
    PERFORM _push_in_app_notification(
      (SELECT u.id FROM auth.users u
       JOIN restaurants r ON r.email = u.email
       WHERE r.id = v_reservation.restaurant_id LIMIT 1),
      'reservation',
      'Nova reserva pendente',
      'Reserva para ' || v_reservation.people || ' pessoas em ' ||
         to_char(v_reservation.reserved_for, 'DD/MM HH24:MI'),
      p_reservation_id::text
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'reservation_id', p_reservation_id);
END;
$function$;

-- Os mesmos acessos de hoje (lidos a 15/11):
--   client_confirm_reservation_payment  {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
--   confirm_reservation_payment_webhook {postgres=X/postgres,service_role=X/postgres}
revoke all on function public.client_confirm_reservation_payment(uuid) from public, anon;
grant execute on function public.client_confirm_reservation_payment(uuid) to authenticated, service_role;
revoke all on function public.confirm_reservation_payment_webhook(uuid, text) from public, anon, authenticated;
grant execute on function public.confirm_reservation_payment_webhook(uuid, text) to service_role;

commit;

-- =====================================================================================================
-- PROVAS (só leitura; correr depois do commit)
-- =====================================================================================================
-- P1 — a coluna continua a não existir (esperado: 0)
-- select count(*) as tem_updated_at
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reservations' and column_name = 'updated_at';
--
-- P2 — as duas funções: o que mudou está lá e segurança, dono e acessos ficaram
--      (esperado, cliente:  false | true | true | true | true | {search_path=public} | postgres |
--                           {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
--                 webhook:  false | true | true | true | true | {search_path=public} | postgres |
--                           {postgres=X/postgres,service_role=X/postgres})
-- select p.proname,
--        pg_get_functiondef(p.oid) ~ 'updated_at' as usa_updated_at,
--        case p.proname when 'client_confirm_reservation_payment'
--             then pg_get_functiondef(p.oid) ~* 'coalesce\(prepayment_cents, 0\) = 0'
--             else pg_get_functiondef(p.oid) ~* 'and status = ''pending_payment''' end as so_sem_pre_ou_so_pendente,
--        case p.proname when 'client_confirm_reservation_payment'
--             then pg_get_functiondef(p.oid) ~* 'is distinct from v_uid'
--             else pg_get_functiondef(p.oid) ~* 'restaurant_id, people, reserved_for' end as guarda_ou_leitura,
--        pg_get_functiondef(p.oid) ~* 'if found then\s+(--[^\n]*\n\s*)*perform _push_in_app_notification' as aviso_dentro_do_found,
--        p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as dono, p.proacl::text as acessos,
--        md5(pg_get_functiondef(p.oid)) as md5_novo
--   from pg_proc p
--  where p.oid in ('public.client_confirm_reservation_payment(uuid)'::regprocedure,
--                  'public.confirm_reservation_payment_webhook(uuid,text)'::regprocedure);
--
-- P3 — o gatilho continua lá, ligado, e a função dele não é SECURITY DEFINER
--      (esperado: trg_00_reservas_campos_protegidos | O | false)
-- select t.tgname, t.tgenabled, p.prosecdef
--   from pg_trigger t join pg_proc p on p.oid = t.tgfoid
--  where t.tgrelid = 'public.reservations'::regclass and t.tgname = 'trg_00_reservas_campos_protegidos';
--
-- P4 — OPCIONAL, correr SOZINHO (escreve e desfaz: o bloco acaba em RAISE EXCEPTION, por isso nada
--      fica gravado — nem as reservas de teste, nem os avisos in-app, nem os pedidos do pg_net do
--      gatilho do INSERT).
--      Esperado depois da correção (uma linha só):
--        ERROR P0001 PROVA (nada fica gravado)
--          paga: rpc={"status": "pending_payment", "success": true, "waiting_payment_confirmation": true} estado=pending_payment
--        | livre: rpc={"status": "pending", "success": true} estado=pending
--        | sem cliente: not_your_reservation | update direto: travado 42501 | a 0: travado 42501
--        | webhook: {"ok": true, "reservation_id": "<id>"} estado=pending avisos_in_app_da_paga=1
--      (avisos_in_app_da_paga = 1 se o email do restaurante escolhido for o de uma conta, como nos
--       8 restaurantes com user_ lidos a 15/11; 0 = restaurante sem conta com esse email.)
--      Antes da correção: ERROR 42703 column "updated_at" of relation "reservations" does not exist.
-- do $prova$
-- declare
--   v_cli uuid; v_rest text; v_paga uuid; v_livre uuid; v_orfa uuid;
--   r_paga jsonb; r_livre jsonb; r_web jsonb;
--   e_paga text; e_livre text; e_web text;
--   v_orfa_erro text; v_update text; v_zerar text; v_avisos int;
-- begin
--   select u.id into v_cli from auth.users u
--    where lower(coalesce(u.email, '')) <> 'guest@bora.com'
--      and coalesce(u.raw_app_meta_data->>'role', '') <> 'admin'
--      and coalesce(u.email, '') not in ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
--    limit 1;
--   select r.id into v_rest from public.restaurants r
--    where coalesce(r.coming_soon, false) = false and r.user_ is not null
--    limit 1;
--   -- reserva sem cliente (como uma criada pelo admin), feita pelo dono da base
--   insert into public.reservations (restaurant_id, client_user_id, reserved_for, status, prepayment_cents, client_name)
--   values (v_rest, null, now() + interval '1 day', 'pending_payment', 0, 'prova rollback sem cliente')
--   returning id into v_orfa;
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', v_cli::text, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   insert into public.reservations
--     (restaurant_id, client_user_id, reserved_for, status, prepayment_cents, prepayment_pi, client_name)
--   values (v_rest, v_cli, now() + interval '1 day', 'pending_payment', 300, 'pi_prova_rollback', 'prova rollback paga')
--   returning id into v_paga;
--   insert into public.reservations (restaurant_id, client_user_id, reserved_for, status, prepayment_cents, client_name)
--   values (v_rest, v_cli, now() + interval '1 day', 'pending_payment', 0, 'prova rollback livre')
--   returning id into v_livre;
--   r_paga  := public.client_confirm_reservation_payment(v_paga);   -- corre como postgres
--   r_livre := public.client_confirm_reservation_payment(v_livre);
--   begin
--     perform public.client_confirm_reservation_payment(v_orfa);
--     v_orfa_erro := 'PASSOU (mau: devia recusar)';
--   exception when others then v_orfa_erro := sqlerrm;
--   end;
--   begin
--     update public.reservations set status = 'pending' where id = v_paga;            -- cliente direto
--     v_update := 'PASSOU (mau: o gatilho devia travar)';
--   exception when others then v_update := 'travado ' || sqlstate;
--   end;
--   begin
--     update public.reservations set prepayment_cents = 0 where id = v_paga;          -- fingir que é grátis
--     v_zerar := 'PASSOU (mau: o gatilho devia travar)';
--   exception when others then v_zerar := 'travado ' || sqlstate;
--   end;
--   reset role;
--   select status into e_paga from public.reservations where id = v_paga;
--   select status into e_livre from public.reservations where id = v_livre;
--   r_web := public.confirm_reservation_payment_webhook(v_paga, 'pi_prova_rollback');  -- como o webhook
--   select status into e_web from public.reservations where id = v_paga;
--   select count(*) into v_avisos from public.in_app_notifications
--    where related_id = v_paga::text and kind = 'reservation' and title = 'Nova reserva pendente';
--   raise exception 'PROVA (nada fica gravado) paga: rpc=% estado=% | livre: rpc=% estado=% | sem cliente: % | update direto: % | a 0: % | webhook: % estado=% avisos_in_app_da_paga=%',
--     r_paga, e_paga, r_livre, e_livre, v_orfa_erro, v_update, v_zerar, r_web, e_web, v_avisos;
-- end
-- $prova$;

-- =====================================================================================================
-- ROLLBACK (comentado; só por ordem explícita) — volta às versões de hoje.
-- Conferir depois: md5(pg_get_functiondef) = e52f212e03458760171ee2d742c135c0 (cliente, a que falha
-- sempre com 42703) e fcde7d09713f743e0bbcb96ed6bfd576 (webhook); md5(prosrc) =
-- 9b8677ae3a26dea148cc6ba67a8a366d e b0d043ff95b464085b8344d3ceb7f7a5. Os corpos abaixo, sem o
-- "-- " do início das linhas, dão exatamente esses md5(prosrc) (conferido a 15/11).
-- =====================================================================================================
-- create or replace function public.client_confirm_reservation_payment(p_reservation_id uuid)
--  returns jsonb
--  language plpgsql
--  security definer
--  set search_path to 'public'
-- as $function$
-- DECLARE v_rsv record; v_uid uuid := auth.uid();
-- BEGIN
--   IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
--   SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
--   IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
--   IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
--   IF v_rsv.status NOT IN ('pending_payment', 'pending') THEN
--     RAISE EXCEPTION 'invalid_status: %', v_rsv.status;
--   END IF;
--
--   UPDATE reservations SET status = 'pending', updated_at = NOW()
--   WHERE id = p_reservation_id AND status = 'pending_payment';
--
--   -- Notify partner via in_app (also FCM via Edge Fn — fire-and-forget Flutter)
--   -- Find partner user_id from restaurants table
--   PERFORM _push_in_app_notification(
--     (SELECT u.id FROM auth.users u
--      JOIN restaurants r ON r.email = u.email
--      WHERE r.id = v_rsv.restaurant_id LIMIT 1),
--     'reservation',
--     'Nova reserva pendente',
--     'Reserva para ' || v_rsv.people || ' pessoas em ' ||
--        to_char(v_rsv.reserved_for, 'DD/MM HH24:MI'),
--     p_reservation_id::text
--   );
--   RETURN jsonb_build_object('success', true, 'status', 'pending');
-- END;
-- $function$;
--
-- create or replace function public.confirm_reservation_payment_webhook(p_reservation_id uuid, p_payment_intent_id text)
--  returns jsonb
--  language plpgsql
--  security definer
--  set search_path to 'public'
-- as $function$
-- DECLARE
--   v_reservation record;
-- BEGIN
--   SELECT id, status, prepayment_pi INTO v_reservation
--   FROM public.reservations
--   WHERE id = p_reservation_id
--   FOR UPDATE;
--
--   IF v_reservation IS NULL THEN
--     RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
--   END IF;
--
--   -- Idempotência: já confirmada (race com client_confirm_reservation_payment)
--   IF v_reservation.status <> 'pending_payment' THEN
--     RETURN jsonb_build_object('ok', true, 'already_confirmed', true,
--                               'status', v_reservation.status);
--   END IF;
--
--   -- Validar PI (defesa contra spoofing de metadata)
--   IF v_reservation.prepayment_pi IS DISTINCT FROM p_payment_intent_id THEN
--     RETURN jsonb_build_object('ok', false, 'error', 'pi_mismatch');
--   END IF;
--
--   UPDATE public.reservations
--   SET status = 'pending'
--   WHERE id = p_reservation_id;
--
--   RETURN jsonb_build_object('ok', true, 'reservation_id', p_reservation_id);
-- END;
-- $function$;
