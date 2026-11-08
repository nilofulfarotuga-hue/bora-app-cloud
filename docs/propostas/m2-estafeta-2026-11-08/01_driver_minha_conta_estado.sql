-- PROPOSTA · missão m2-estafeta-conta-fila-2026-11-08 · 1/3
-- Aplicar em produção: Claude.ai (a trava do modo automático não deixa o Claude Code).
-- Depois de aplicar: copiar para supabase/migrations/20261108200000_m2_driver_minha_conta_estado.sql.
--
-- driver_minha_conta_estado(p_user_id): o semáforo "A minha conta" do estafeta e do motorista.
-- FONTE ÚNICA: a app (ecrã A minha conta, barra "Falta: …" do mapa, folha do botão Online) e o
-- painel admin (/admin/estafetas) chamam ESTA função. As regras são as mesmas de
-- lib/services/minha_conta.dart (montarMinhaConta), fixadas em test/minha_conta_test.dart.
--
-- Só LÊ. Não mexe em dinheiro: a dívida é lida de v_acerto_semanal_unificado (semanas fechadas em
-- que a pessoa deve e ainda não pagou) e de drivers.debt_cents; nada é escrito.
-- Segurança: o próprio (auth.uid()) ou o admin (is_admin()). Fechada a anon.

create or replace function public._minha_conta_item(
  p_chave text, p_rotulo text, p_curto text, p_estado text,
  p_detalhe text default null, p_bloqueia boolean default false,
  p_opcional boolean default false, p_kind text default null)
returns jsonb
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'chave', p_chave, 'rotulo', p_rotulo, 'rotulo_curto', p_curto, 'estado', p_estado,
    'detalhe', p_detalhe, 'bloqueia', coalesce(p_bloqueia, false),
    'opcional', coalesce(p_opcional, false), 'kind_foto', p_kind);
$$;

