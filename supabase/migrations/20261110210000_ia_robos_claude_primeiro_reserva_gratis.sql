-- 20261110210000_ia_robos_claude_primeiro_reserva_gratis.sql
-- Missão fechar-tudo-2026-11-10, bloco H (agente-h). NÃO aplicado por este agente: o líder aplica.
--
-- Os robôs que liam com o Gemini do projeto Google "bora-juiz" (conta de pagamento vencida, 402) passam
-- a usar o módulo supabase/functions/_shared/ia_visao.ts: Claude primeiro, rotação grátis de reserva,
-- erro claro. A reserva grátis também escreve em public.ia_gastos (modelo "<motor>:<modelo>", custo 0).
--
-- 1. public.ia_claude_pode: "sem crédito" e "última resposta boa" passam a olhar SÓ para as linhas do
--    Claude (modelo like 'claude-%'). Sem isto, uma resposta boa da reserva grátis acordava o Claude logo
--    a seguir a ele dizer "sem crédito" (cada pedido batia primeiro no Claude e só depois descia), e um
--    402 de um motor grátis podia parecer "sem crédito do Claude". O resto da função fica igual.
-- 2. platform_settings.claude_robos: os robôs novos aparecem no painel (Motores → Crédito Claude) com o
--    interruptor "usar Claude". Só acrescenta chaves que ainda não existem (o que lá está ganha).
-- 3. Comentário de public.ia_gastos atualizado.
--
-- Reversível: voltar a aplicar a definição de 20261101204928_ia_claude_sem_racao_2026_11_01.sql e tirar
-- as chaves novas de claude_robos.

create or replace function public.ia_claude_pode(p_prioridade integer, p_robo text default null::text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
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

  -- a API do Claude disse "sem credito" nas ultimas 6 h e ainda nao houve resposta boa DO CLAUDE depois disso?
  -- (10/11/2026: so linhas do Claude; as da reserva gratis tem modelo "<motor>:<modelo>")
  select max(quando) into v_sem_saldo from ia_gastos
   where ok = false and quando > now() - interval '6 hours'
     and modelo like 'claude-%'
     and (erro ilike '%sem credito%' or erro ilike '%credit balance%' or erro ilike 'http 402%');
  select max(quando) into v_ultimo_ok from ia_gastos
   where ok = true and quando > now() - interval '6 hours'
     and modelo like 'claude-%';

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
$function$;

comment on function public.ia_claude_pode(int, text) is
  'Porteiro do credito do Claude para as Edge Functions. Desde 01/11/2026 SEM RACAO (claude_robos.racao=false): tudo pelo Claude ate a API dizer sem credito (falha em ia_gastos nas ultimas 6 h). Desde 10/11/2026 so conta linhas do Claude (modelo like claude-%), nunca as da reserva gratis.';

-- Os privilegios da funcao nao mudam com create or replace (continua como estava: servidor).

-- 2. Robôs novos no painel (só chaves que ainda não existem: o que já lá está ganha).
update public.platform_settings
   set value = jsonb_build_object(
         'edge-documentos', jsonb_build_object(
           'nome', 'Fiscal de documentos (estafetas e prestadores; Haiku, duvida -> Sonnet; sem motor gratis)',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-documentos-previa', jsonb_build_object(
           'nome', 'Fiscal de documentos na hora (app do candidato; sem motor gratis)',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-ocr-talao', jsonb_build_object(
           'nome', 'Leitura dos taloes (Haiku, vazio -> Sonnet; sem motor gratis: NIF do cliente)',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-etiquetas-menu', jsonb_build_object(
           'nome', 'Etiquetas do menu (vegetariano, picante, sem gluten)',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-resumo-avaliacoes', jsonb_build_object(
           'nome', 'Resumo das avaliacoes para o parceiro',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-analise-suporte', jsonb_build_object(
           'nome', 'Analise semanal das conversas do suporte (propostas de skills)',
           'usar', true, 'modelo', 'claude-haiku-5-5', 'prioridade', 3),
         'edge-suporte-humano', jsonb_build_object(
           'nome', 'Falar com humano (persona do suporte)',
           'usar', true, 'modelo', 'claude-sonnet-5-5', 'prioridade', 1)
       ) || value,
       updated_at = now()
 where key = 'claude_robos';

-- 3. O livro passa a ter também a reserva grátis.
comment on table public.ia_gastos is
  'Livro de gastos de IA (porteiro do credito, missao motor-claude 31/10/2026). Uma linha por chamada: Claude (VPS e Edge Functions, com custo) e, desde 10/11/2026, a reserva gratis das Edge (_shared/ia_visao.ts: modelo "<motor>:<modelo>", custo 0). Escrito com a service role.';
