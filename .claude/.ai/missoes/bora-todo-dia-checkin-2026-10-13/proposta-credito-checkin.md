# Check-in diário — a função que dá os tokens (PROPOSTA, à espera do "vai")

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Data: 13/10/2026. Missão "Bora Todo Dia", novidade n.º 1.

O que faz, em palavras simples: quando o cliente carrega em "Fazer check-in", esta função
grava o check-in do dia e põe os tokens do dia na conta dele, as duas coisas na mesma
transação (ou entram as duas, ou nenhuma). Um toque repetido no mesmo dia não dá nada.

Porque está aqui e não aplicada: insere em `bora_tokens` — zona protegida (PADRAO_BORA §6,
CEO-AI Lista Vermelha). A bora-tranca recusa gravar uma migração com esse nome. Só se
aplica depois do "vai" do Danilo. Também vêm aqui os dois VALORES em tokens
(`checkin_rewards` e `checkin_token_expiry_days`): a 13/10 a bora-tranca bloqueou a
migração da base por os ter ("platform_settings financeiro"), e com razão — são dinheiro.

O que já está aplicado e de que esta função depende (migração
`supabase/migrations/20261013060000_checkin_diario_base.sql`): a tabela `daily_checkins`,
as definições `checkin_*`, `_checkin_estado`, `_checkin_premios`,
`_checkin_telemovel_confirmado`, `_checkin_e_cliente` e `client_checkin_status`.
**Enquanto esta função não existir, o check-in está desligado sozinho**: o cartão não
aparece na app e os lembretes não saem (`_checkin_estado` exige `client_daily_checkin()`
criada para dizer `enabled=true`). Aplicar esta função liga tudo de uma vez, sem nova
versão da app.

Diferença em relação à ordem, e porquê: a ordem pedia `source_order_id = 'checkin-AAAA-MM-DD'`.
Em produção há um índice único `idx_bora_tokens_order_role (source_order_id, role)` — com o
mesmo texto para todos, o segundo cliente do dia dava erro. Segue-se o padrão do BEMVINDO
(`bonus-bemvindo-AAAAMMDD-<uid>`): `checkin-AAAA-MM-DD-<uid>`. Continua a começar por
`checkin-AAAA-MM-DD`, que é o que o painel e as contas procuram.

O dar e tirar tokens no painel usa as funções que já existem e já registam em
`admin_audit_log` (`admin_grant_tokens`, `admin_revoke_token_grant`) — nada novo de dinheiro.

Prova local (PGlite, base falsa com o índice único real): ver `prova_pglite.saida.txt`.

```sql
-- Valores em tokens do check-in (o painel muda-os depois, com motivo, por admin_update_money_setting).
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('checkin_rewards', '[5,5,10,10,15,15,40]'::jsonb,
   'Tokens de cada dia do ciclo de 7 dias do check-in diário (Dia 1 a Dia 7).', 'tokens'),
  ('checkin_token_expiry_days', '60'::jsonb,
   'Validade, em dias, dos tokens ganhos no check-in diário.', 'tokens')
ON CONFLICT (key) DO NOTHING;

-- client_daily_checkin(): grava o check-in de hoje (Lisboa) e credita os tokens do dia.
CREATE OR REPLACE FUNCTION public.client_daily_checkin()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_validade integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings
                                   WHERE key = 'checkin_token_expiry_days'), 60);
  v_estado   jsonb;
  v_premios  integer[];
  v_dia      integer;
  v_tokens   integer;
  v_id       uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao', 'tokens_awarded', 0);
  END IF;

  -- Dois toques seguidos (ou dois aparelhos) da mesma pessoa esperam um pelo outro.
  PERFORM pg_advisory_xact_lock(hashtextextended('checkin:' || v_uid::text, 0));

  v_estado := public._checkin_estado(v_uid);

  IF (v_estado ->> 'already_done')::boolean THEN
    RETURN v_estado || jsonb_build_object('ok', true, 'already_done', true, 'tokens_awarded', 0,
                                          'balance', public.get_user_tokens(v_uid));
  END IF;

  IF NOT (v_estado ->> 'eligible')::boolean THEN
    RETURN v_estado || jsonb_build_object('ok', false, 'tokens_awarded', 0);
  END IF;

  v_premios  := public._checkin_premios();
  v_dia      := (v_estado ->> 'streak_day')::integer;
  v_tokens   := v_premios[v_dia];
  v_validade := LEAST(GREATEST(v_validade, 1), 365);

  INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded)
  VALUES (v_uid, v_hoje, v_dia, v_tokens)
  ON CONFLICT ON CONSTRAINT daily_checkins_um_por_dia DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN public._checkin_estado(v_uid) || jsonb_build_object('ok', true, 'already_done', true,
             'tokens_awarded', 0, 'balance', public.get_user_tokens(v_uid));
  END IF;

  IF v_tokens > 0 THEN
    INSERT INTO public.bora_tokens (user_id, role, amount, expires_at, source_order_id)
    VALUES (v_uid, 'client', v_tokens, now() + make_interval(days => v_validade),
            'checkin-' || to_char(v_hoje, 'YYYY-MM-DD') || '-' || v_uid::text);
  END IF;

  RETURN public._checkin_estado(v_uid) || jsonb_build_object('ok', true, 'already_done', false,
           'tokens_awarded', v_tokens, 'balance', public.get_user_tokens(v_uid));
END;
$function$;

REVOKE ALL ON FUNCTION public.client_daily_checkin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_daily_checkin() TO authenticated;
```

Como se aplica, depois do "vai": colar o bloco acima numa migração
`supabase/migrations/20261013070000_checkin_diario_credito.sql` (ou pelo `apply_migration`
da Claude.ai). Prova a seguir, em produção, com o JWT de uma conta demo, dentro de
`DO $$ … RAISE EXCEPTION 'PROVA %' … $$` (tudo revertido): ver o guião em
`prova-producao-depois-do-vai.md`.
