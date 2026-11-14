-- =============================================================================
-- farmacias-loja-2026-11-14 · c1 · Painel admin (Bloco 5): ficha completa da farmácia
--
-- 1) admin_farmacias_listar passa a devolver também o login (e-mail da conta do dono e o da loja,
--    se é de demonstração, último acesso, último link de senha), os dados da empresa que NÃO são
--    sensíveis (nome legal, código da certidão permanente, termos aceitos em) e a lista do que falta
--    para abrir ao público (_conformidade_em_falta). O NIF e o IBAN NÃO vêm aqui: o ecrã lê-os pela
--    parceiro_dados_fiscais(p_restaurant_id), como o cartão "Dados fiscais (DAC7)" da ficha do parceiro.
--    Todas as chaves antigas mantêm-se iguais (o ecrã de 11/11 continua a funcionar).
--    O portão continua public.is_admin() (igual a 11/11 — não muda quem vê a lista).
--
-- 2) admin_farmacia_certidao_definir(p_restaurant_id, p_codigo): grava o código da certidão
--    permanente (restaurants.business_registration_number) no formato 0000-0000-0000.
--    Vazio = apaga (para corrigir um código errado). Só admin, auditado com log_admin_action.
--
-- Não mexe em preços, comissões, pedidos, carteiras nem RLS.
-- =============================================================================

create or replace function public.admin_farmacias_listar()
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', r.id, 'name', r.name, 'approval_status', r.approval_status, 'is_active_admin', r.is_active_admin,
    'is_partner', r.is_partner,
    'coming_soon', r.coming_soon, 'so_lista_permissao', r.so_lista_permissao,
    'pharmacy_prescription_mode', r.pharmacy_prescription_mode,
    'partner_extra_commission_pct', r.partner_extra_commission_pct,
    'partner_extra_commission_starts_at', r.partner_extra_commission_starts_at,
    'aberta_ao_publico_em', r.aberta_ao_publico_em,
    -- login (14/11)
    'dono_user_id', coalesce(r.user_id, r.user_),
    'dono_email', u.email,
    'dono_email_confirmado', u.email_confirmed_at is not null,
    'dono_ultimo_login', u.last_sign_in_at,
    'dono_link_senha_em', u.recovery_sent_at,
    'email', nullif(btrim(coalesce(r.email, '')), ''),
    'email_demonstracao', (coalesce(u.email, '') ~* '^demo[._+-]' or coalesce(r.email, '') ~* '^demo[._+-]'),
    -- dados da empresa sem NIF/IBAN (14/11)
    'legal_name', r.legal_name,
    'business_registration_number', r.business_registration_number,
    'dsa_self_certified_at', r.dsa_self_certified_at,
    'dsa_self_cert_version', r.dsa_self_cert_version,
    'em_falta', to_jsonb(public._conformidade_em_falta(to_jsonb(r))),
    -- contagens (11/11)
    'produtos', (select count(*) from public.products p where p.restaurant_id = r.id),
    'produtos_provisorios', (select count(*) from public.products p where p.restaurant_id = r.id and p.preco_provisorio),
    'lista', (select coalesce(jsonb_agg(lu.email order by lu.email), '[]'::jsonb)
                from public.loja_lista_permissao l join auth.users lu on lu.id = l.user_id where l.restaurant_id = r.id),
    'pedidos_receita', (select count(*) from public.pedidos_prescricao pp where pp.restaurant_id = r.id))
  from public.restaurants r
  left join auth.users u on u.id = coalesce(r.user_id, r.user_)
  where r.category = 'pharmacy'
  order by r.so_lista_permissao desc, r.name;
end $function$;

revoke all on function public.admin_farmacias_listar() from public, anon;
grant execute on function public.admin_farmacias_listar() to authenticated;


create or replace function public.admin_farmacia_certidao_definir(p_restaurant_id text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_digitos text := regexp_replace(coalesce(p_codigo, ''), '[^0-9]', '', 'g');
  v_novo    text;
  v_antes   text;
begin
  if not public._is_admin(auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_digitos = '' then
    v_novo := null;  -- apagar um código errado
  elsif v_digitos !~ '^[0-9]{12}$' then
    raise exception 'certidao_invalida: o código da certidão permanente tem 12 dígitos (0000-0000-0000).'
      using errcode = 'P0001';
  else
    v_novo := substr(v_digitos, 1, 4) || '-' || substr(v_digitos, 5, 4) || '-' || substr(v_digitos, 9, 4);
  end if;

  select business_registration_number into v_antes
    from public.restaurants where id = p_restaurant_id and category = 'pharmacy';
  if not found then
    raise exception 'Farmácia não encontrada.' using errcode = 'P0002';
  end if;

  update public.restaurants set business_registration_number = v_novo
   where id = p_restaurant_id and category = 'pharmacy';

  perform public.log_admin_action('farmacia_certidao_definir'::text, 'restaurant'::text, p_restaurant_id::text,
    jsonb_build_object('antes', v_antes, 'depois', v_novo));

  return jsonb_build_object('ok', true, 'business_registration_number', v_novo);
end $function$;

revoke all on function public.admin_farmacia_certidao_definir(text, text) from public, anon;
grant execute on function public.admin_farmacia_certidao_definir(text, text) to authenticated;
