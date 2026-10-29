-- S1_prova_rollback.sql — PROVA em transação desfeita do S1 (missão final-app-2026-10-29, bloco 6.c).
-- Não deixa NADA no banco: o bloco acaba num RAISE EXCEPTION que desfaz tudo (política, vista e função
-- de nome temporário get_setting_s1_teste incluídas). Correr com execute_sql; o resultado vem na mensagem
-- de erro "RESULT ...". Só lê; nunca imprime o valor de uma chave secreta (só "NULL" ou "VALOR").
-- Atores: anon · cliente (conta sem loja, não admin) · parceiro (dono de loja) · admin · service_role.
-- Limite conhecido: o editor SQL liga-se como postgres e não deixa mudar o session_user para
-- 'authenticator'; por isso o ramo "sem claims" só se prova como postgres (valor) — o caso real do
-- PostgREST (authenticator, sem claims) fica provado pela expressão, não ao vivo.

do $prova$
declare
  r text := E'S1 prova (transacao desfeita)\n';
  v_cli uuid; v_adm uuid; v_parc uuid;
  a record; v text;
  n_sec int; n_all int; n_par int; n_view int; n_view_sec int; n_guia int;
  m0 text; m1 text; m2 text; m3 text;
  lista text[] := array[
    'app_latest_version_code','app_latest_version_code_ios','app_min_supported_version_code','app_min_supported_version_code_ios','app_update_notes_pt',
    'appointment_max_advance_days','appointment_reschedule_max_count','assistant_enabled','cancel_fee_after_accept_cents','cancel_fee_after_pickup_ratio',
    'cancel_fee_before_dispatch_cents','cancel_grace_seconds','carwash_enabled','carwash_interior_enabled','carwash_stripe_enabled',
    'cleaning_cancel_free_hours','cleaning_cancel_half_hours','cleaning_min_hours','cleaning_min_lead_hours','cleaning_stripe_enabled',
    'client_live_location_enabled','client_live_location_interval_seconds','delivery_base_fee_cents','dispatch_gps_fresh_seconds','dispatch_offer_timeout_seconds',
    'errand_home_stop_fee_cents','errand_max_advance_cents','eta_avg_speed_kmh','eta_shopping_minutes_nonpartner_max','eta_shopping_minutes_nonpartner_min',
    'favor_pellets_max_sacos','ios_hide_nonpartner_logos','map_route_line_width','max_cash_amount_cents','min_order_cents',
    'non_partner_service_fee_cents','non_partner_service_fee_strikethrough_cents','order_edit_enabled','payment_sheet_timeout_seconds','sessao_convidado_ativa',
    'small_order_fee_cents','small_order_fee_enabled','tips_enabled','token_balance_max_use_pct','token_payment_max_pct',
    'token_value_cents_x100','tvde_base_distance_km','tvde_card_payments_enabled','tvde_dest_change_enabled','tvde_driver_card_poll_seconds',
    'tvde_driver_lost_seconds','tvde_driver_stale_seconds','tvde_encomendas_enabled','tvde_eta_arriving_push_min','tvde_eta_client_discount_max_min',
    'tvde_eta_client_discount_pct','tvde_eta_client_floor_min','tvde_extra_per_km_cents','tvde_extra_ride_cents','tvde_max_stops',
    'tvde_nav_camera_follow_ms','tvde_nav_offroute_fixes','tvde_nav_offroute_meters','tvde_nav_reroute_min_seconds','tvde_nav_tilt',
    'tvde_nav_zoom','tvde_noshow_wait_minutes','tvde_pos_ao_vivo_enabled','tvde_pos_ao_vivo_intervalo_s','tvde_reservation_dest_change_enabled',
    'tvde_reservation_enabled','tvde_reservation_free_cancel_hours','tvde_reservation_max_advance_days','tvde_reservation_min_advance_minutes','tvde_reservation_payment_timeout_minutes',
    'tvde_ride_gps_interval_seconds','tvde_roundtrip_reservation_enabled','tvde_stop_fee_cents','tvde_stop_timer_seconds','visitantes_sem_conta',
    'wallet_split_free_pct','web_card_payments_enabled'];