create or replace function public.driver_minha_conta_estado(p_user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  d record;
  v_itens jsonb := '[]'::jsonb;
  v_rob jsonb := '{}'::jsonb;          -- campo -> {decisao, motivo}
  x jsonb;
  vv record;
  v_tvde boolean;
  v_bici boolean;
  -- fiscal (igual a driver_fiscal_status_get, mas para v_uid)
  v_nif text; v_ativ_aberta boolean; v_fiscal_ok boolean;
  v_desde date; v_prazo date; v_extra date;
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
  v_bloq_fiscal boolean;
  -- comprovativo de atividade
  v_at_status text; v_at_doc boolean;
  -- recibo verde do mês passado
  v_ant date := (date_trunc('month', (now() at time zone 'Europe/Lisbon')) - interval '1 month')::date;
  v_mes_nome text;
  v_rec jsonb;
  -- dívida
  v_divida bigint := 0;
  v_stripe text;
  -- auxiliares
  v_tem boolean; v_est text; v_det text; v_dec jsonb;
begin
  if auth.uid() is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if v_uid <> auth.uid() and not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;

  select * into d from public.drivers
   where user_id = v_uid and deleted_at is null
   order by created_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA');
  end if;

  v_tvde := coalesce(d.vehicle_type, '') in ('carro_passageiros', 'carPassengers');
  v_bici := coalesce(d.vehicle_type, '') = 'bicycle';

  -- Decisões do robô dos documentos (só quando está a agir), pela mesma regra
  -- de provider_documentos_estado: 'errado' sem ação conta como 'duvida'.
  if public._robo_documentos_age() then
    for x in select * from jsonb_array_elements(public._robo_documentos_alvos(v_uid) -> 'alvos') loop
      select dv.decisao, dv.motivo_pt, dv.acao into vv from public.documentos_verificacoes dv
       where dv.user_id = v_uid and dv.campo = x ->> 'campo' and dv.path = x ->> 'path' and dv.revertido_em is null
       order by dv.id desc limit 1;
      if found then
        v_rob := v_rob || jsonb_build_object(x ->> 'campo', jsonb_build_object(
          'decisao', case when vv.decisao = 'errado' and vv.acao = 'nenhuma' then 'duvida' else vv.decisao end,
          'motivo', case when vv.decisao = 'errado' and vv.acao <> 'nenhuma' then vv.motivo_pt end));
      end if;
    end loop;
  end if;

  -- 1. Aprovação (só enquanto não está aprovada).
  if coalesce(d.approval_status, '') <> 'approved' then
    v_itens := v_itens || public._minha_conta_item('aprovacao', 'Aprovação da conta', 'aprovação',
      case when d.approval_status = 'rejected' then 'falta' else 'analise' end,
      case when d.approval_status = 'rejected'
           then 'A candidatura não foi aprovada. Fala connosco no Suporte.'
           else 'A nossa equipa está a ver a tua candidatura.' end,
      true);
  end if;

  -- 2. Selfie, documento (foto) e número do documento.
  v_tem := nullif(btrim(coalesce(d.photo_url, '')), '') is not null
        or nullif(btrim(coalesce(d.registration_selfie_url, '')), '') is not null;
  v_dec := v_rob -> 'drivers.registration_selfie_url';
  v_est := case when not v_tem then 'falta'
                when v_dec ->> 'decisao' = 'errado' then 'falta'
                when v_dec ->> 'decisao' = 'duvida' then 'analise' else 'ok' end;
  v_det := case when v_tem and v_dec ->> 'decisao' = 'errado'
                  then coalesce(v_dec ->> 'motivo', 'Não ficou legível ou não é o documento certo. Envia uma foto nova.')
                when v_tem and v_dec ->> 'decisao' = 'duvida' then 'Recebido — estamos a confirmar.' end;
  v_itens := v_itens || public._minha_conta_item('selfie', 'Foto pessoal (selfie)', 'selfie', v_est, v_det,
                                                 false, false, 'selfie');

  v_tem := nullif(btrim(coalesce(d.document_photo_url, '')), '') is not null;
  v_dec := v_rob -> 'drivers.document_photo_url';
  v_est := case when not v_tem then 'falta'
                when v_dec ->> 'decisao' = 'errado' then 'falta'
                when v_dec ->> 'decisao' = 'duvida' then 'analise' else 'ok' end;
  v_det := case when v_tem and v_dec ->> 'decisao' = 'errado'
                  then coalesce(v_dec ->> 'motivo', 'Não ficou legível ou não é o documento certo. Envia uma foto nova.')
                when v_tem and v_dec ->> 'decisao' = 'duvida' then 'Recebido — estamos a confirmar.' end;
  v_itens := v_itens || public._minha_conta_item('document', 'Foto do documento de identificação', 'documento',
                                                 v_est, v_det, false, false, 'document');

  v_itens := v_itens || public._minha_conta_item('document_number', 'Número do documento', 'n.º do documento',
    case when nullif(btrim(coalesce(d.document_number, '')), '') is null then 'falta' else 'ok' end);

  -- 3. Veículo (não para bicicleta; no TVDE vive na Conformidade TVDE).
  if not v_bici and not v_tvde then
    v_tem := nullif(btrim(coalesce(d.vehicle_photo_url, '')), '') is not null;
    v_dec := v_rob -> 'drivers.vehicle_photo_url';
    v_est := case when not v_tem then 'falta'
                  when v_dec ->> 'decisao' = 'errado' then 'falta'
                  when v_dec ->> 'decisao' = 'duvida' then 'analise' else 'ok' end;
    v_det := case when v_tem and v_dec ->> 'decisao' = 'errado'
                    then coalesce(v_dec ->> 'motivo', 'Não ficou legível ou não é o documento certo. Envia uma foto nova.')
                  when v_tem and v_dec ->> 'decisao' = 'duvida' then 'Recebido — estamos a confirmar.' end;
    v_itens := v_itens || public._minha_conta_item('vehicle', 'Foto do veículo', 'foto do veículo', v_est, v_det,
                                                   false, false, 'vehicle');
    v_itens := v_itens || public._minha_conta_item('license_plate', 'Matrícula', 'matrícula',
      case when nullif(btrim(coalesce(d.license_plate, '')), '') is null then 'falta' else 'ok' end);
  end if;

  -- 4. Morada, data de nascimento, IBAN.
  v_itens := v_itens || public._minha_conta_item('morada', 'Morada', 'morada',
    case when nullif(btrim(coalesce(d.address, '')), '') is null then 'falta' else 'ok' end);
  v_itens := v_itens || public._minha_conta_item('nascimento', 'Data de nascimento', 'data de nascimento',
    case when d.birth_date is null then 'falta' else 'ok' end);
  v_itens := v_itens || public._minha_conta_item('iban', 'IBAN (para receberes)', 'IBAN',
    case when nullif(btrim(coalesce(d.iban, '')), '') is null then 'falta' else 'ok' end);

  -- 5. NIF + atividade aberta (mesma conta de driver_fiscal_status_get).
  select (value #>> '{}')::date into v_desde from public.platform_settings where key = 'estafeta_fiscal_em_vigor_desde';
  select (value #>> '{}')::date into v_prazo from public.platform_settings where key = 'estafeta_fiscal_prazo';
  select (value ->> v_uid::text)::date into v_extra from public.platform_settings where key = 'estafeta_fiscal_prazo_extra';
  v_prazo := coalesce(v_extra, v_prazo, date '2026-10-15');
  select f.nif, f.atividade_aberta into v_nif, v_ativ_aberta from public.driver_fiscal_status f where f.user_id = v_uid;
  v_nif := coalesce(v_nif, d.nif);
  v_fiscal_ok := coalesce(v_ativ_aberta, false) and public._nif_valido(v_nif);
  if coalesce(public.is_demo_email((select email from auth.users where id = v_uid)), false) then
    v_fiscal_ok := true;
  end if;
  v_bloq_fiscal := (not v_fiscal_ok) and v_hoje >= v_prazo;
  v_itens := v_itens || public._minha_conta_item('fiscal', 'NIF e atividade aberta nas Finanças', 'NIF',
    case when v_fiscal_ok then 'ok' else 'falta' end,
    case when v_fiscal_ok then null
         when v_bloq_fiscal then 'Sem isto não podes ficar online.'
         else 'Tens até ' || to_char(v_prazo, 'YYYY-MM-DD') || ' para confirmar.' end,
    (not v_fiscal_ok) and v_bloq_fiscal);

  -- 6. Comprovativo de atividade (Finanças) — quem é prestador.
  select pa.atividade_status, pa.documento_path is not null into v_at_status, v_at_doc
    from public.provider_atividade pa where pa.user_id = v_uid;
  v_at_status := coalesce(v_at_status, 'por_enviar');
  v_itens := v_itens || public._minha_conta_item('atividade', 'Comprovativo de atividade (Finanças)',
    'comprovativo de atividade',
    case when v_at_status = 'aprovada' then 'ok'
         when v_at_status = 'em_analise' and coalesce(v_at_doc, false) then 'analise'
         else 'falta' end,
    case when v_at_status = 'em_analise' and coalesce(v_at_doc, false) then 'Recebido — estamos a confirmar.'
         when v_at_status = 'recusada' then 'O comprovativo não foi aceite. Envia outro.' end);

  -- 7. Recibo verde do mês passado (a partir do recibo de outubro de 2026).
  if v_ant >= date '2026-10-01' then
    begin
      select el.val into v_rec
        from jsonb_array_elements(coalesce(
               public.driver_monthly_invoice_summary(extract(year from v_ant)::int, extract(month from v_ant)::int)
                 -> 'estafetas', '[]'::jsonb)) as el(val)
       where el.val ->> 'user_id' = v_uid::text
       limit 1;
    exception when others then
      v_rec := null;  -- o semáforo não cai por causa do recibo
    end;
    if v_rec is not null then
      v_mes_nome := (array['janeiro','fevereiro','março','abril','maio','junho','julho',
                           'agosto','setembro','outubro','novembro','dezembro'])[extract(month from v_ant)::int];
      v_itens := v_itens || public._minha_conta_item('recibo', 'Recibo verde de ' || v_mes_nome, 'recibo verde',
        case when coalesce((v_rec ->> 'recibo_passado')::boolean, false) then 'ok' else 'falta' end,
        case when coalesce((v_rec ->> 'recibo_passado')::boolean, false) then null
             else 'Passa o recibo e marca aqui que já passaste.' end);
    end if;
  end if;

  -- 8. Stripe (opcional, nunca bloqueia).
  v_stripe := coalesce(d.stripe_account_status, 'none');
  v_itens := v_itens || public._minha_conta_item('stripe', 'Receber pagamentos por cartão (Stripe)', 'Stripe',
    case v_stripe when 'enabled' then 'ok' when 'pending' then 'analise' else 'falta' end,
    case when v_stripe = 'enabled' then null else 'Opcional.' end,
    false, true);

  -- 9. Dívida à Bora: semanas fechadas por pagar (ou a coluna, se for maior).
  select coalesce(sum(abs(v.total_cents)), 0) into v_divida
    from public.v_acerto_semanal_unificado v
   where v.user_id = v_uid and v.sentido = 'pessoa_deve' and not coalesce(v.tudo_pago, false);
  v_divida := greatest(v_divida, coalesce(d.debt_cents, 0));
  v_itens := v_itens || public._minha_conta_item('divida',
    case when v_divida > 0 then 'Deves à Bora ' || replace(to_char(v_divida / 100.0, 'FM999990.00'), '.', ',') || ' €'
         else 'Sem dívidas à Bora' end,
    'dívida ' || replace(to_char(v_divida / 100.0, 'FM999990.00'), '.', ',') || ' €',
    case when v_divida > 0 then 'falta' else 'ok' end,
    case when v_divida > 0 then 'Paga por MB Way e carrega em "Já paguei".' end,
    v_divida > 0 and coalesce(d.blocked_for_debt, false));

  return jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'approval_status', d.approval_status,
    'vehicle_type', d.vehicle_type,
    'divida_cents', v_divida,
    'itens', v_itens);
end
$$;

revoke all on function public.driver_minha_conta_estado(uuid) from public, anon;
grant execute on function public.driver_minha_conta_estado(uuid) to authenticated;
revoke all on function public._minha_conta_item(text, text, text, text, text, boolean, boolean, text) from public, anon;
grant execute on function public._minha_conta_item(text, text, text, text, text, boolean, boolean, text) to authenticated;

comment on function public.driver_minha_conta_estado(uuid) is
  'm2 08/11/2026: semáforo A minha conta (estafeta/motorista). Fonte única da app e do painel. Só lê.';
