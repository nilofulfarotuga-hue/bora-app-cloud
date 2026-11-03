-- JÁ APLICADA EM PRODUÇÃO pela Claude.ai por MCP a 03/11/2026 11:52-12:15 (missão boom-hamburguer-mes,
-- autorização do Danilo de 03/11 11:51: "Eu autorizo 1, 2 e o 3."). Este ficheiro é o espelho no repo,
-- tirado de produção com pg_get_functiondef às 12:20. Idempotente; não é preciso voltar a correr.
-- 1) aviso de carrinho esquecido ligado; 2) nunca a contas demo nem às do Danilo;
-- 3) texto verdadeiro quando a loja ficou mais barata depois do carrinho (tabela lojas_mais_baratas).

create table if not exists public.lojas_mais_baratas (
  id bigserial primary key,
  loja_id text not null,
  mudou_em timestamptz not null default now(),
  valido_ate timestamptz,
  titulo text not null,
  texto text not null,
  criado_por text default 'claude-ai'
);
alter table public.lojas_mais_baratas enable row level security;
drop policy if exists lojas_mais_baratas_admin on public.lojas_mais_baratas;
create policy lojas_mais_baratas_admin on public.lojas_mais_baratas
  for all using (public.is_admin()) with check (public.is_admin());
comment on table public.lojas_mais_baratas is
  'Avisos "o teu carrinho ficou mais barato": quando uma loja baixou a entrega ou tirou a taxa de pedido pequeno. '
  'O aviso de carrinho esquecido usa a linha mais recente posterior ao carrinho e ainda válida. Só admin.';

insert into public.platform_settings (key, value)
values ('carrinho_abandonado_excluir_emails',
        '["nilofulfarotuga@gmail.com", "boraappbora@gmail.com", "%@bora.app"]'::jsonb)
on conflict (key) do nothing;
update public.platform_settings set value = 'true'::jsonb where key = 'carrinho_abandonado_ligado';

-- O aviso do Fuku de 03/11 (válido 3 dias).
insert into public.lojas_mais_baratas (loja_id, mudou_em, valido_ate, titulo, texto)
select 'fuku-sushi-guarda', '2026-11-03 11:53:59.795389+00', '2026-11-06 11:53:59.795389+00',
       'O teu carrinho do {loja} ficou mais barato',
       'Já não pagas a taxa de pedido pequeno e, a partir de 22 €, a entrega é grátis. Toca para terminar o pedido.'
where not exists (select 1 from public.lojas_mais_baratas where loja_id = 'fuku-sushi-guarda'
                    and mudou_em = '2026-11-03 11:53:59.795389+00');

CREATE OR REPLACE FUNCTION public.carrinhos_abandonados_avisar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ligado  boolean;
  v_minutos integer;
  v_titulo  text;
  v_texto   text;
  v_url     text;
  v_key     text;
  r         record;
  v_n       integer := 0;
  v_corpo   text;
  v_tit     text;
  v_excl    jsonb;
  m         record;
BEGIN
  SELECT COALESCE((value::text)::boolean, false) INTO v_ligado
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_ligado';
  IF COALESCE(v_ligado, false) IS NOT TRUE THEN RETURN 0; END IF;

  SELECT (value::text)::integer INTO v_minutos
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_minutos';
  v_minutos := GREATEST(COALESCE(v_minutos, 60), 5);
  SELECT value #>> '{}' INTO v_titulo
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_titulo';
  SELECT value #>> '{}' INTO v_texto
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_texto';
  SELECT value INTO v_excl
    FROM public.platform_settings WHERE key = 'carrinho_abandonado_excluir_emails';
  v_excl := COALESCE(v_excl, '[]'::jsonb);
  v_titulo := COALESCE(NULLIF(v_titulo, ''), 'Ficou alguma coisa no teu carrinho 🛒');
  v_texto  := COALESCE(NULLIF(v_texto, ''), 'O teu pedido de {loja} está à tua espera. Toca para terminar.');

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_url := NULL; v_key := NULL; END;

  FOR r IN
    SELECT c.*
      FROM public.carrinhos_abandonados c
     WHERE c.n_itens > 0
       AND c.convertido_em IS NULL
       AND c.avisado_em IS NULL
       AND c.atualizado_em < now() - make_interval(mins => v_minutos)
       AND c.atualizado_em > now() - interval '3 days'
       AND (c.ultimo_aviso_em IS NULL OR c.ultimo_aviso_em < now() - interval '24 hours')
       AND NOT EXISTS (SELECT 1 FROM public.orders o
                        WHERE o.user_id = c.user_id
                          AND o.created_at > c.atualizado_em - interval '2 minutes')
       AND NOT public.is_demo_user(c.user_id)
       AND NOT EXISTS (SELECT 1 FROM auth.users u, jsonb_array_elements_text(v_excl) pat
                        WHERE u.id = c.user_id AND lower(u.email) LIKE lower(pat))
     ORDER BY c.atualizado_em
     LIMIT 200
     FOR UPDATE OF c SKIP LOCKED
  LOOP
    v_tit   := v_titulo;
    v_corpo := replace(v_texto, '{loja}', COALESCE(NULLIF(r.loja, ''), 'Bora'));
    SELECT lm.titulo, lm.texto INTO m
      FROM public.lojas_mais_baratas lm
     WHERE lm.loja_id = r.loja_id
       AND lm.mudou_em > r.atualizado_em
       AND (lm.valido_ate IS NULL OR lm.valido_ate > now())
     ORDER BY lm.mudou_em DESC LIMIT 1;
    IF FOUND THEN
      v_tit   := replace(m.titulo, '{loja}', COALESCE(NULLIF(r.loja, ''), 'Bora'));
      v_corpo := replace(m.texto,  '{loja}', COALESCE(NULLIF(r.loja, ''), 'Bora'));
    END IF;

    UPDATE public.carrinhos_abandonados
       SET avisado_em = now(), ultimo_aviso_em = now()
     WHERE user_id = r.user_id;
    BEGIN
      PERFORM public._push_in_app_notification(r.user_id, 'carrinho_abandonado', v_tit, v_corpo, r.loja_id);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
          body := jsonb_build_object('clientId', r.user_id::text, 'title', v_tit, 'body', v_corpo,
                                     'kind', 'carrinho_abandonado', 'type', 'carrinho_abandonado')
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;
revoke all on function public.carrinhos_abandonados_avisar() from public, anon, authenticated;
