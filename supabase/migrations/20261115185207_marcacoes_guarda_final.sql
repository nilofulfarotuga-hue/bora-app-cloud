-- Texto aplicado em produção a 15/11/2026 (versão 20261115185207, pela Claude.ai, por carregador com sha256
-- a033bdc1a6e3576d4893736b1b158855f6cc0a26bf795e45bd4bcdd12adbace6); igual a docs/propostas/fechar-tudo-15-11/appointments_guarda_FINAL.sql.

-- PROPOSTA — marcações (public.appointments): um cliente ou parceiro com sessão (ou anon) deixa de
-- poder mexer à mão no estado, no pagamento, no valor e na hora da marcação. Igual ao gatilho
-- trg_00_reservas_campos_protegidos das reservas (15/11), mas também no INSERT.
-- Missão fechar-tudo-15-11, 15/11/2026, Claude Code. Ordem do Juiz da Claude.ai (18:42), dentro do
-- "Autorizo tudo" do Danilo das 15:15. NADA DISTO FOI APLICADO: aplica a Claude.ai com
-- apply_migration e guarda depois a migração em supabase/migrations/.
--
-- PORQUÊ (lido no ar a 15/11, só SELECT)
--   * RLS de appointments: ap_insert / ap_update deixam o CLIENTE (client_user_id = auth.uid()) e
--     o PARCEIRO dono do service_provider escrever QUALQUER coluna da sua marcação; anon e
--     authenticated têm GRANT INSERT/UPDATE/DELETE na tabela. Hoje um cliente pode, pela API, pôr
--     status='confirmed' sem pagar, trocar deposit_pi por um pagamento de outra coisa, baixar
--     deposit_cents antes de pagar (create-appointment-payment-intent cobra deposit_cents) ou mudar
--     scheduled_at para uma hora ocupada sem passar pela verificação de colisão.
--   * Gatilhos que já existem: trg_appointments_updated (BEFORE UPDATE, updated_at),
--     trg_coming_soon_guard_appointments (BEFORE INSERT), trg_convidado_so_ve (BEFORE INSERT/UPDATE),
--     trg_notify_new_appointment_admin (AFTER INSERT). Nenhum protege colunas.
--
-- QUEM ESCREVE HOJE NESTAS COLUNAS (e continua a poder, porque NÃO corre como authenticated/anon)
--   * As 27 funções SQL que fazem INSERT/UPDATE em appointments são TODAS SECURITY DEFINER com dono
--     postgres (current_user = postgres dentro delas — erro aprendido de 14/11): client_book_appointment,
--     client_cancel_appointment, client_reschedule_appointment, client_confirm_appointment_payment,
--     confirm_appointment_payment_webhook, partner_add_walk_in, partner_block_slot,
--     partner_cancel_appointment, partner_complete_appointment, partner_mark_no_show,
--     admin_appointment_confirm_done, admin_appointment_mark_no_show, admin_appointment_revert_no_show,
--     admin_cancel_appointment_on_behalf_of, admin_assistente_limpar_testes, assistente_marcar(_v2),
--     assistente_desmarcar(_v2), assistente_remarcar(_v2), assistente_aviso_enviado,
--     _appt_ask_partner_confirmation e os 4 relógios _appointment_cron_*. Prova 2, abaixo.
--   * Edge Functions com a chave do servidor (service_role): payments-reconciler, robot-b,
--     delete-account (este só mexe em client_name/client_phone, que ficam livres).
--   * create-appointment-payment-intent v5 (conserto P0 de 15/11, neste ramo): grava deposit_pi e
--     stripe_account com a chave do servidor. A v4, NO AR, grava como `authenticated`.
--   * App Flutter (lib/): nenhum INSERT/UPDATE direto em appointments (grep a 15/11); tudo por RPC.
--   * Admin com sessão (is_admin()): passa, como nas reservas.
--
-- PRÉ-REQUISITOS — SEM ISTO A GUARDA PARTE PAGAMENTOS
--   1. Publicar create-appointment-payment-intent v5 (este ramo) ANTES da guarda.
--   2. create-mbway-appointment-payment-intent (no ar) tem o MESMO defeito: cliente com a chave
--      secreta + Authorization do cliente → `update({ deposit_pi, stripe_account })` corre como
--      authenticated (index.ts ~:156-163, e só escreve o erro no log). Com a guarda, as marcações
--      pagas por MB WAY ficavam sem o deposit_pi. Tem de levar o mesmo conserto (cliente admin só
--      para escrever + cancelar o PI se não gravar) e ser publicada ANTES. Ficou fora desta ordem
--      (só tinha autorização para as 3 Edges de reservas/marcação por cartão).
--   3. confirm-mbway-appointment-payment só lê e chama client_confirm_appointment_payment
--      (SECURITY DEFINER): não precisa de mudar.
--
-- O QUE FAZ
--   * INSERT por authenticated/anon que não seja admin → recusado (42501). Toda a marcação legítima
--     nasce por RPC SECURITY DEFINER (cliente, parceiro, walk-in, bloqueio, assistente).
--   * UPDATE por authenticated/anon que não seja admin → recusado se mudar uma coluna protegida.
--     Ficam livres: client_name, client_phone, client_notes, partner_notes, updated_at.
--   * Nome trg_00_...: os gatilhos BEFORE correm por ordem alfabética, este corre primeiro.
--   * A função NÃO é SECURITY DEFINER (tem de ver o current_user de quem escreve).

