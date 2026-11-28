-- 28/11/2026 — prémios do check-in, Bloco A: os robôs (suporte e Amigo) passam a explicar que o prémio
-- de limpeza/lavagem entra na MARCAÇÃO NORMAL (migração 20261128172054, app deste ramo).
-- Só texto; nenhum valor de dinheiro muda. Idempotente. Backup antes.
-- Quem aplica: a Claude.ai, por MCP, DEPOIS de a app estar publicada nas 3 (senão o robô explica um
-- botão que o cliente ainda não tem). Depois copiar para supabase/migrations/<versão>_robos_premios_checkin.sql.

create table if not exists public.bkp_support_skills_20261128_premios as
  select * from public.support_skills where skill_name = 'CHECKIN_MARCOS_PREMIOS';

do $$
declare
  v_horas int := 2;
  v_hora_cents int := coalesce((select (value #>> '{}')::int from public.platform_settings
                                 where key = 'cleaning_hourly_cents'), 1200);
  v_valor text;
  v_novo text;
begin
  v_valor := replace(to_char(v_horas * v_hora_cents / 100.0, 'FM990D00'), '.', ',') || ' €';
  v_novo := E'- Prémio dos 30 dias (desde 28/11/2026): entra na **marcação normal**. Ao marcar uma limpeza, o resumo mostra '
    || E'"Tens ' || v_horas || E' h de limpeza grátis (prémio do check-in)" já ligado: desconta ' || v_valor
    || E' (' || v_horas || E' horas de limpeza Standard). O cliente pode marcar mais horas e paga só as que passam do prémio. '
    || E'Na Profunda e na Pós-obras o prémio paga ' || v_horas || E' h Standard e o cliente paga a diferença. '
    || E'Na lavagem o prémio paga a lavagem só por fora; a completa ou só por dentro pagam a diferença. '
    || E'A taxa de deslocação, se houver, paga-se à parte. Se o prémio cobrir tudo, não se paga nada. '
    || E'Também dá para ir por "Os meus prémios" → "Escolher". A limpeza segue a antecedência normal da app.';

  -- troca a linha antiga (marcação à parte, 12 h de antecedência) pela nova; se já não existir, junta a secção uma vez
  update public.support_skills
     set playbook_md = regexp_replace(playbook_md,
           E'- Prémio dos 30 dias: toca em \\*\\*"Escolher"\\*\\*[^\\n]*\\n[^\\n]*antecedência\\.',
           v_novo),
         version = version + 1, updated_at = now()
   where skill_name = 'CHECKIN_MARCOS_PREMIOS'
     and playbook_md ~ E'- Prémio dos 30 dias: toca em \\*\\*"Escolher"\\*\\*';

  update public.support_skills
     set playbook_md = playbook_md || E'\n## Prémio dos 30 dias na marcação normal\n' || v_novo || E'\n',
         version = version + 1, updated_at = now()
   where skill_name = 'CHECKIN_MARCOS_PREMIOS'
     and playbook_md not like '%entra na **marcação normal**%';

  -- Amigo / assistente: respostas aprendidas (só se ainda não existirem)
  insert into public.assistant_learned (question_norm, question, answer, source, kind, active)
  select x.qn, x.q, x.a, 'admin', 'resposta', true
    from (values
      ('como uso o meu premio de limpeza do check in',
       'Como uso o meu prémio de limpeza do check-in?',
       'Marca a limpeza como sempre (Limpeza → Só uma vez). No resumo aparece "Tens ' || v_horas
         || ' h de limpeza grátis (prémio do check-in)" já ligado: desconta ' || v_valor
         || '. Podes marcar mais horas e pagas só as que passam do prémio. Na Profunda ou na Pós-obras pagas só a diferença.'),
      ('posso marcar mais horas com o premio da limpeza',
       'Posso marcar mais horas com o prémio da limpeza?',
       'Podes. O prémio paga ' || v_horas || ' horas de limpeza Standard (' || v_valor
         || ') e tu pagas só as horas a mais, em dinheiro, cartão ou MB Way.'),
      ('como uso o premio da lavagem do carro',
       'Como uso o prémio da lavagem do carro?',
       'Pede a lavagem como sempre. No fim aparece "Tens uma lavagem por fora grátis (prémio do check-in)" já ligado. Se escolheres a lavagem por fora, não pagas nada; a completa ou só por dentro pagam a diferença.')
    ) as x(qn, q, a)
   where not exists (select 1 from public.assistant_learned l where l.question_norm = x.qn);
end $$;
