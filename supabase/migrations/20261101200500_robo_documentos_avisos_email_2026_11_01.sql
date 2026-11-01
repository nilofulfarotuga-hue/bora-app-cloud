-- Robo "fiscal de documentos" — avisos por email ao candidato (ordem do Danilo 01/11/2026 19:56, ponto 11):
--   "e so para o robo continuar vendo se o documento ta certo. O que tiver faltando tem que mandar o robo
--    mandar e-mail para as pessoas falando que ta faltando documento."
--
-- O que muda:
--   • O robo, MESMO em modo "sombra", passa a avisar o candidato por email (suporte@boraguarda.com, via
--     agentes-email-enviar/Resend) e por aviso na app quando lhe falta um documento, quando enviou o
--     documento errado, ilegivel ou fora de validade (veredito 'errado' do robo). NUNCA aprova nem recusa.
--   • Anti-repeticao: o mesmo aviso (mesma lista de faltas) nao se repete ao mesmo candidato em menos de
--     7 dias; e nunca mais de um aviso por candidato em 24 h.
--   • Registo: documentos_lembretes_enviados (quem='robo', com assunto, texto e o pedido de email) — e o
--     painel le com admin_documentos_avisos(). Interruptor: platform_settings.robo_documentos_avisos_ativo.
--   • Cron diario as 10:00 de Lisboa (robo-documentos-avisos). O cron antigo dos lembretes (dias 1/3/7,
--     so em modo ativo) fica como esta.

-- ── registo ────────────────────────────────────────────────────────────────────────
alter table public.documentos_lembretes_enviados drop constraint if exists documentos_lembretes_quem_ck;
alter table public.documentos_lembretes_enviados
  add constraint documentos_lembretes_quem_ck check (quem in ('cron','painel','robo'));
alter table public.documentos_lembretes_enviados
  add column if not exists assunto text,
  add column if not exists texto text,
  add column if not exists email_para text,
  add column if not exists email_pedido bigint,
  add column if not exists aviso_app jsonb;

insert into public.platform_settings (key, value, description, category) values
  ('robo_documentos_avisos_ativo', 'true'::jsonb,
   'Robo de documentos: avisa por email e na app o candidato a quem falta documento ou que enviou o documento errado (funciona em sombra e em ativo; nunca aprova).', 'documentos')
on conflict (key) do nothing;

-- ── o que falta a UMA pessoa, ja em frases (faltas + vereditos 'errado' do robo) ───────
create or replace function public._robo_documentos_linhas_aviso(p_uid uuid)
returns text[] language plpgsql stable security definer set search_path to 'public' as $f$
declare
  linhas text[] := '{}';
  faltas text[] := public._robo_documentos_faltas(p_uid);
  al jsonb := public._robo_documentos_alvos(p_uid);
  x jsonb;
  v record;
  f text;
  comprovativo_errado boolean := false;
begin
  if not coalesce((al ->> 'pendente')::boolean, false) then return linhas; end if;

  -- 1) documentos enviados mas errados / ilegiveis / fora de prazo (ultimo veredito do ficheiro atual)
  for x in select * from jsonb_array_elements(al -> 'alvos') loop
    select dv.decisao, dv.motivo_pt, dv.campo into v from public.documentos_verificacoes dv
     where dv.user_id = p_uid and dv.campo = x ->> 'campo' and dv.path = x ->> 'path' and dv.revertido_em is null
     order by dv.id desc limit 1;
    if found and v.decisao = 'errado' and coalesce(v.motivo_pt, '') <> '' then
      if v.campo = 'provider_atividade.documento_path' then comprovativo_errado := true; end if;
      linhas := array_append(linhas, v.motivo_pt);
    end if;
  end loop;

  -- 2) documentos que ainda nao foram enviados
  foreach f in array faltas loop
    if f = 'comprovativo de atividade' and comprovativo_errado then continue; end if;
    linhas := array_append(linhas, 'Falta enviar: ' || f || '.');
  end loop;

  return linhas;
end
$f$;