begin;

create or replace function public._marcacoes_cliente_campos_protegidos()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if current_user in ('authenticated', 'anon') and not coalesce(public.is_admin(), false) then
    if tg_op = 'INSERT' then
      raise exception 'marcacao_campo_protegido: as marcacoes so se criam pelas funcoes do servidor (ex.: client_book_appointment)'
        using errcode = '42501';
    end if;
    if new.status                      is distinct from old.status
    or new.scheduled_at                is distinct from old.scheduled_at
    or new.deposit_cents               is distinct from old.deposit_cents
    or new.deposit_pi                  is distinct from old.deposit_pi
    or new.deposit_status              is distinct from old.deposit_status
    or new.service_price_cents         is distinct from old.service_price_cents
    or new.full_payment_method         is distinct from old.full_payment_method
    or new.full_payment_pi             is distinct from old.full_payment_pi
    or new.full_payment_status         is distinct from old.full_payment_status
    or new.stripe_account              is distinct from old.stripe_account
    or new.provider_id                 is distinct from old.provider_id
    or new.staff_id                    is distinct from old.staff_id
    or new.service_id                  is distinct from old.service_id
    or new.client_user_id              is distinct from old.client_user_id
    or new.duration_minutes            is distinct from old.duration_minutes
    or new.confirmed_at                is distinct from old.confirmed_at
    or new.completed_at                is distinct from old.completed_at
    or new.cancelled_at                is distinct from old.cancelled_at
    or new.cancel_reason               is distinct from old.cancel_reason
    or new.cancelled_by                is distinct from old.cancelled_by
    or new.no_show_at                  is distinct from old.no_show_at
    or new.no_show_decided_by          is distinct from old.no_show_decided_by
    or new.no_show_decided_at          is distinct from old.no_show_decided_at
    or new.reschedule_count            is distinct from old.reschedule_count
    or new.original_scheduled_at       is distinct from old.original_scheduled_at
    or new.last_rescheduled_at         is distinct from old.last_rescheduled_at
    or new.awaiting_since              is distinct from old.awaiting_since
    or new.confirm_asked_count         is distinct from old.confirm_asked_count
    or new.confirm_last_asked_at       is distinct from old.confirm_last_asked_at
    or new.reminder_24h_sent_at        is distinct from old.reminder_24h_sent_at
    or new.reminder_2h_sent_at         is distinct from old.reminder_2h_sent_at
    or new.is_walk_in                  is distinct from old.is_walk_in
    or new.origem                      is distinct from old.origem
    or new.is_test                     is distinct from old.is_test
    or new.assistant_tenant_id         is distinct from old.assistant_tenant_id
    or new.assistant_reminder_sent_at  is distinct from old.assistant_reminder_sent_at
    or new.assistant_review_sent_at    is distinct from old.assistant_review_sent_at
    or new.created_at                  is distinct from old.created_at
    or new.id                          is distinct from old.id
    then
      raise exception 'marcacao_campo_protegido: este campo so muda pelas funcoes do servidor (ex.: client_cancel_appointment)'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$function$;

revoke all on function public._marcacoes_cliente_campos_protegidos() from public, anon, authenticated;

drop trigger if exists trg_00_marcacoes_campos_protegidos on public.appointments;
create trigger trg_00_marcacoes_campos_protegidos
  before insert or update on public.appointments
  for each row execute function public._marcacoes_cliente_campos_protegidos();

