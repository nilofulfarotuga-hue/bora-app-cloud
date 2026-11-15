-- PROPOSTA — client_confirm_reservation_payment deixa de usar a coluna updated_at, que não existe
-- (missão fechar-tudo-15-11, 15/11/2026, Claude Code; ordem da Claude.ai às 16:15, dentro do
-- "Autorizo tudo" do Danilo das 15:15). NADA DISTO FOI APLICADO: aplica a Claude.ai com
-- execute_sql (ou apply_migration), e guarda depois a migração em supabase/migrations/.
--
-- O QUE FAZ
--   create or replace de public.client_confirm_reservation_payment(uuid), igual à que está no ar,
--   SÓ sem `, updated_at = NOW()` no UPDATE. Mesma assinatura (p_reservation_id uuid), mesmo
--   retorno (jsonb), SECURITY DEFINER, search_path=public, dono postgres (o create or replace
--   mantém o dono e o ACL), EXECUTE só para postgres, service_role e authenticated (o revoke/grant
--   abaixo é idempotente e deixa o ACL exatamente como hoje).
--
-- PORQUÊ
--   * public.reservations não tem a coluna updated_at (information_schema.columns lido a 15/11:
--     27 colunas, 0 com esse nome). O plpgsql só resolve o UPDATE quando ele corre, por isso a
--     função foi criada sem erro e falha SEMPRE com 42703 (column "updated_at" of relation
--     "reservations" does not exist). Vem assim desde a migração
--     20260503020000_reservation_rpcs_sync.sql (5/7): md5(pg_get_functiondef) no ar a 15/11 =
--     e52f212e03458760171ee2d742c135c0, o mesmo que essa migração regista; md5 do corpo (prosrc)
--     = 9b8677ae3a26dea148cc6ba67a8a366d, igual ao do ROLLBACK no fim deste ficheiro.
--   * Efeito hoje no ecrã que a app usa (ReservationCheckoutScreen → ReservationStore.
--     confirmReservationPayment, cartão e MB WAY): o erro é engolido e o cliente vê "Reserva
--     pendente!", mas (a) o parceiro NUNCA recebe o aviso in-app "Nova reserva pendente" desta
--     função e (b) a reserva só sai de 'pending_payment' quando o webhook chega — se ele falhar,
--     fica parada com os 3 € cobrados até o payments-reconciler dar o alarme. Se o aviso FCM do
--     webhook também não sair (ACHADO 3), o parceiro não recebe aviso de reserva paga nenhuma.
--     O ecrã antigo lib/screens/reservation_flow_screen.dart (linhas 215 e 325) chama a RPC
--     diretamente e, na web, apagaria a reserva paga (cancel_orphan_reservation no catch), mas já
--     ninguém o abre (grep "ReservationFlowScreen(" em lib/ = 0). Com a correção deixa de lançar.
--   * Não há coluna equivalente (decided_at é a decisão do parceiro, confirmation_sent_at é a
--     mensagem de confirmação): tira-se o carimbo em vez de o trocar.
--   * Hoje há 0 linhas em reservations (SELECT por estado, 15/11): ninguém ficou por corrigir.
--
-- O GATILHO NOVO NÃO TRAVA ESTA FUNÇÃO (pg_trigger + pg_proc lidos a 15/11)
--   trg_00_reservas_campos_protegidos (BEFORE UPDATE em reservations) chama
--   public._reservas_cliente_campos_protegidos(), que NÃO é SECURITY DEFINER e só recusa quando
--   current_user in ('authenticated','anon') e não is_admin(). Esta função É SECURITY DEFINER com
--   dono postgres: durante o UPDATE dela o current_user é 'postgres', a condição é falsa e a
--   mudança de status passa. O cliente direto (PostgREST, current_user = authenticated) continua
--   travado. A prova P4 mostra as duas coisas. Os outros gatilhos de UPDATE (no_show, late_cancel,
--   seated, finished, convidado_so_ve) não mudam nada para 'pending_payment' → 'pending'.
--
-- O QUE FICA IGUAL, DE PROPÓSITO (ordem: "mesmo comportamento"):
--   * Passa 'pending_payment' → 'pending' sem ir à Stripe, como antes (o webhook
--     confirm_reservation_payment_webhook faz o mesmo quando o pagamento entra; quem chegar
--     primeiro ganha e o outro responde já confirmado). Não abre nada de novo: o cliente já
--     consegue INSERIR uma reserva diretamente em 'pending' (ACHADO 1).
--   * Avisa o parceiro (in-app) em cada chamada, procurando-o por restaurants.email = auth.users.email
--     (lido a 15/11: nos 8 restaurantes com user_, o email aponta para o mesmo utilizador).
--   * A hora do aviso sai em UTC (to_char sem 'Europe/Lisbon'): certa no inverno, 1 h atrás no verão.
--
-- ACHADOS (não corrigidos aqui — para a Claude.ai decidir)
--   1. INSERT direto: a RLS reservations_client_owner (FOR ALL, with check client_user_id =
--      auth.uid()) e o gatilho novo (só BEFORE UPDATE) deixam o cliente criar uma reserva já em
--      'pending' (o default da coluna) com prepayment_cents/prepayment_pi à escolha, sem pagar.
--      Fecho sugerido: BEFORE INSERT que, para authenticated/anon não-admin, obrigue
--      status='pending_payment', prepayment_pi null e stripe_account por defeito (as Edge
--      create-*-reservation-payment-intent inserem com a chave do servidor e não são afetadas).
--   2. cancel_orphan_reservation (SECURITY DEFINER, EXECUTE para authenticated) não confere quem
--      chama: quem souber o id da reserva e o do PI apaga a reserva 'pending_payment' de outra pessoa.
--   3. Zona vermelha, só lido NO REPO (a versão no ar não foi lida): _shared/stripe_webhook_core.ts
--      (payment_intent.succeeded de reserva) faz select('restaurant_id, guests') e a coluna guests
--      não existe (é people) → o aviso FCM "Nova reserva confirmada!" ao parceiro não sai.

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
  IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('pending_payment', 'pending') THEN
    RAISE EXCEPTION 'invalid_status: %', v_rsv.status;
  END IF;

  -- fechar-tudo-15-11: sem o carimbo de atualização (essa coluna não existe em reservations; 42703).
  UPDATE reservations SET status = 'pending'
  WHERE id = p_reservation_id AND status = 'pending_payment';

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
END;
$function$;

