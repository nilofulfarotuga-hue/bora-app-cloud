-- Ronda 04/10 A.1: o reconciliador (v4) preenche orders.stripe_charge_cents a partir da Stripe.
-- Corre o modo "cobrancas" de 10 em 10 minutos (o resto continua no cron diário das 05:45).
create or replace function public.run_payments_reconciler_cobrancas()
returns bigint language plpgsql security definer set search_path to 'public' as $f$
declare v_url text; v_key text; v_req bigint;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name='project_url' limit 1;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='service_role_key' limit 1;
  if v_url is null or v_key is null then
    raise warning '[run_payments_reconciler_cobrancas] vault secrets em falta';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/payments-reconciler',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := '{"modo":"cobrancas"}'::jsonb,
    timeout_milliseconds := 55000
  ) into v_req;
  return v_req;
end $f$;
revoke all on function public.run_payments_reconciler_cobrancas() from public, anon, authenticated;
select cron.schedule('payments-reconciler-cobrancas', '*/10 * * * *', 'select public.run_payments_reconciler_cobrancas()');