revoke delete, truncate on public.appointments from anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- PROVAS (só leitura; correr depois do commit)
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. O gatilho existe, está ligado e é BEFORE INSERT OR UPDATE (tgtype 23 = ROW+BEFORE+INSERT+UPDATE):
-- select t.tgname, t.tgenabled, t.tgtype, p.prosecdef
--   from pg_trigger t join pg_proc p on p.oid = t.tgfoid
--  where t.tgrelid = 'public.appointments'::regclass and t.tgname = 'trg_00_marcacoes_campos_protegidos';
--   (esperado: trg_00_marcacoes_campos_protegidos | O | 23 | false)
--
-- 2. Nenhuma função que escreve em appointments corre como o chamador (esperado: 0 linhas):
-- select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.prokind = 'f' and not p.prosecdef
--    and pg_get_functiondef(p.oid) ~* '(insert\s+into|update)\s+(public\.)?appointments';
--
-- 3. Prova em rollback (nada fica gravado: o bloco acaba SEMPRE com erro). Como cliente dono de uma
--    marcação: mudar deposit_pi, status, deposit_cents ou scheduled_at → 42501; criar marcação à
--    mão → 42501; mudar client_notes → passa. Como postgres (o caminho das RPC) → passa.
-- do $$
-- declare
--   v_id uuid; v_cli uuid; v_prov text;
--   r_pi text := 'passou'; r_st text := 'passou'; r_val text := 'passou'; r_hora text := 'passou';
--   r_ins text := 'passou'; r_notas text := 'passou'; r_srv text := 'passou';
-- begin
--   select id, client_user_id, provider_id into v_id, v_cli, v_prov
--     from public.appointments where client_user_id is not null order by created_at desc limit 1;
--   update public.appointments set deposit_pi = deposit_pi || '' where id = v_id;  -- postgres: passa
--   begin update public.appointments set deposit_cents = coalesce(deposit_cents, 0) + 1 where id = v_id;
--   exception when others then r_srv := sqlstate || ' ' || sqlerrm; end;
--   perform set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
--   execute 'set local role authenticated';
--   begin update public.appointments set deposit_pi = 'pi_prova' where id = v_id;
--   exception when others then r_pi := sqlstate || ' ' || sqlerrm; end;
--   begin update public.appointments set status = 'confirmed' where id = v_id;
--   exception when others then r_st := sqlstate || ' ' || sqlerrm; end;
--   begin update public.appointments set deposit_cents = 50 where id = v_id;
--   exception when others then r_val := sqlstate || ' ' || sqlerrm; end;
--   begin update public.appointments set scheduled_at = scheduled_at + interval '1 hour' where id = v_id;
--   exception when others then r_hora := sqlstate || ' ' || sqlerrm; end;
--   begin insert into public.appointments (provider_id, client_user_id, scheduled_at, status, deposit_cents)
--         values (v_prov, v_cli, now() + interval '2 days', 'confirmed', 50);
--   exception when others then r_ins := sqlstate || ' ' || sqlerrm; end;
--   begin update public.appointments set client_notes = coalesce(client_notes, '') || ' prova' where id = v_id;
--   exception when others then r_notas := sqlstate || ' ' || sqlerrm; end;
--   execute 'reset role';
--   raise exception 'PROVA (nada fica gravado) servidor: % | deposit_pi: % | status: % | deposit_cents: % | scheduled_at: % | insert: % | client_notes: %',
--     r_srv, r_pi, r_st, r_val, r_hora, r_ins, r_notas;
-- end $$;
--   (esperado: servidor: passou | deposit_pi: 42501 marcacao_campo_protegido... | status: 42501 ... |
--    deposit_cents: 42501 ... | scheduled_at: 42501 ... | insert: 42501 marcacao_campo_protegido: as
--    marcacoes so se criam ... | client_notes: passou)
--
-- 4. Depois de aplicar, vigiar 24 h: erros 42501 'marcacao_campo_protegido' nos logs da API
--    (query_logs service 'postgres') = alguém escrevia à mão; ver quem antes de afrouxar.

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (comentado; só por ordem explícita) — volta ao estado de hoje (sem guarda).
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- begin;
-- drop trigger if exists trg_00_marcacoes_campos_protegidos on public.appointments;
-- drop function if exists public._marcacoes_cliente_campos_protegidos();
-- commit;
