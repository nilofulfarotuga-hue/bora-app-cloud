-- ia_claude_sem_racao_2026_11_01
-- Missao infra-claude-tudo-2026-11-01 (Danilo 01/11 19:56: "sem limite ... nunca ficar sem").
-- A regra das Edge Functions passa a ser a do porteiro da VPS: SEM RACAO. Enquanto houver credito,
-- P1, P2 e P3 usam o Claude, sem parte do dia. Quem diz que o credito acabou e a API: uma falha
-- "sem credito" (402 / 400 credit balance) registada em ia_gastos nas ultimas 6 h, sem nenhuma resposta
-- boa depois dela, manda tudo para o Gemini de cada funcao; 6 h depois tenta outra vez sozinho.
-- A racao antiga continua aqui e liga-se no painel com claude_robos.racao = true.
-- Nada aqui mexe em precos, comissoes, ganhos, Stripe, carteira, tokens, pedidos nem estafetas.
create or replace function public.ia_claude_pode(p_prioridade int, p_robo text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_credito   numeric := coalesce((select (value #>> '{}')::numeric from platform_settings where key = 'claude_credito_atual_usd'), 0);
  v_lido      timestamptz := coalesce((select (value #>> '{}')::timestamptz from platform_settings where key = 'claude_credito_lido_em'), now());
  v_proximo   date := coalesce((select (value #>> '{}')::date from platform_settings where key = 'claude_proximo_credito'), (current_date + 30));
  v_robos     jsonb := coalesce((select value from platform_settings where key = 'claude_robos'), '{}'::jsonb);
  v_racao     boolean := coalesce((v_robos ->> 'racao')::boolean, false);
  v_hoje_lx   date := (now() at time zone 'Europe/Lisbon')::date;
  v_gasto     numeric;
  v_gasto_dia numeric;
  v_resta     numeric;
  v_dias      int;
  v_parte     numeric;
  v_limite    numeric;
  v_pode      boolean;
  v_motivo    text;
  v_modelo    text;
  v_sem_saldo timestamptz;
  v_ultimo_ok timestamptz;
begin
  select coalesce(sum(custo_usd), 0) into v_gasto from ia_gastos where quando >= v_lido;
  select coalesce(sum(custo_usd), 0) into v_gasto_dia from ia_gastos
   where (quando at time zone 'Europe/Lisbon')::date = v_hoje_lx;
  v_resta := v_credito - v_gasto;
  v_dias  := greatest(1, v_proximo - v_hoje_lx);
  v_parte := greatest(0, v_resta + v_gasto_dia) / v_dias;
  v_modelo := coalesce(v_robos -> p_robo ->> 'modelo', case when p_prioridade <= 2 then 'claude-sonnet-5-5' else 'claude-haiku-5-5' end);
  if v_modelo like 'claude-opus%' then v_modelo := 'claude-sonnet-5-5'; end if;   -- Opus nunca automatico

  -- a API disse "sem credito" nas ultimas 6 h e ainda nao houve resposta boa depois disso?
  select max(quando) into v_sem_saldo from ia_gastos
   where ok = false and quando > now() - interval '6 hours'
     and (erro ilike '%sem credito%' or erro ilike '%credit balance%' or erro ilike 'http 402%');
  select max(quando) into v_ultimo_ok from ia_gastos
   where ok = true and quando > now() - interval '6 hours';

  if coalesce((v_robos ->> 'ligado')::boolean, true) = false then
    v_pode := false; v_motivo := 'Claude desligado no painel';
  elsif p_robo is not null and (v_robos -> p_robo) is not null and coalesce((v_robos -> p_robo ->> 'usar')::boolean, true) = false then
    v_pode := false; v_motivo := 'Claude desligado para este robo';
  elsif v_sem_saldo is not null and (v_ultimo_ok is null or v_ultimo_ok < v_sem_saldo) then
    v_pode := false;
    v_motivo := 'sem credito na API desde ' || to_char(v_sem_saldo at time zone 'Europe/Lisbon', 'DD/MM HH24:MI') || ' (tenta outra vez 6 h depois)';
  elsif not v_racao then
    v_pode := true; v_motivo := 'sem racao: Claude enquanto houver credito (P' || p_prioridade || ')';
  elsif v_resta <= 0 then
    v_pode := false; v_motivo := 'credito do mes acabado';
  elsif p_prioridade <= 1 then
    v_pode := true; v_motivo := 'P1 usa enquanto houver credito';
  else
    v_limite := case when p_prioridade = 2 then v_parte else v_parte * 0.5 end;
    v_pode := v_gasto_dia < v_limite;
    v_motivo := case when v_pode then 'dentro da parte do dia' else 'parte do dia esgotada para P' || p_prioridade end;
  end if;

  return jsonb_build_object('pode', v_pode, 'motivo', v_motivo, 'modelo', v_modelo, 'racao', v_racao,
    'resta_usd', round(v_resta, 4), 'gasto_hoje_usd', round(v_gasto_dia, 4),
    'parte_do_dia_usd', round(v_parte, 4), 'dias_ate_proximo', v_dias);
end;
$$;
revoke all on function public.ia_claude_pode(int, text) from public, anon, authenticated;
grant execute on function public.ia_claude_pode(int, text) to service_role;
comment on function public.ia_claude_pode(int, text) is 'Porteiro do credito do Claude para as Edge Functions. Desde 01/11/2026 SEM RACAO (claude_robos.racao=false): tudo pelo Claude ate a API dizer sem credito (falha em ia_gastos nas ultimas 6 h).'