-- ── texto do email (PT-PT, curto, humano, assinado Equipa Bora; nunca promete aprovacao) ──
create or replace function public._robo_documentos_texto_email(p_uid uuid, p_linhas text[])
returns text language plpgsql stable security definer set search_path to 'public' as $f$
declare
  nome text := public._robo_documentos_nome_conta(p_uid);
  primeiro text;
  papeis text[] := public._provider_atividade_papeis(p_uid);
  papel text;
  corpo text;
  l text;
begin
  primeiro := nullif(split_part(coalesce(nome, ''), ' ', 1), '');
  papel := case
    when 'limpeza' = any(papeis) then 'profissional de limpeza'
    when 'lavagem' = any(papeis) then 'lavador(a) de carros'
    when 'motorista_tvde' = any(papeis) then 'motorista'
    when 'servicos' = any(papeis) then 'prestador(a) de serviços'
    else 'estafeta' end;
  corpo := 'Olá' || coalesce(' ' || primeiro, '') || '!' || E'\n\n'
        || 'Vimos a tua candidatura a ' || papel || ' no Bora e ainda falta resolver isto:' || E'\n';
  foreach l in array p_linhas loop
    corpo := corpo || E'\n' || '- ' || l;
  end loop;
  corpo := corpo || E'\n\n'
        || 'Para enviar: abre a app Bora, entra com a tua conta e toca em "Falta enviar", logo à entrada. '
        || 'Assim que estiver tudo, a tua candidatura entra na fila de análise.' || E'\n\n'
        || 'Se precisares de ajuda, responde a este email.' || E'\n\n'
        || 'Equipa Bora';
  return corpo;
end
$f$;

-- ── avisa UMA pessoa (email + aviso na app), com anti-repeticao. Nunca aprova nem recusa. ──
create or replace function public.robo_documentos_avisar_faltas(p_uid uuid, p_quem text default 'robo')
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  linhas text[];
  v_assunto text := 'Bora: faltam documentos na tua candidatura';
  v_texto text;
  v_email text;
  v_req bigint;
  v_app jsonb;
  v_id bigint;
  v_ligado boolean := coalesce((select (value #>> '{}')::boolean from public.platform_settings
                                 where key = 'robo_documentos_avisos_ativo'), true);
begin
  if p_uid is null then return jsonb_build_object('ok', false, 'porque', 'sem_user'); end if;
  if not v_ligado then return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'desligado'); end if;
  if public.is_demo_user(p_uid) then return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'demo'); end if;

  linhas := public._robo_documentos_linhas_aviso(p_uid);
  if coalesce(array_length(linhas, 1), 0) = 0 then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'nada_em_falta');
  end if;

  -- anti-repeticao: mesma lista em < 7 dias, ou qualquer aviso em < 24 h
  if exists (select 1 from public.documentos_lembretes_enviados e
              where e.user_id = p_uid and e.enviado_em > now() - interval '7 days' and e.faltas = linhas) then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'ja_avisado_7_dias', 'linhas', to_jsonb(linhas));
  end if;
  if exists (select 1 from public.documentos_lembretes_enviados e
              where e.user_id = p_uid and e.enviado_em > now() - interval '24 hours') then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'ja_avisado_24h', 'linhas', to_jsonb(linhas));
  end if;

  select u.email into v_email from auth.users u where u.id = p_uid;
  v_texto := public._robo_documentos_texto_email(p_uid, linhas);

  v_req := public._robo_documentos_email(p_uid, v_assunto, v_texto);
  v_app := public._provider_atividade_avisar(p_uid, 'Faltam documentos na tua candidatura',
             'Ainda falta: ' || public._robo_documentos_juntar(array(
               select regexp_replace(l, '^Falta enviar: (.*)\.$', '\1') from unnest(linhas) l))
             || '. Abre "Falta enviar" na app e envia o que falta.');

  insert into public.documentos_lembretes_enviados (user_id, dia, quem, faltas, assunto, texto, email_para, email_pedido, aviso_app)
  values (p_uid, -1, p_quem, linhas, v_assunto, v_texto, v_email, v_req, v_app)
  returning id into v_id;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'aviso-email', case when v_req is null then 'sem_email' else 'ok' end,
          'u=' || left(p_uid::text, 8) || ' para=' || coalesce(v_email, '?') || ' pedido=' || coalesce(v_req::text, 'null')
          || ' linhas=' || array_length(linhas, 1), 'servidor');

  return jsonb_build_object('ok', true, 'enviado', v_req is not null, 'id', v_id, 'para', v_email,
                            'email_pedido', v_req, 'linhas', to_jsonb(linhas));