begin
  -- atores reais (só leitura)
  select u.id into v_adm from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='admin' order by u.created_at limit 1;
  select q.user_id into v_parc from public.restaurants q where q.user_id is not null and q.user_id is distinct from v_adm order by q.id limit 1;
  select u.id into v_cli from auth.users u
   where u.id is distinct from v_adm and u.id is distinct from v_parc
     and coalesce(u.raw_app_meta_data->>'role','') <> 'admin'
     and not exists (select 1 from public.restaurants q where q.user_id = u.id or q.user_ = u.id)
   order by u.created_at desc limit 1;
  if v_adm is null or v_parc is null or v_cli is null then raise exception 'sem ator (adm=% parc=% cli=%)', v_adm, v_parc, v_cli; end if;

  -- ===== ANTES: produção como está =====
  for a in select * from (values
      ('anon','anon','{"role":"anon"}'),
      ('cliente','authenticated', json_build_object('sub',v_cli,'role','authenticated')::text),
      ('parceiro','authenticated', json_build_object('sub',v_parc,'role','authenticated')::text),
      ('admin','authenticated', json_build_object('sub',v_adm,'role','authenticated')::text),
      ('service_role','service_role','{"role":"service_role"}')
    ) t(lbl, rol, cl) loop
    perform set_config('request.jwt.claims', a.cl, true);
    execute format('set local role %I', a.rol);
    select count(*) filter (where is_secret), count(*) into n_sec, n_all from public.platform_settings;
    v := public.get_setting('bora_mbway_phone')::text;
    reset role;
    r := r || format(E'ANTES   %-12s tabela: %s secretas de %s linhas | get_setting(secreta): %s\n', a.lbl, n_sec, n_all, case when v is null then 'NULL' else 'VALOR' end);
  end loop;
  -- fuga da função antiga sem claims, como papel authenticated (o current_user dentro da função é o dono)
  perform set_config('request.jwt.claims', '', true);
  set local role authenticated;
  v := public.get_setting('bora_mbway_phone')::text;
  reset role;
  r := r || format(E'ANTES   sem claims, papel authenticated: get_setting(secreta) = %s   <- a fuga\n', case when v is null then 'NULL' else 'VALOR' end);

  -- ===== aplica o S1 (tudo desfeito no fim) =====
  execute $d$ drop policy platform_settings_select_authed on public.platform_settings $d$;
  execute $d$ create policy platform_settings_select_sem_segredos on public.platform_settings
      for select to authenticated
      using (
        coalesce(is_secret, false) = false
        or (select public.is_admin())
        or ( key in ('partner_visible_commission_pct', 'partner_hidden_markup_pct')
             and exists (select 1 from public.parceiro_minhas_lojas()) )
      ) $d$;
  execute format($d$ create view public.platform_settings_publicas with (security_barrier = true) as
      select s.key, s.value from public.platform_settings s
       where coalesce(s.is_secret, false) = false
         and ( s.key = any (%L::text[]) or s.key like 'limpeza\_guia\_%%' ) $d$, lista);
  execute 'revoke all on public.platform_settings_publicas from public, anon, authenticated';
  execute 'grant select on public.platform_settings_publicas to anon, authenticated';
  execute $f$ create function public.get_setting_s1_teste(p_key text) returns jsonb
      language plpgsql stable security definer set search_path to 'public' as $corpo$
    declare v_row record; v_claims text; v_role text; v_admin boolean := false;
    begin
      select value, is_secret into v_row from public.platform_settings where key = p_key;
      if not found then return null; end if;
      if not v_row.is_secret then return v_row.value; end if;
      v_claims := nullif(current_setting('request.jwt.claims', true), '');
      if v_claims is not null then
        begin v_role := v_claims::jsonb ->> 'role'; exception when others then v_role := null; end;
        if v_role = 'service_role' then return v_row.value; end if;
        begin v_admin := public.is_admin(); exception when others then v_admin := false; end;
        if v_admin then return v_row.value; end if;
        return null;
      end if;
      if session_user in ('postgres', 'supabase_admin') then return v_row.value; end if;
      return null;
    end $corpo$ $f$;
  execute 'grant execute on function public.get_setting_s1_teste(text) to anon, authenticated, service_role';

  -- ===== DEPOIS =====
  for a in select * from (values
      ('anon','anon','{"role":"anon"}'),
      ('cliente','authenticated', json_build_object('sub',v_cli,'role','authenticated')::text),
      ('parceiro','authenticated', json_build_object('sub',v_parc,'role','authenticated')::text),
      ('admin','authenticated', json_build_object('sub',v_adm,'role','authenticated')::text),
      ('service_role','service_role','{"role":"service_role"}')
    ) t(lbl, rol, cl) loop
    perform set_config('request.jwt.claims', a.cl, true);
    execute format('set local role %I', a.rol);
    select count(*) filter (where is_secret), count(*) into n_sec, n_all from public.platform_settings;
    select count(*) into n_par from public.platform_settings where key in ('partner_visible_commission_pct','partner_hidden_markup_pct');
    v := public.get_setting_s1_teste('bora_mbway_phone')::text;
    select count(*), count(*) filter (where key like 'limpeza\_guia\_%') into n_view, n_guia from public.platform_settings_publicas;
    select count(*) into n_view_sec from public.platform_settings_publicas p join public.platform_settings s on s.key = p.key where s.is_secret;
    reset role;
    r := r || format(E'DEPOIS  %-12s tabela: %s secretas de %s linhas | chaves dos parceiros: %s de 2 | get_setting(secreta): %s | vista: %s linhas (%s guia, %s secretas)\n',
                     a.lbl, n_sec, n_all, n_par, case when v is null then 'NULL' else 'VALOR' end, n_view, n_guia, n_view_sec);
  end loop;
  -- claims vazios '{}' (pedido sem papel) e sem claims nenhum (interno, como postgres)
  perform set_config('request.jwt.claims', '{}', true);
  v := public.get_setting_s1_teste('bora_mbway_phone')::text;
  r := r || format(E'DEPOIS  claims vazios {}: get_setting(secreta) = %s\n', case when v is null then 'NULL' else 'VALOR' end);
  perform set_config('request.jwt.claims', '', true);
  v := public.get_setting_s1_teste('bora_mbway_phone')::text;
  r := r || format(E'DEPOIS  interno sem claims (session_user=%s): get_setting(secreta) = %s\n', session_user, case when v is null then 'NULL' else 'VALOR' end);
  set local role authenticated;
  v := public.get_setting_s1_teste('bora_mbway_phone')::text;
  reset role;
  r := r || format(E'DEPOIS  sem claims, papel authenticated, ligacao postgres (limite do editor): %s\n', case when v is null then 'NULL' else 'VALOR' end);

  -- ===== as chaves da app abrem iguais (82 nomes da lista; 81 existem) =====
  select md5(string_agg(key || '=' || value::text, ',' order by key)), count(*)::text into m0, v from public.platform_settings where key = any(lista) and coalesce(is_secret,false) = false;
  r := r || format(E'IGUAIS  referencia (como postgres): %s chaves, md5 %s\n', v, left(m0, 10));
  perform set_config('request.jwt.claims', json_build_object('sub',v_cli,'role','authenticated')::text, true);
  set local role authenticated;
  select md5(string_agg(key || '=' || value::text, ',' order by key)) into m1 from public.platform_settings where key = any(lista);
  select md5(string_agg(key || '=' || value::text, ',' order by key)) into m2 from public.platform_settings_publicas where key = any(lista);
  select md5(string_agg(k || '=' || coalesce(public.get_setting_s1_teste(k)::text, 'null'), ',' order by k)) into m3
    from unnest(lista) k where exists (select 1 from public.platform_settings p where p.key = k);
  reset role;
  r := r || format(E'IGUAIS  cliente por tabela md5 %s | por vista md5 %s | por get_setting md5 %s | tudo igual: %s\n', left(m1,10), left(m2,10), left(m3,10), (m0 = m1 and m1 = m2 and m2 = m3));
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  select md5(string_agg(key || '=' || value::text, ',' order by key)) into m1 from public.platform_settings_publicas where key = any(lista);
  reset role;
  r := r || format(E'IGUAIS  anon por vista md5 %s | igual ao da referencia: %s\n', left(m1,10), (m0 = m1));

  raise exception 'RESULT %', r;
end
$prova$;
