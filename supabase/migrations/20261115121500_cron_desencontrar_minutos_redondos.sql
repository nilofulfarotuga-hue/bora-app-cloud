-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115121500); antes estava no repo como 20261115020100_cron_desencontrar_minutos_redondos.sql
-- Acertado ao que correu: a versão aplicada não tem a linha RAISE NOTICE 'cron %: passa a "%"' dentro do
-- ciclo (tirada daqui); o resto do SQL é igual ao gravado no servidor, só comentários e espaços diferem.

-- Missão fechar-app-15-11 — Bloco 3 (h).
--
-- "remaining connection slots are reserved for roles with the SUPERUSER
-- attribute" — quem esgota as ligações são as tarefas agendadas (pg_cron),
-- todas a arrancar no mesmo segundo dos minutos redondos.
--
-- MEDIDO em produção a 14/11/2026:
--   * max_connections = 60, 3 reservadas → 57 para toda a gente.
--   * Em repouso já estão ocupadas 28 (API 16, tempo-real 6, ficheiros 3,
--     outras 3) — medido às 23 h, sem movimento.
--   * cron.use_background_workers = off → cada tarefa abre uma ligação NOVA.
--   * Ao minuto :00 arrancam 39 tarefas no mesmo segundo; ao :30, 36;
--     aos :10/:20/:40/:50, 26 a 29. (28 + 36 = 64 > 57.)
--   * Registos de 24 h: 75 recusas de ligação, TODAS aos minutos :00, :10,
--     :20, :30 e :40, todas do papel das tarefas agendadas (uma apanhou o
--     serviço de ficheiros).
--   * Em 47 h o pg_cron perdeu 273 corridas (156 "connection failed" + 117
--     "job startup timeout"). Às 18:30 de 14/11: 15 tarefas não arrancaram, as
--     outras demoraram ~18 s em vez de 0,05 s, e as varreduras de 15 s ficaram
--     20 s sem correr.
--
-- O QUE ESTA MIGRAÇÃO FAZ: tira dos minutos redondos 10 tarefas que só
-- AVISAM ou ARRUMAM (lembretes, catálogo, índices de pesquisa, registos) e
-- põe-nas uns minutos ao lado. Mesma frequência, mesmo comando, mesma função.
-- Nenhuma delas olha para o minuto em que corre (todas usam janelas a partir
-- de now()).
--
-- O QUE NÃO FAZ: não toca em NENHUMA tarefa de dinheiro nem de despacho
-- (pagamentos, reembolsos, gorjetas, acertos, ofertas, estafetas). Essas
-- ficam onde estão; o resto do desencontro está PROPOSTO, à espera de ordem,
-- em docs/propostas/fechar-app-15-11/3deh-servidor.md.
--
-- Efeito (prova: supabase/tests/fechar_app_3h_prova.mjs): o pior minuto de
-- cada hora desce de 39 arranques para 29, e o :30 de 36 para 27. ALIVIA mas
-- não fecha: na conta do pior caso o :00 ainda passa do que cabe (29). Com a
-- proposta das tarefas de dinheiro o pior minuto fica em 17 e passa a caber.
--
-- Repetível e cuidadosa: só mexe numa tarefa se ela ainda tiver o horário
-- antigo. Tarefa que não exista, ou que alguém já tenha mudado, fica como está.

DO $desencontrar$
DECLARE
  r   record;
  v_n integer := 0;
BEGIN
  FOR r IN
    SELECT j.jobid, j.jobname, m.novo
      FROM (VALUES
        -- de 2 em 2 minutos: passam dos minutos pares para os ímpares
        ('embeddings-gte-manter',       '*/2 * * * *',  '1-59/2 * * * *'),
        ('drivers-sem-sinal-avisar',    '*/2 * * * *',  '1-59/2 * * * *'),
        -- de 5 em 5: 1, 6, 11, …
        ('tvde-work-log-sweep',         '*/5 * * * *',  '1-59/5 * * * *'),
        -- de 10 em 10: 4, 14, 24, …
        ('produtos-esgotados-voltam',   '*/10 * * * *', '4-59/10 * * * *'),
        -- de 15 em 15: 7, 22, 37, 52
        ('reservas_pro_reminders_2h',   '*/15 * * * *', '7-59/15 * * * *'),
        ('carrinhos-abandonados-15min', '*/15 * * * *', '7-59/15 * * * *'),
        -- de 30 em 30: 9 e 39
        ('reservas_pro_reminders_24h',  '*/30 * * * *', '9-59/30 * * * *'),
        ('appt-reminders-2h',           '*/30 * * * *', '9-59/30 * * * *'),
        ('cleaning-reminders-2h',       '*/30 * * * *', '9-59/30 * * * *'),
        -- de hora a hora: ao minuto 11 em vez do 0
        ('reservas_pro_expire_lists',   '0 * * * *',    '11 * * * *')
      ) AS m(jobname, antigo, novo)
      JOIN cron.job j ON j.jobname = m.jobname AND j.schedule = m.antigo
  LOOP
    -- UPDATE direto em cron.job dá permission denied — sempre cron.alter_job.
    PERFORM cron.alter_job(r.jobid, schedule := r.novo);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'tarefas desencontradas nesta corrida: %', v_n;
END
$desencontrar$;

-- ROLLBACK (voltar aos minutos redondos): o mesmo bloco com as colunas
-- "antigo" e "novo" trocadas. Nada se perde: só muda o minuto.
--
-- VERIFICAR depois de aplicar (deve devolver 10 linhas, nenhuma em minuto redondo):
--   select jobname, schedule from cron.job
--    where jobname in ('embeddings-gte-manter','drivers-sem-sinal-avisar','tvde-work-log-sweep',
--      'produtos-esgotados-voltam','reservas_pro_reminders_2h','carrinhos-abandonados-15min',
--      'reservas_pro_reminders_24h','appt-reminders-2h','cleaning-reminders-2h','reservas_pro_expire_lists')
--    order by 1;
