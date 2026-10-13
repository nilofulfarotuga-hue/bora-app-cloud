# Prova em produção do check-in diário — correr DEPOIS de aplicar as duas migrações

Ordem de aplicação (pela Claude.ai, depois do "vai" do Danilo):

1. `supabase/migrations/20261013060000_checkin_diario_base.sql` (sem dinheiro; a bora-tranca
   recusou-a na caixa a 13/10 — 2 tentativas, ver e2e_log fluxo `checkin_diario`).
2. O bloco SQL de `proposta-credito-checkin.md` (dinheiro: valores + `client_daily_checkin`),
   gravado como `supabase/migrations/20261013070000_checkin_diario_credito.sql`.

Depois, pelo `execute_sql`, esta prova (tudo revertido pelo RAISE no fim; nada fica gravado).
Conta: demo@bora.app (`d5b0c0a1-f49e-4593-a919-147edfc069c2`, telemóvel 920000000, cliente).
demo.cliente@bora.app (`e3c166d2-5e20-4d2d-b4d9-fcd4867805a5`) não tem telemóvel — serve para
o caso "sem telemóvel".

```sql
DO $$
DECLARE
  v_demo uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  v_semtel uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_out jsonb := '{}';
  r jsonb;
BEGIN
  -- limpar o histórico da demo só dentro desta transação
  DELETE FROM public.daily_checkins WHERE user_id IN (v_demo, v_semtel);

  PERFORM set_config('request.jwt.claim.sub', v_demo::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_demo, 'role', 'authenticated')::text, true);
  v_out := v_out || jsonb_build_object('estado_antes', public.client_checkin_status());

  -- dia 1
  r := public.client_daily_checkin();
  v_out := v_out || jsonb_build_object('dia1', r);
  -- repetido no mesmo dia
  v_out := v_out || jsonb_build_object('repetido', public.client_daily_checkin());
  v_out := v_out || jsonb_build_object('linhas_tokens_hoje',
    (SELECT count(*) FROM public.bora_tokens WHERE user_id = v_demo
      AND source_order_id = 'checkin-' || to_char(v_hoje, 'YYYY-MM-DD') || '-' || v_demo::text));

  -- dia seguido: ontem Dia 2 → hoje Dia 3 (10)
  DELETE FROM public.daily_checkins WHERE user_id = v_demo;
  DELETE FROM public.bora_tokens WHERE user_id = v_demo AND source_order_id LIKE 'checkin-%';
  INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (v_demo, v_hoje - 1, 2, 5);
  v_out := v_out || jsonb_build_object('seguido', public.client_daily_checkin() -> 'streak_day');

  -- dia falhado: anteontem Dia 5 → hoje Dia 1
  DELETE FROM public.daily_checkins WHERE user_id = v_demo;
  DELETE FROM public.bora_tokens WHERE user_id = v_demo AND source_order_id LIKE 'checkin-%';
  INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (v_demo, v_hoje - 2, 5, 15);
  v_out := v_out || jsonb_build_object('falhado', public.client_daily_checkin() -> 'streak_day');

  -- dia 7 → 1
  DELETE FROM public.daily_checkins WHERE user_id = v_demo;
  DELETE FROM public.bora_tokens WHERE user_id = v_demo AND source_order_id LIKE 'checkin-%';
  INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (v_demo, v_hoje - 1, 7, 40);
  v_out := v_out || jsonb_build_object('depois_do_7', public.client_daily_checkin() -> 'streak_day');

  -- sem telemóvel
  PERFORM set_config('request.jwt.claim.sub', v_semtel::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_semtel, 'role', 'authenticated')::text, true);
  v_out := v_out || jsonb_build_object('sem_telemovel', public.client_daily_checkin());

  RAISE EXCEPTION 'PROVA %', v_out::text;
END $$;
```

O que tem de sair no `PROVA`: `estado_antes.enabled=true`, `dia1.tokens_awarded=5`,
`repetido.tokens_awarded=0`, `linhas_tokens_hoje=1`, `seguido=3`, `falhado=1`,
`depois_do_7=1`, `sem_telemovel.reason="sem_telemovel"` com `ok=false`.
Atenção: o `DELETE FROM bora_tokens` acima vive só dentro da transação revertida; a Trava
pode recusar o texto — se recusar, tira-se esse caso e prova-se o resto.
