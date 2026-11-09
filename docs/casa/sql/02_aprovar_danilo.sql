-- PUBLICAÇÃO 2 da Casa — passo 2: o Danilo passa a profissional APROVADO da Casa, pelo caminho do painel.
-- Ordem do Danilo (02/11 e 09/11/2026): "quero ser eu o profissional aprovado da Casa por agora"; ofícios sem
-- certificado: montagem, fixação, reparações, canalização e jardinagem.
--
-- Como o painel faria: admin_casa_decidir_profissional(..., 'aprovar') e admin_casa_decidir_oficio(..., 'aprovar')
-- ofício a ofício — as MESMAS funções que os botões do painel chamam (auditoria em admin_audit_log pela
-- log_admin_action de cada uma). O painel não tem botão para JUNTAR ofícios a uma candidatura (quem os pede é
-- o profissional, na candidatura); os 3 que faltam entram com o mesmo INSERT que a casa_candidatura faz
-- (estado 'pending', ligado=true por defeito) e ficam registados no admin_audit_log.
--
-- Admin simulado como na M10: claims do JWT da conta do painel (c9fccf85…, admin), só durante esta transação.
-- ATENÇÃO (efeitos que o servidor faz sozinho, já autorizados a 09/11 06:56 mas a saber):
--  · a 1.ª aprovação de um profissional real liga a promoção "sem comissão" (casa_promo_meses=2) e o Danilo
--    passa a ocupar 1 das 5 vagas (casa_promo_primeiros_n=5) — ver "PARA O DANILO" no PUBLICACAO2-casa.md;
--  · cada aprovação manda um aviso (casa_status) à conta profissional do Danilo (503a2e09…), a ele próprio.
-- Idempotente: o que já estiver aprovado não se volta a aprovar.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_prof  constant uuid := 'ad8e790d-7519-4366-9565-257f816babd1';
  v_user  constant uuid := '503a2e09-2111-44b5-9852-d6d5897467f1';
  v_juntar constant text[] := array['reparacoes', 'canalizacao', 'jardinagem'];
  v_todos  constant text[] := array['montagem', 'fixacao', 'reparacoes', 'canalizacao', 'jardinagem'];
  v_of text;
  v_estado text;
  v_n int;
  r jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  perform set_config('bora.agente', 'publicacao2-casa', true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;

  -- Guarda: é mesmo a ficha da conta profissional do Danilo.
  if not exists (select 1 from public.casa_profissionais where id = v_prof and user_id = v_user) then
    raise exception 'profissional_inesperado';
  end if;

  -- 1) Juntar os ofícios sem certificado que faltam (por aprovar), como a casa_candidatura.
  insert into public.casa_profissional_oficios (profissional_id, oficio)
  select v_prof, x from unnest(v_juntar) x
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform public.log_admin_action('casa_oficio_juntar'::text, 'casa_profissionais'::text, v_prof::text,
      jsonb_build_object('oficios', v_juntar, 'juntados', v_n, 'via', 'publicacao2-casa',
                         'ordem', 'Danilo 09/11/2026 (m11 adendo 3): profissional da Casa por agora'));
  end if;

  -- 2) Aprovar o profissional (botão "Aprovar" da ficha no painel).
  select approval_status into v_estado from public.casa_profissionais where id = v_prof;
  if v_estado <> 'approved' then
    r := public.admin_casa_decidir_profissional(v_prof, 'aprovar', null);
    raise notice 'profissional: %', r;
  end if;

  -- 3) Aprovar ofício a ofício (botão "Aprovar" de cada ofício). Nenhum destes exige documento.
  foreach v_of in array v_todos loop
    select estado into v_estado from public.casa_profissional_oficios
     where profissional_id = v_prof and oficio = v_of;
    if v_estado is distinct from 'approved' then
      r := public.admin_casa_decidir_oficio(v_prof, v_of, 'aprovar', null);
      raise notice 'oficio %: %', v_of, r;
    end if;
  end loop;
end
$pub$;

-- Prova (lê de volta):
select p.approval_status, p.is_active, p.approved_at is not null as tem_data_aprovacao, p.sem_comissao_ate,
       (select string_agg(o.oficio || '=' || o.estado || (case when o.ligado then '+ligado' else '-desligado' end),
                          ', ' order by o.oficio)
          from public.casa_profissional_oficios o where o.profissional_id = p.id) as oficios
  from public.casa_profissionais p
 where p.id = 'ad8e790d-7519-4366-9565-257f816babd1';
