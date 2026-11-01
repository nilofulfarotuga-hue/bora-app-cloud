-- Avisos automaticos do robo de documentos: limite de 4 emails automaticos por candidato (depois disso so o
-- Danilo, pelo botao "Lembrar este" do painel). Sem isto, um candidato que abandonou a candidatura recebia o
-- mesmo email de 7 em 7 dias para sempre. Complemento da migracao 20261101200500.

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
  v_max_robo integer := 4;
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

  -- anti-repeticao: mesma lista em < 7 dias, ou qualquer aviso em < 24 h; e no maximo 4 automaticos
  if exists (select 1 from public.documentos_lembretes_enviados e
              where e.user_id = p_uid and e.enviado_em > now() - interval '7 days' and e.faltas = linhas) then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'ja_avisado_7_dias', 'linhas', to_jsonb(linhas));
  end if;
  if exists (select 1 from public.documentos_lembretes_enviados e
              where e.user_id = p_uid and e.enviado_em > now() - interval '24 hours') then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'ja_avisado_24h', 'linhas', to_jsonb(linhas));
  end if;
  if p_quem = 'robo' and (select count(*) from public.documentos_lembretes_enviados e
                           where e.user_id = p_uid and e.quem = 'robo') >= v_max_robo then
    return jsonb_build_object('ok', true, 'enviado', false, 'porque', 'limite_avisos_robo', 'linhas', to_jsonb(linhas));
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
revoke all on function public.robo_documentos_avisar_faltas(uuid, text) from public, anon, authenticated;
grant execute on function public.robo_documentos_avisar_faltas(uuid, text) to service_role;