end
$f$;

-- ── corre para todos os candidatos pendentes (cron diario 10:00 Lisboa; p_ignorar_hora para correr ja) ──
create or replace function public.robo_documentos_avisos_correr(p_ignorar_hora boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_uid uuid;
  r jsonb;
  n_vistos integer := 0;
  n_enviados integer := 0;
  n_saltados integer := 0;
  res jsonb := '[]'::jsonb;
begin
  if not coalesce(p_ignorar_hora, false)
     and extract(hour from (now() at time zone 'Europe/Lisbon')) <> 10 then
    return jsonb_build_object('ok', true, 'enviados', 0, 'porque', 'fora_de_horas');
  end if;
  for v_uid in
    select distinct x.u from (
      select user_id as u from public.drivers where approval_status = 'pending' and deleted_at is null
      union select user_id from public.cleaners where approval_status = 'pending'
      union select user_id from public.washers where approval_status = 'pending'
      union select user_id from public.service_providers where approval_status = 'pending'
    ) x where x.u is not null and not public.is_demo_user(x.u)
  loop
    n_vistos := n_vistos + 1;
    r := public.robo_documentos_avisar_faltas(v_uid, 'robo');
    if coalesce((r ->> 'enviado')::boolean, false) then n_enviados := n_enviados + 1; else n_saltados := n_saltados + 1; end if;
    res := res || jsonb_build_array(jsonb_build_object('user_id', v_uid, 'enviado', r -> 'enviado', 'porque', r -> 'porque', 'para', r -> 'para'));
  end loop;
  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'avisos', 'ok', 'candidatos=' || n_vistos || ' enviados=' || n_enviados || ' saltados=' || n_saltados, 'servidor');
  return jsonb_build_object('ok', true, 'candidatos', n_vistos, 'enviados', n_enviados, 'saltados', n_saltados, 'detalhe', res);
end
$f$;

-- ── painel (so admin): os avisos ja enviados a um candidato (ou a todos) ──
create or replace function public.admin_documentos_avisos(p_user_id uuid default null, p_limite integer default 200)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.enviado_em desc) from (
      select e.id, e.user_id, public._robo_documentos_nome_conta(e.user_id) as nome, e.quem, e.dia, e.faltas,
             e.assunto, e.email_para, e.email_pedido, e.enviado_em,
             (select ae.estado from public.agentes_email ae
               where ae.direcao = 'saida' and ae.para = e.email_para and ae.assunto = e.assunto
                 and ae.criado_em between e.enviado_em - interval '1 minute' and e.enviado_em + interval '10 minutes'
               order by ae.criado_em desc limit 1) as email_estado
        from public.documentos_lembretes_enviados e
       where p_user_id is null or e.user_id = p_user_id
       order by e.enviado_em desc
       limit least(greatest(coalesce(p_limite, 200), 1), 1000)
    ) x), '[]'::jsonb);
end
$f$;

-- ── permissoes ──
revoke all on function public._robo_documentos_linhas_aviso(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_texto_email(uuid, text[]) from public, anon, authenticated;
revoke all on function public.robo_documentos_avisar_faltas(uuid, text) from public, anon, authenticated;
revoke all on function public.robo_documentos_avisos_correr(boolean) from public, anon, authenticated;
revoke all on function public.admin_documentos_avisos(uuid, integer) from public, anon;
grant execute on function public.robo_documentos_avisar_faltas(uuid, text) to service_role;
grant execute on function public.robo_documentos_avisos_correr(boolean) to service_role;
grant execute on function public.admin_documentos_avisos(uuid, integer) to authenticated;

-- ── cron: 09:00 e 10:00 UTC; so avanca quando em Lisboa sao 10h ──
select cron.unschedule('robo-documentos-avisos') where exists (select 1 from cron.job where jobname = 'robo-documentos-avisos');
select cron.schedule('robo-documentos-avisos', '0 9,10 * * *', 'select public.robo_documentos_avisos_correr()');
