-- Missão boom-hamburguer-mes (bloco R2, ordem do Danilo de 03/11/2026): painel admin PT-BR do aviso de
-- carrinho esquecido — lista de emails excluídos (editar) e avisos "loja ficou mais barata"
-- (criar / ver / terminar), com quantos foram avisados e quantos voltaram a pedir. Só admin; auditoria.

create or replace function public.admin_carrinho_extras()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_excl jsonb;
  v_avisos jsonb;
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  select value into v_excl from platform_settings where key = 'carrinho_abandonado_excluir_emails';
  select coalesce(jsonb_agg(x order by x.mudou_em desc), '[]'::jsonb) into v_avisos
    from (
      select lm.id, lm.loja_id, coalesce(r.name, lm.loja_id) as loja, lm.titulo, lm.texto,
             lm.mudou_em, lm.valido_ate, lm.criado_por,
             (lm.valido_ate is null or lm.valido_ate > now()) as ativo,
             (select count(*) from carrinhos_abandonados c
               where c.loja_id = lm.loja_id and c.avisado_em >= lm.mudou_em
                 and c.atualizado_em < lm.mudou_em
                 and (lm.valido_ate is null or c.avisado_em <= lm.valido_ate)) as avisados,
             (select count(*) from carrinhos_abandonados c
               where c.loja_id = lm.loja_id and c.avisado_em >= lm.mudou_em
                 and c.atualizado_em < lm.mudou_em
                 and (lm.valido_ate is null or c.avisado_em <= lm.valido_ate)
                 and exists (select 1 from orders o where o.user_id = c.user_id
                               and o.created_at > c.avisado_em)) as voltaram_a_pedir
        from lojas_mais_baratas lm
        left join restaurants r on r.id = lm.loja_id
       limit 100
    ) x;
  return jsonb_build_object('excluir_emails', coalesce(v_excl, '[]'::jsonb), 'avisos', v_avisos);
end
$function$;

create or replace function public.admin_carrinho_excluir_emails_definir(p_emails jsonb)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_lista jsonb;
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_emails, '[]'::jsonb)) <> 'array' then raise exception 'lista_invalida'; end if;
  select coalesce(jsonb_agg(distinct lower(trim(e))), '[]'::jsonb) into v_lista
    from jsonb_array_elements_text(coalesce(p_emails, '[]'::jsonb)) e
   where nullif(trim(e), '') is not null;
  insert into platform_settings (key, value, updated_at, updated_by)
  values ('carrinho_abandonado_excluir_emails', v_lista, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  insert into admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'carrinho_excluir_emails', 'platform_settings', 'carrinho_abandonado_excluir_emails',
          jsonb_build_object('emails', v_lista));
  return public.admin_carrinho_extras();
end
$function$;

create or replace function public.admin_loja_mais_barata_guardar(
  p_id bigint, p_loja_id text, p_titulo text, p_texto text, p_valido_ate timestamptz)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_id bigint := p_id;
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  if not exists (select 1 from restaurants where id = p_loja_id) then raise exception 'loja_nao_encontrada'; end if;
  if nullif(trim(p_titulo), '') is null or nullif(trim(p_texto), '') is null then
    raise exception 'titulo_e_texto_obrigatorios';
  end if;
  if v_id is null then
    insert into lojas_mais_baratas (loja_id, titulo, texto, valido_ate, criado_por)
    values (p_loja_id, left(trim(p_titulo), 80), left(trim(p_texto), 240), p_valido_ate, 'admin')
    returning id into v_id;
  else
    update lojas_mais_baratas
       set loja_id = p_loja_id, titulo = left(trim(p_titulo), 80), texto = left(trim(p_texto), 240),
           valido_ate = p_valido_ate
     where id = v_id;
  end if;
  insert into admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'loja_mais_barata_guardar', 'lojas_mais_baratas', v_id::text,
          jsonb_build_object('loja_id', p_loja_id, 'valido_ate', p_valido_ate));
  return public.admin_carrinho_extras();
end
$function$;

create or replace function public.admin_loja_mais_barata_terminar(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  update lojas_mais_baratas set valido_ate = now()
   where id = p_id and (valido_ate is null or valido_ate > now());
  insert into admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'loja_mais_barata_terminar', 'lojas_mais_baratas', p_id::text, '{}'::jsonb);
  return public.admin_carrinho_extras();
end
$function$;

revoke all on function public.admin_carrinho_extras() from public, anon;
revoke all on function public.admin_carrinho_excluir_emails_definir(jsonb) from public, anon;
revoke all on function public.admin_loja_mais_barata_guardar(bigint, text, text, text, timestamptz) from public, anon;
revoke all on function public.admin_loja_mais_barata_terminar(bigint) from public, anon;
grant execute on function public.admin_carrinho_extras() to authenticated;
grant execute on function public.admin_carrinho_excluir_emails_definir(jsonb) to authenticated;
grant execute on function public.admin_loja_mais_barata_guardar(bigint, text, text, text, timestamptz) to authenticated;
grant execute on function public.admin_loja_mais_barata_terminar(bigint) to authenticated;
-- A tabela tem RLS só admin; o anon não precisa de privilégios nela.
revoke all on public.lojas_mais_baratas from anon;
