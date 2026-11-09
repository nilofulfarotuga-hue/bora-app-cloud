-- PUBLICAÇÃO 2 da Casa — passo 6: UMA notificação aos clientes (só DEPOIS do teste real do passo 5 passar).
-- O MESMO caminho do painel > Enviar notificação (admin_broadcast_notification): grava o sininho in-app e a
-- fila push_broadcasts; a tarefa agendada execute-broadcast-queue (de 2 em 2 min) chama a Edge Function
-- execute-broadcast, que envia e marca 'sent'/'failed'.
-- Segmento all_clients com kind 'promo' = comunicação comercial → SÓ a quem deu o opt-in de "Promoções e
-- novidades" (users.marketing_opt_in, regra D3 de 23/09). A 09/11/2026 eram 22 clientes (21 com aparelho).
-- O texto bate com o catálogo autorizado (PADRAO 1.19): hora a 20 € (mínimo 1 h), material do cliente.
-- NÃO é idempotente de propósito: correr DUAS vezes manda DUAS notificações. A guarda abaixo recusa se já
-- houver uma difusão com este título.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_titulo constant text := 'Novidade: Casa & Manutenção';
  v_corpo constant text := 'Montar móveis, pendurar quadros e TV, pequenas reparações e jardim, a partir de 20 € à hora. '
                           || 'O profissional leva as ferramentas; o material é teu. Pede na app Bora, no atalho Casa.';
  v_n int;
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  if not public._casa_visivel() then raise exception 'a Casa ainda esta desligada: liga primeiro (passo 3)'; end if;
  if exists (select 1 from public.push_broadcasts where title = v_titulo) then
    raise exception 'ja houve uma difusao "%": nao se manda segunda', v_titulo;
  end if;

  v_n := public.admin_broadcast_notification('all_clients', 'promo', v_titulo, v_corpo);
  raise notice 'sininho para % clientes; push na fila', v_n;
end
$pub$;

-- Prova (lê de volta; a fila passa a 'sent' em <= 2 min — repetir este SELECT):
select id, segment, kind, only_marketing_opt_in, cardinality(target_user_ids) as pessoas, status, sent_count,
       failed_count, status_note, created_at
  from public.push_broadcasts
 where title = 'Novidade: Casa & Manutenção'
 order by created_at desc;
