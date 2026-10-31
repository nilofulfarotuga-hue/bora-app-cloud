-- 31/10/2026 — vigia diário das chaves, parte 3: horários (07:00 pings; 07:06 e 07:20 verificação). UTC = Lisboa no inverno.
select cron.schedule('saude_chaves_funcoes', '0 7 * * *', 'select public._cron_saude_chaves_funcoes();');
select cron.schedule('saude_chaves_verificar', '6 7 * * *', 'select public._cron_saude_chaves_verificar();');
select cron.schedule('saude_chaves_verificar_tarde', '20 7 * * *', 'select public._cron_saude_chaves_verificar();');
