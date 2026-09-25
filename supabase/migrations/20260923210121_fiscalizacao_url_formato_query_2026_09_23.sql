-- motorista-ficha-legal-2026-09-23 · o QR passa a usar /verificar/?t=<token>.
-- Provado por pg_net às 21:00 UTC: /verificar/<token> devolvia a página 404 do
-- bora-site (a regra _redirects do Cloudflare Pages não pegou), enquanto
-- /verificar/?t=<token> serve a página e chama verificar_ficha_publica.
-- Já tinha sido mudado por admin_update_setting (auditado); isto só regista
-- o valor no repo. Idempotente.
update public.platform_settings
   set value = to_jsonb('https://boraguarda.com/verificar/?t='::text), updated_at = now()
 where key = 'fiscalizacao_verificar_base_url'
   and value is distinct from to_jsonb('https://boraguarda.com/verificar/?t='::text);
