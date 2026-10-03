-- CONTA DEMO DE PARCEIRO + LOJA INVISIVEL AOS CLIENTES (2026-09-10).
--
-- Ordem do Danilo: "PARCEIRO: ainda nao foi testado por ninguem. Cria uma
-- conta demo de parceiro com uma loja de demonstracao invisivel aos
-- clientes." Nao havia nenhuma: so' contas de parceiros REAIS, que nao se
-- emprestam.
--
-- Porque e' que a loja fica INVISIVEL sem tocar em codigo: o painel do
-- parceiro so' encontra a loja na lista publica (approved + is_active_admin),
-- por isso ela TEM de estar la. Mas cada ecra de cliente lista por categoria
-- (restaurant, supermarket/store/pharmacy, festas, sobremesa) -- e NENHUM
-- lista `beauty`, que existe no enum para os prestadores de servicos. Uma
-- loja `beauty` sem extra_categories esta na lista publica e nao aparece em
-- ecra nenhum do cliente. Por seguranca vai tambem offline e "em breve".
--
-- Receita igual a `repor_demo_apagar()`: auth.users + auth.identities com
-- bcrypt. O gatilho handle_new_auth_user cria a linha em public.users.
do $$
declare
  v_uid  uuid := 'dede0000-0000-4000-8000-000000000003';
  v_mail text := 'demo-parceiro@bora.app';
  v_pw   text := crypt('BoraDemo2026!', gen_salt('bf'));
  v_loja text := 'demo-parceiro-loja';
begin
  if not exists (select 1 from auth.users where id = v_uid or email = v_mail) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_sso_user, is_anonymous, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token)
    values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
      v_mail, v_pw, now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"bora_role":"partner","bora_name":"Demo Parceiro","bora_phone":"920000001",
        "bora_restaurant_name":"Loja Demo Bora (teste)","bora_address":"Praca Luis de Camoes, 6300-725 Guarda"}'::jsonb,
      false, false, '', '', '', '', '', '', '', '');

    insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (v_uid::text, v_uid,
            jsonb_build_object('sub', v_uid::text, 'email', v_mail, 'email_verified', true),
            'email', now(), now())
    on conflict do nothing;
  end if;

  update public.users
     set name = 'Demo Parceiro', role = 'partner', phone = '920000001'
   where id = v_uid;

  insert into public.user_roles (user_id, role, created_at)
  values (v_uid, 'partner', now())
  on conflict do nothing;

  if not exists (select 1 from public.restaurants where id = v_loja) then
    insert into public.restaurants (
      id, name, address, phone, email, is_partner, category,
      is_online, coming_soon, coming_soon_text,
      approval_status, is_active_admin, user_, user_id, lat, lng, submitted_at)
    values (
      v_loja, 'Loja Demo Bora (teste, nao e real)',
      'Praca Luis de Camoes, 6300-725 Guarda', '920000001', v_mail, true, 'beauty',
      false, true, 'Loja de demonstracao',
      'approved', true, v_uid, v_uid, 40.5373, -7.2659, now());
  end if;
end $$;