-- Os mesmos acessos de hoje ({postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}).
revoke all on function public.client_confirm_reservation_payment(uuid) from public, anon;
grant execute on function public.client_confirm_reservation_payment(uuid) to authenticated, service_role;

commit;

-- =====================================================================================================
-- PROVAS (só leitura; correr depois do commit)
-- =====================================================================================================
-- P1 — a coluna continua a não existir (esperado: 0)
-- select count(*) as tem_updated_at
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reservations' and column_name = 'updated_at';
--
-- P2 — a função já não fala em updated_at e manteve segurança, dono e acessos
--      (esperado: false | true | {search_path=public} | postgres |
--       {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres})
-- select pg_get_functiondef(p.oid) ~ 'updated_at' as ainda_usa_updated_at,
--        p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as dono, p.proacl::text as acessos
--   from pg_proc p
--  where p.oid = 'public.client_confirm_reservation_payment(uuid)'::regprocedure;
--
-- P3 — o gatilho continua lá, ligado, e a função dele não é SECURITY DEFINER
--      (esperado: trg_00_reservas_campos_protegidos | O | false)
-- select t.tgname, t.tgenabled, p.prosecdef
--   from pg_trigger t join pg_proc p on p.oid = t.tgfoid
--  where t.tgrelid = 'public.reservations'::regclass and t.tgname = 'trg_00_reservas_campos_protegidos';
--
-- P4 — OPCIONAL, correr SOZINHO (escreve e desfaz: o bloco acaba em RAISE EXCEPTION, por isso nada
--      fica gravado — nem a reserva de teste, nem o aviso in-app, nem o pedido do pg_net).
--      Antes da correção: ERROR 42703 column "updated_at" of relation "reservations" does not exist.
--      Depois: ERROR P0001 PROVA (nada fica gravado) rpc={"status": "pending", "success": true}
--              | estado=pending | update_direto=travado 42501: reserva_campo_protegido: ...
-- do $prova$
-- declare
--   v_cli uuid; v_rest text; v_rsv uuid; v_res jsonb; v_estado text; v_update text;
-- begin
--   select u.id into v_cli from auth.users u
--    where lower(coalesce(u.email, '')) <> 'guest@bora.com'
--      and coalesce(u.raw_app_meta_data->>'role', '') <> 'admin'
--      and coalesce(u.email, '') not in ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
--    limit 1;
--   select r.id into v_rest from public.restaurants r
--    where coalesce(r.coming_soon, false) = false and r.user_ is not null
--    limit 1;
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', v_cli::text, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   insert into public.reservations
--     (restaurant_id, client_user_id, reserved_for, status, prepayment_cents, client_name)
--   values (v_rest, v_cli, now() + interval '1 day', 'pending_payment', 300, 'prova rollback')
--   returning id into v_rsv;
--   v_res := public.client_confirm_reservation_payment(v_rsv);        -- corre como postgres
--   select status into v_estado from public.reservations where id = v_rsv;
--   begin
--     update public.reservations set status = 'approved' where id = v_rsv;  -- cliente direto
--     v_update := 'PASSOU (mau: o gatilho devia travar)';
--   exception when others then
--     v_update := 'travado ' || sqlstate || ': ' || sqlerrm;
--   end;
--   raise exception 'PROVA (nada fica gravado) rpc=% | estado=% | update_direto=%',
--     v_res, v_estado, v_update;
-- end
-- $prova$;

-- =====================================================================================================
-- ROLLBACK (comentado; só por ordem explícita) — volta à versão de hoje, a que falha sempre com 42703
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
