-- PROPOSTA · missão m2-estafeta-conta-fila-2026-11-08 · 3/3
-- Aplicar em produção: Claude.ai, DEPOIS da 01 (usa driver_minha_conta_estado).
-- Depois: supabase/migrations/20261108200200_m2_fila_de_espera_candidatos.sql.
--
-- Fila de espera dos candidatos (regras do Danilo, livro onboarding-estafetas):
--   documentos_pendentes → em_verificacao → fila_de_espera → aprovado (SÓ o Danilo aprova, no painel).
-- Não se cria coluna nova: a fase DERIVA do que já existe (faltas do robô, decisões do robô,
-- approval_status), pela mesma regra de lib/services/minha_conta.dart (faseDoCandidato).
-- O robô dos documentos (robo-documentos, desde 29/10) NÃO é duplicado: só se lhe junta
--   · o texto fixo do "falta enviar" (2 frases, PT-PT);
--   · o aviso "tudo em ordem, ficas na fila" (push + WhatsApp da Bora), uma vez por candidato.
-- Regra do Danilo (27/10): nunca "pouca procura" nem "não há pedidos".

-- 1. A fase de um candidato.
create or replace function public._candidato_fase(p_uid uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_status text;
  v_faltas int;
  v_recusou boolean := false;
  v_age boolean := public._robo_documentos_age();
begin
  select approval_status into v_status from public.drivers
   where user_id = p_uid and deleted_at is null order by created_at desc limit 1;
  if v_status = 'approved' then return 'aprovado'; end if;
  if v_status = 'rejected' then return 'recusado'; end if;
  v_faltas := coalesce(array_length(public._robo_documentos_faltas(p_uid), 1), 0);
  if v_age then
    select exists (
      select 1 from public.documentos_verificacoes dv
       where dv.user_id = p_uid and dv.revertido_em is null and dv.decisao = 'errado' and dv.acao <> 'nenhuma'
         and dv.id = (select max(d2.id) from public.documentos_verificacoes d2
                       where d2.user_id = p_uid and d2.campo = dv.campo and d2.revertido_em is null))
      into v_recusou;
  end if;
  if v_faltas > 0 or v_recusou then return 'documentos_pendentes'; end if;
  if v_age and not public._robo_documentos_pronto(p_uid) then return 'em_verificacao'; end if;
  return 'fila_de_espera';
end
$$;

-- 2. O painel /admin/estafetas: todos (ou um filtro), com a fase e o semáforo da 01.
create or replace function public.admin_estafetas_fila(p_filtro text default 'todos')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_out jsonb := '[]'::jsonb;
  r record;
  v_fase text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  for r in
    select d.user_id, d.name, d.phone, d.vehicle_type, d.approval_status, d.submitted_at, d.created_at
      from public.drivers d
     where d.deleted_at is null and d.approval_status in ('pending', 'approved')
       and not coalesce(public.is_demo_user(d.user_id), false)
     order by (d.approval_status = 'approved'), d.submitted_at nulls last, d.created_at
  loop
    v_fase := public._candidato_fase(r.user_id);
    continue when p_filtro = 'na_fila' and v_fase <> 'fila_de_espera';
    continue when p_filtro = 'incompletos' and v_fase <> 'documentos_pendentes';
    continue when p_filtro = 'aprovados' and v_fase <> 'aprovado';
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'user_id', r.user_id, 'nome', r.name, 'telefone', r.phone, 'vehicle_type', r.vehicle_type,
      'approval_status', r.approval_status, 'submitted_at', r.submitted_at, 'fase', v_fase,
      'conta', public.driver_minha_conta_estado(r.user_id)));
  end loop;
  return jsonb_build_object('ok', true, 'filtro', p_filtro, 'estafetas', v_out);
end
$$;

-- 3. Texto fixo do "falta enviar" (usado pelo robô no email e no aviso da app).
create or replace function public._robo_documentos_texto_pedido(p_faltas text[])
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $$
  select 'A tua inscrição ainda não está completa: falta enviar '
         || public._robo_documentos_juntar(p_faltas)
         || '. Envia aqui na app; assim que estiver tudo, passas para a fila de ativação.';
$$;

-- 4. "Tudo em ordem, ficas na fila" — uma vez por candidato (push + WhatsApp da Bora).
create or replace function public.robo_documentos_avisar_fila(p_uid uuid, p_quem text default 'robo')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_texto constant text :=
    'Está tudo em ordem com os teus documentos. Neste momento já temos estafetas suficientes para os '
    'pedidos atuais; ficas na fila e avisamos-te assim que a procura subir.';
  v_tel text;
  v_app jsonb;
  v_id bigint;
begin
  if p_uid is null then return jsonb_build_object('ok', false, 'porque', 'sem_user'); end if;
  if p_quem <> 'robo' and not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if public.is_demo_user(p_uid) then return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'demo'); end if;
  if public._candidato_fase(p_uid) <> 'fila_de_espera' then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'nao_esta_na_fila');
  end if;
  if exists (select 1 from public.documentos_lembretes_enviados e where e.user_id = p_uid and e.quem = 'fila') then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'ja_avisado');
  end if;

  v_app := public._provider_atividade_avisar(p_uid, 'Bora: os teus documentos estão em ordem', v_texto);

  select nullif(regexp_replace(coalesce(d.phone, ''), '[^0-9+]', '', 'g'), '') into v_tel
    from public.drivers d where d.user_id = p_uid and d.deleted_at is null order by d.created_at desc limit 1;
  if v_tel is not null then
    insert into public.whatsapp_saida (numero, texto, motivo, origem)
    values (v_tel, v_texto, 'robo-documentos-fila', 'm2-estafeta-2026-11-08');
  end if;

  insert into public.documentos_lembretes_enviados (user_id, dia, quem, faltas, assunto, texto, aviso_app)
  values (p_uid, -1, 'fila', '{}'::text[], 'Bora: os teus documentos estão em ordem', v_texto, v_app)
  returning id into v_id;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'aviso-fila', 'ok',
          'u=' || left(p_uid::text, 8) || ' whatsapp=' || (v_tel is not null)::text, 'servidor');

  return jsonb_build_object('ok', true, 'enviado', true, 'id', v_id, 'whatsapp', v_tel is not null);
end
$$;

-- 5. Corrida diária (ligar ao pg_cron junto com robo_documentos_avisos_correr, por exemplo 10:15 Lisboa).
create or replace function public.robo_documentos_fila_correr()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  r record;
  n int := 0;
  v jsonb;
begin
  for r in select d.user_id from public.drivers d
            where d.deleted_at is null and d.approval_status = 'pending'
  loop
    v := public.robo_documentos_avisar_fila(r.user_id, 'robo');
    if coalesce((v ->> 'enviado')::boolean, false) then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'avisados', n);
end
$$;

revoke all on function public._candidato_fase(uuid) from public, anon;
revoke all on function public.admin_estafetas_fila(text) from public, anon;
revoke all on function public.robo_documentos_avisar_fila(uuid, text) from public, anon, authenticated;
revoke all on function public.robo_documentos_fila_correr() from public, anon, authenticated;
grant execute on function public._candidato_fase(uuid) to authenticated;
grant execute on function public.admin_estafetas_fila(text) to authenticated;
-- robo_documentos_avisar_fila / _correr: só service_role e pg_cron (postgres).

-- Ligar a corrida (a Claude.ai decide a hora; exemplo):
-- select cron.schedule('robo-documentos-fila', '15 10 * * *', $c$select public.robo_documentos_fila_correr()$c$);
