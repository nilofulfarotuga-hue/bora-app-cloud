-- PROVA da migração 20261029200600_c6_modo_ocupado.sql — correr DEPOIS de a aplicar.
-- Não deixa rasto: o que escreve vive num sub-bloco que se desfaz sempre
-- (RAISE 'PROVA_DESFEITA'). Acaba com NOTICE "PROVA C6 MIGRACAO OK" ou com uma
-- EXCEPTION a dizer o que falhou. No editor SQL do Supabase não há sessão
-- (auth.uid() é nulo), o que também prova que sem sessão as funções recusam.

do $prova$
declare
  v_rest  text;
  v_n     integer;
  v_r     jsonb;
  v_f     text;
begin
  -- 1) as funções existem
  foreach v_f in array array[
    'public.partner_busy_extra_minutes(text)',
    'public.partner_set_busy(text,integer)',
    'public.admin_partner_busy_list()',
    'public.admin_partner_busy_desligar(text)',
    'public.partner_set_ready_at(text,timestamptz)',
    'public._partner_busy_mode_on()'
  ] loop
    if to_regprocedure(v_f) is null then
      raise exception 'PROVA C6 FALHOU: falta a funcao %', v_f;
    end if;
    -- 2) fechadas a anon
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'PROVA C6 FALHOU: % esta aberta a anon', v_f;
    end if;
  end loop;

  -- 3) colunas
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'restaurants' and column_name = 'busy_until')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'restaurants' and column_name = 'busy_extra_minutes')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'orders' and column_name = 'ready_at_promised') then
    raise exception 'PROVA C6 FALHOU: falta uma coluna nova';
  end if;

  -- 4) o interruptor existe
  if not exists (select 1 from public.platform_settings where key = 'partner_busy_mode_enabled') then
    raise exception 'PROVA C6 FALHOU: falta o interruptor partner_busy_mode_enabled';
  end if;
  raise notice 'interruptor agora = %', (select value from public.platform_settings where key = 'partner_busy_mode_enabled');

  select id into v_rest from public.restaurants limit 1;
  if v_rest is null then
    raise notice 'PARTE DOS DADOS SALTADA: nao ha restaurantes';
    return;
  end if;

  begin
    -- 5) interruptor DESLIGADO: devolve 0 mesmo com a loja marcada ocupada
    update public.platform_settings set value = 'false'::jsonb where key = 'partner_busy_mode_enabled';
    update public.restaurants set busy_extra_minutes = 20, busy_until = now() + interval '1 hour' where id = v_rest;
    if public.partner_busy_extra_minutes(v_rest) <> 0 then
      raise exception 'PROVA C6 FALHOU: com o interruptor desligado devia dar 0'; end if;

    -- 6) LIGADO: dá os minutos
    update public.platform_settings set value = 'true'::jsonb where key = 'partner_busy_mode_enabled';
    v_n := public.partner_busy_extra_minutes(v_rest);
    if v_n <> 20 then
      raise exception 'PROVA C6 FALHOU: ligado devia dar 20, deu %', v_n; end if;

    -- 7) expira sozinho
    update public.restaurants set busy_until = now() - interval '1 minute' where id = v_rest;
    if public.partner_busy_extra_minutes(v_rest) <> 0 then
      raise exception 'PROVA C6 FALHOU: expirado devia dar 0'; end if;

    -- 8) loja que não existe
    if public.partner_busy_extra_minutes('__nao_existe__') <> 0 then
      raise exception 'PROVA C6 FALHOU: loja inexistente devia dar 0'; end if;

    -- 9) sem sessão as funções de parceiro recusam
    v_r := public.partner_set_busy(v_rest, 20);
    if (v_r ->> 'ok') <> 'false' or (v_r ->> 'error') <> 'forbidden' then
      raise exception 'PROVA C6 FALHOU: sem sessao partner_set_busy devia recusar, deu %', v_r; end if;
    v_r := public.partner_set_ready_at('__nao_existe__', now() + interval '10 minutes');
    if (v_r ->> 'error') <> 'pedido_nao_encontrado' then
      raise exception 'PROVA C6 FALHOU: partner_set_ready_at devia dizer pedido_nao_encontrado, deu %', v_r; end if;

    -- 10) o admin-list recusa quem não é admin
    begin
      perform public.admin_partner_busy_list();
      raise exception 'PROVA C6 FALHOU: admin_partner_busy_list deixou passar sem ser admin';
    exception when others then
      if sqlerrm like 'PROVA C6 FALHOU%' then raise; end if;
    end;

    -- 11) o limite 0..60 está na base
    begin
      update public.restaurants set busy_extra_minutes = 99 where id = v_rest;
      raise exception 'PROVA C6 FALHOU: aceitou busy_extra_minutes = 99';
    exception when check_violation then
      null;
    end;

    raise notice 'PROVA C6 MIGRACAO OK';
    raise exception 'PROVA_DESFEITA';
  exception when others then
    if sqlerrm <> 'PROVA_DESFEITA' then raise; end if;
  end;
end $prova$;
